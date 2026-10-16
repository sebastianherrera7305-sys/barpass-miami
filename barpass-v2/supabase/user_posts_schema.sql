-- =====================================================================
-- BarPass user posts — Instagram-style social posts
-- Build 1.1 (owner review wave 2 — 2026-10-16)
--
-- Cambios desde la v1:
--   · post_reports_not_self removido (CHECK no permite subqueries en
--     Postgres); la verificación "no reportar tu propio post" vive
--     ahora en la policy de INSERT con EXISTS.
--   · profiles.is_private se lee a través de posts_author_is_public,
--     un SECURITY DEFINER wrapper, para no abrir la RLS de profiles
--     (que mantiene home_address privado). Idem bp_blocked_between
--     → posts_viewer_blocked_by, porque bp_blocked_between no tiene
--     EXECUTE a authenticated (verificado contra prod).
--   · Trigger que borraba de storage.objects REMOVIDO. El cliente
--     borra el archivo con la Storage API ANTES de borrar la fila.
--     El trigger queda documentado en los comentarios por si algún
--     día Supabase expone un hook soportado para esto.
--
-- VISIBILIDAD:
--   · profiles.is_private boolean default false.
--   · Un post es visible si:
--       - sos el autor, o
--       - el autor NO es privado, o
--       - sos amigo mutuamente aceptado del autor.
--   · Y nunca si hay bloqueo mutuo entre vos y el autor.
--
-- STORAGE:
--   Bucket `user-posts` (public), path `{user_id}/{post_id}.{ext}`.
--   CHECK en la tabla: image_path tiene que empezar con `{user_id}/`.
--
-- MODERACIÓN:
--   · post_reports (reporter, post, reason).
--   · user_blocks ya existe en friend_graph_schema.sql y bloquea
--     visibilidad en los dos sentidos.
-- =====================================================================

create extension if not exists pgcrypto;

-- ================
-- 1. profiles.is_private — toggle "Cuenta privada" vive acá
-- ================
alter table public.profiles
  add column if not exists is_private boolean not null default false;

-- La RLS de profiles sigue siendo "SELECT own row only" (verificado
-- 2026-10-16): un usuario no ve home_address, is_private, etc. de
-- otro. Esa invariante no se toca.

-- ================
-- 2. posts
-- ================
create table if not exists public.posts (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  image_path text not null,
  caption    text not null default '' check (char_length(caption) <= 500),
  venue_id   uuid references public.venues(id) on delete set null,
  created_at timestamptz not null default now(),

  -- Un cliente comprometido no puede registrar un path que apunte al
  -- objeto de otro usuario. El bucket aplica lo mismo en el INSERT
  -- de storage.objects; este CHECK duplica la invariante en la row
  -- para que no exista una row válida con un path ajeno aunque el
  -- bucket y la tabla se escriban en órdenes distintos.
  --
  -- Y bloquea path traversal (`..`): sin este segundo check, un path
  -- como `{user_id}/../otro_user/foto.jpg` pasa el prefix check pero
  -- al normalizar apunta a `otro_user/foto.jpg`. El bucket de
  -- Supabase valida el path para INSERT, pero esto cierra la row
  -- misma por si el cliente lo registra sin haber subido o si una
  -- futura migración de storage no replica la validación.
  constraint posts_path_belongs_to_user
    check (
      position(user_id::text || '/' in image_path) = 1
      and image_path !~ '\.\.'
    )
);

create index if not exists posts_user_created_idx
  on public.posts (user_id, created_at desc);

create index if not exists posts_venue_created_idx
  on public.posts (venue_id, created_at desc)
  where venue_id is not null;

-- ================
-- 3. Helpers SECURITY DEFINER — todos revocados de public/anon
-- ================

-- 3.a ¿Es `p_other` amigo mutuo del caller? Un solo parámetro,
-- compara contra auth.uid() internamente.
create or replace function public.posts_viewer_is_friend(p_other uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when auth.uid() is null then false
    when auth.uid() = p_other then false   -- self no cuenta como amigo
    else exists (
      select 1
      from public.friendships f
      where f.status = 'accepted'
        and f.user_a = least(auth.uid(), p_other)
        and f.user_b = greatest(auth.uid(), p_other)
    )
  end;
$$;
revoke all on function public.posts_viewer_is_friend(uuid) from public, anon;
grant execute on function public.posts_viewer_is_friend(uuid) to authenticated;

-- 3.b ¿El autor del post NO es privado? Único acceso del cliente a
-- profiles.is_private. Devuelve false si el usuario no existe,
-- para no filtrar la existencia de la fila por un canal lateral.
create or replace function public.posts_author_is_public(p_user uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select not p.is_private from public.profiles p where p.id = p_user),
    false
  );
$$;
revoke all on function public.posts_author_is_public(uuid) from public, anon;
grant execute on function public.posts_author_is_public(uuid) to authenticated;

-- 3.c ¿Hay bloqueo entre el caller y p_other? Wrap de la lógica de
-- bp_blocked_between porque esa función NO tiene EXECUTE a
-- authenticated (verificado contra prod 2026-10-16, devuelve 42501).
-- Reimplementa el predicado inline en vez de delegar — así quedamos
-- independientes de los grants de friend_graph_schema.
create or replace function public.posts_viewer_blocked_by(p_other uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when auth.uid() is null then false
    when auth.uid() = p_other then false
    else exists (
      select 1 from public.user_blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = p_other)
         or (b.blocker_id = p_other   and b.blocked_id = auth.uid())
    )
  end;
$$;
revoke all on function public.posts_viewer_blocked_by(uuid) from public, anon;
grant execute on function public.posts_viewer_blocked_by(uuid) to authenticated;

-- ================
-- 4. RLS en posts
-- ================
alter table public.posts enable row level security;
revoke all on public.posts from anon, authenticated;
grant select, insert, delete on public.posts to authenticated;

drop policy if exists posts_select_visible on public.posts;
create policy posts_select_visible on public.posts
  for select to authenticated
  using (
    not public.posts_viewer_blocked_by(user_id)
    and (
      auth.uid() = user_id
      or public.posts_viewer_is_friend(user_id)
      or public.posts_author_is_public(user_id)
    )
  );

drop policy if exists posts_insert_own on public.posts;
create policy posts_insert_own on public.posts
  for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists posts_delete_own on public.posts;
create policy posts_delete_own on public.posts
  for delete to authenticated
  using (auth.uid() = user_id);

-- NO UPDATE. Para corregir caption → delete + nuevo post.

-- ================
-- 5. Cleanup del archivo cuando se borra el post
-- ================
-- Supabase NO expone un hook server-side soportado para eliminar un
-- objeto de Storage desde un trigger de Postgres (storage.objects
-- vive en un esquema managed; un DELETE directo deja huérfanos los
-- metadatos de la fila `objects` pero no borra el blob físico, que
-- se queda en el bucket consumiendo cuota hasta la próxima limpieza
-- manual).
--
-- Decisión (owner review wave 2, 2026-10-16): el cliente borra PRIMERO
-- la fila y DESPUÉS el archivo (`DELETE /rest/v1/posts?id=eq.{id}` →
-- `DELETE /storage/v1/object/user-posts/{path}`). Si el DELETE del
-- archivo falla, el blob queda huérfano en el bucket pero NADIE lo
-- ve: la row ya no existe, no hay forma de descubrir la URL desde el
-- DB, y la URL raw es un UUID random no adivinable. Un cronjob manual
-- futuro limpia huérfanos (`storage.objects` sin fila en posts). El
-- orden inverso dejaba el peor estado posible: fila viva + archivo
-- gone → placeholder "foto no disponible" en todos los grids hasta
-- que el cliente reintente, lo cual puede no pasar nunca.
--
-- Si Supabase alguna vez expone un trigger soportado para esto, se
-- agrega acá en una sección aparte.

-- ================
-- 6. Helper RPC: posts_count_for(user_id)
-- Rinde "N posts" en el perfil, respetando RLS (SELECT via policy).
-- ================
create or replace function public.posts_count_for(p_user uuid)
returns int
language sql stable set search_path = public as $$
  select count(*)::int from public.posts p where p.user_id = p_user;
$$;
revoke all on function public.posts_count_for(uuid) from public, anon;
grant execute on function public.posts_count_for(uuid) to authenticated;

-- ================
-- 7. Storage bucket + object-level policies
-- ================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'user-posts',
  'user-posts',
  true,
  10 * 1024 * 1024,                              -- 10 MB
  array['image/jpeg', 'image/png', 'image/heic', 'image/webp']
)
on conflict (id) do update
   set public = excluded.public,
       file_size_limit = excluded.file_size_limit,
       allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "user_posts_insert_own" on storage.objects;
create policy "user_posts_insert_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'user-posts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "user_posts_delete_own" on storage.objects;
create policy "user_posts_delete_own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'user-posts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- SELECT (download) sigue abierto por `public = true`. La row del DB
-- gatea discoverability; el nombre del archivo es un UUID. Si eso
-- cambia, flipeamos bucket a privado + signed URLs en el Repository.

-- ================
-- 8. Moderación — post_reports
-- ================
create table if not exists public.post_reports (
  id          uuid primary key default gen_random_uuid(),
  post_id     uuid not null references public.posts(id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reason      text not null check (char_length(reason) between 1 and 400),
  created_at  timestamptz not null default now(),
  -- Una denuncia por post por usuario; segunda intenta falla 23505,
  -- cliente la trata como "ya denunciado".
  unique (post_id, reporter_id)
  -- NO CHECK con subquery acá (Postgres no las permite en CHECK).
  -- La invariante "no reportar tu propio post" vive en la policy
  -- de INSERT abajo con EXISTS.
);

create index if not exists post_reports_post_idx
  on public.post_reports (post_id, created_at desc);

alter table public.post_reports enable row level security;
revoke all on public.post_reports from anon, authenticated;
grant select, insert on public.post_reports to authenticated;

-- SELECT: solo tus propias denuncias (para rendir "ya reportado").
drop policy if exists post_reports_select_own on public.post_reports;
create policy post_reports_select_own on public.post_reports
  for select to authenticated
  using (auth.uid() = reporter_id);

-- INSERT: solo como vos mismo, y nunca denunciando tu propio post.
drop policy if exists post_reports_insert_own on public.post_reports;
create policy post_reports_insert_own on public.post_reports
  for insert to authenticated
  with check (
    auth.uid() = reporter_id
    and exists (
      select 1 from public.posts p
      where p.id = post_reports.post_id
        and p.user_id <> auth.uid()
    )
  );

-- NO DELETE/UPDATE para el usuario. La denuncia es un acto histórico
-- que modera revisa; si fue por error el equipo de soporte lo limpia
-- desde admin con service role.

-- Bloqueo: tabla user_blocks existe (friend_graph_schema.sql). La
-- policy SELECT de posts arriba invoca posts_viewer_blocked_by para
-- ocultar en ambos sentidos. No necesitamos tabla nueva.

-- =====================================================================
-- CÓMO APLICAR
--   Pegar entero en Supabase SQL editor. Idempotente: todo tiene
--   IF NOT EXISTS / DROP IF EXISTS / UPSERT. Correlo dos veces y la
--   segunda es un no-op.
-- =====================================================================
