-- Referral system (S4) — server-authoritative attribution, qualification,
-- and reward. Design: PHASE_1_REFERRAL_DESIGN.md. Product decisions:
--   qualifying event = referred user's first successful pass redemption
--   reward           = 200 XP referrer / 100 XP referred (two-sided)
--   cap              = max 15 rewarded referrals per referrer per 30 days
--
-- Every mutation is a SECURITY DEFINER RPC invoked only by the service role
-- (referral routes / the redeem route). Idempotency and fraud limits are
-- enforced by the database, not by application code — same posture already
-- used for passes (unique source index) and wallet (adjust_wallet_balance).
--
-- Points land in profiles.bpx_points (server column, already protected from
-- client writes by protect_profile_points). Run once in the Supabase SQL
-- editor.

-- ── Each user's own shareable code ────────────────────────────────────────
-- Its own table (not a profiles column) so it needs no client policy at all:
-- reads happen through the authenticated /api/referral/code route (service
-- role), never a direct client SELECT — same default-deny pattern as
-- venue_secrets / rate_limits / wallet_balances.
create table if not exists public.referral_codes (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  code       text unique not null,
  created_at timestamptz not null default now()
);
alter table public.referral_codes enable row level security;
-- Deliberately no policies — default-deny for anon/authenticated.

-- ── The referral ledger (the state machine) ───────────────────────────────
create table if not exists public.referrals (
  id                uuid primary key default gen_random_uuid(),
  referrer_id       uuid not null references auth.users(id) on delete cascade,
  referred_id       uuid not null references auth.users(id) on delete cascade,
  code              text not null,
  state             text not null default 'attributed'
                      check (state in ('attributed', 'qualified', 'reward_granted')),
  referrer_reward   int  not null default 0,
  referred_reward   int  not null default 0,
  created_at        timestamptz not null default now(),
  qualified_at      timestamptz,
  reward_granted_at timestamptz,

  -- A user can never refer themselves.
  constraint referrals_no_self check (referrer_id <> referred_id),
  -- A user can be referred at most once, ever. This unique constraint — not
  -- application logic — is what makes attribution idempotent and blocks
  -- re-attribution / attribution races at the database layer.
  constraint referrals_one_per_referred unique (referred_id)
);
create index if not exists referrals_referrer_idx on public.referrals (referrer_id);

alter table public.referrals enable row level security;
-- Owner-read only (either side of the referral); no client writes at all —
-- every mutation goes through the SECURITY DEFINER RPCs below.
drop policy if exists referrals_select on public.referrals;
create policy referrals_select on public.referrals
  for select using (auth.uid() = referrer_id or auth.uid() = referred_id);

-- ── RPC 1: get or create the caller's referral code (idempotent) ──────────
create or replace function public.get_or_create_referral_code(p_user_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  select code into v_code from public.referral_codes where user_id = p_user_id;
  if v_code is not null then
    return v_code;
  end if;

  -- Generate a random 8-char code, retrying only on the rare code collision.
  -- unique(user_id) collapses concurrent first-time calls to a single code.
  loop
    v_code := upper(substr(md5(gen_random_uuid()::text), 1, 8));
    begin
      insert into public.referral_codes (user_id, code) values (p_user_id, v_code);
      return v_code;
    exception when unique_violation then
      -- Either this user's row was created concurrently (return that code)
      -- or the code value collided (loop and pick another).
      select code into v_code from public.referral_codes where user_id = p_user_id;
      if v_code is not null then
        return v_code;
      end if;
    end;
  end loop;
end;
$$;

-- ── RPC 2: attribute a referral (state → attributed, idempotent) ──────────
-- Returns a short status string. Never raises for normal rejections so the
-- route can map them to a response without try/catch noise.
create or replace function public.attribute_referral(p_referred_id uuid, p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_referrer uuid;
  v_norm     text := upper(trim(p_code));
begin
  select user_id into v_referrer from public.referral_codes where code = v_norm;
  if v_referrer is null then
    return 'invalid_code';
  end if;
  if v_referrer = p_referred_id then
    return 'self_referral';
  end if;

  -- Idempotent + one-per-referred: a duplicate (or a second, different
  -- referrer) is silently dropped, the first attribution stands.
  insert into public.referrals (referrer_id, referred_id, code, state)
  values (v_referrer, p_referred_id, v_norm, 'attributed')
  on conflict (referred_id) do nothing;

  return 'attributed';
end;
$$;

-- ── RPC 3: qualify + reward on first pass redemption (idempotent core) ─────
-- Called from /api/passes/redeem with the redeemed pass's customer_id. Only
-- acts on a referral still in 'attributed', so a user's 2nd+ redemption is a
-- no-op automatically — "first redemption" needs no separate flag.
create or replace function public.qualify_and_reward_referral(p_referred_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ref            public.referrals;
  v_recent_rewards int;
begin
  -- Row-lock the candidate so two simultaneous redemptions can't both reward.
  select * into v_ref from public.referrals
    where referred_id = p_referred_id and state = 'attributed'
    for update;
  if not found then
    return; -- no pending referral, or already qualified/rewarded → no-op
  end if;

  -- Cap: at most 15 rewarded referrals per referrer in the last 30 days.
  select count(*) into v_recent_rewards from public.referrals
    where referrer_id = v_ref.referrer_id
      and state = 'reward_granted'
      and reward_granted_at > now() - interval '30 days';

  if v_recent_rewards >= 15 then
    -- Qualifying event happened, but the referrer is over the cap: record
    -- qualification (terminal for this referral) without granting points.
    -- Not retried later — the cap is evaluated at the qualifying moment.
    update public.referrals
      set state = 'qualified', qualified_at = now()
      where id = v_ref.id and state = 'attributed';
    return;
  end if;

  -- Atomic transition attributed → reward_granted. The state guard makes the
  -- points grant fire exactly once even under concurrent calls.
  update public.referrals
    set state = 'reward_granted',
        qualified_at = coalesce(qualified_at, now()),
        reward_granted_at = now(),
        referrer_reward = 200,
        referred_reward = 100
    where id = v_ref.id and state = 'attributed';

  if found then
    update public.profiles set bpx_points = bpx_points + 200 where id = v_ref.referrer_id;
    update public.profiles set bpx_points = bpx_points + 100 where id = v_ref.referred_id;
  end if;
end;
$$;

-- Server-only: only the referral routes and the redeem route (service role)
-- call these. Revoke direct execution from the shipped anon/authenticated
-- keys — same lockdown as adjust_wallet_balance / check_rate_limit.
revoke execute on function public.get_or_create_referral_code(uuid) from public, anon, authenticated;
revoke execute on function public.attribute_referral(uuid, text)    from public, anon, authenticated;
revoke execute on function public.qualify_and_reward_referral(uuid)  from public, anon, authenticated;
