-- Columnas para datos reales de Google Places — antes la tabla no tenía
-- dónde guardar teléfono/sitio web en absoluto, y no había forma de
-- re-consultar un venue específico en Google sin buscarlo por nombre de
-- nuevo cada vez (google_place_id lo fija una sola vez).
--
-- Correr en el editor SQL de Supabase.

alter table public.venues add column if not exists phone text;
alter table public.venues add column if not exists website text;
alter table public.venues add column if not exists google_place_id text;
alter table public.venues add column if not exists business_status text;
alter table public.venues add column if not exists google_synced_at timestamptz;
