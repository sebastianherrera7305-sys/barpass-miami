-- Reemplaza el secreto único VENUE_VALIDATION_SECRET (compartido por TODOS
-- los venues) por un secreto individual por venue. Antes, filtrar un solo
-- secreto comprometía el canje de pases y las estadísticas de TODOS los
-- venues a la vez.
--
-- Correr en el editor SQL de Supabase. Seguro sobre datos existentes:
-- agrega la columna, la rellena con un secreto random por fila, y recién
-- después la vuelve NOT NULL.

alter table public.venues add column if not exists validation_secret text;

update public.venues
set validation_secret = encode(gen_random_bytes(18), 'base64')
where validation_secret is null;

alter table public.venues alter column validation_secret set not null;

-- El secreto de cada venue nunca debe salir por una lectura pública —
-- solo se toca desde rutas server-side con el service role.
