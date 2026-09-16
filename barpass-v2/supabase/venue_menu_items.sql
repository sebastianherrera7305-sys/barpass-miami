-- La carta entera, no seis tragos.
--
-- El extractor ya lee la carta completa de cada venue (Boxcar: 45 ítems de un
-- JPG), pero hasta ahora sólo los 6 principales llegaban a la app en
-- venues.popular_drinks; el resto quedaba enterrado en la procedencia, donde
-- el producto no lo puede leer. Esta tabla es esa carta, consultable.
--
-- Sigue siendo público lo que el venue ya publica: una carta colgada en su
-- propio sitio no es un secreto. Escribir, sólo el service role (los
-- extractores); nadie más puede inventar un precio.
create table if not exists public.venue_menu_items (
  id           uuid primary key default gen_random_uuid(),
  venue_id     uuid not null references public.venues(id) on delete cascade,
  name         text not null check (char_length(btrim(name)) between 1 and 120),
  -- NULL es legal y es un hecho: un ítem listado sin precio impreso existe,
  -- y decir "no sabemos su precio" es verdad. Inventarlo, no.
  price        numeric(8,2) check (price is null or (price >= 0 and price <= 2000)),
  -- cocktail | beer | wine | shot | spirit | food | other
  category     text not null default 'other',
  is_drink     boolean not null default true,
  -- 'venue website menu' | 'venue menu image' | 'user_report' | 'manual_research'
  source       text not null,
  source_url   text,
  extracted_at timestamptz not null default now(),
  -- Una carta no repite el mismo trago dos veces; y esto hace que re-correr
  -- el extractor actualice en vez de duplicar.
  unique (venue_id, name)
);

alter table public.venue_menu_items enable row level security;

drop policy if exists "menus are public" on public.venue_menu_items;
create policy "menus are public"
  on public.venue_menu_items for select
  to anon, authenticated
  using (true);

-- Sin política de INSERT/UPDATE/DELETE: sólo el service role escribe.
revoke insert, update, delete on public.venue_menu_items from anon, authenticated;
grant select on public.venue_menu_items to anon, authenticated;

create index if not exists venue_menu_items_venue_idx
  on public.venue_menu_items (venue_id, is_drink, category);
