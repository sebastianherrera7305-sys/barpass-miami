-- "Go home" button: lets a user save one address once, then get a Uber
-- deep link straight there while checked in at a venue. Coordinates are
-- geocoded client-side (CLGeocoder) and stored alongside the text address
-- so the app never needs to re-geocode on every tap.
alter table public.profiles add column if not exists home_address text;
alter table public.profiles add column if not exists home_lat double precision;
alter table public.profiles add column if not exists home_lng double precision;
