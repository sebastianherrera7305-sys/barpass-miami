-- Adds real x/y percentage coordinates per POI, so the app can render an
-- actually-positioned map instead of an approximated ring layout.
-- Coordinate system: percentage, origin top-left, (50,50) = arena center.
alter table public.stadium_pois add column if not exists x_pct numeric;
alter table public.stadium_pois add column if not exists y_pct numeric;
