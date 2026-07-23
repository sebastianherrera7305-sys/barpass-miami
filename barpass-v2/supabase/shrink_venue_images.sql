-- Las 176 venues seed tienen image_url de Google Places pidiendo 4800px
-- (=s4800-w1200) — varios MB por imagen, para mostrarla en una card de
-- unos cientos de px. CachedImage ya downsamplea del lado del cliente,
-- pero eso no evita bajar el archivo gigante primero por la red.
--
-- Reduce el tamaño pedido directo en la URL — Google sirve la misma foto,
-- más chica, sin volver a pasar por el enrichment script.
--
-- Correr en el editor SQL de Supabase.

update public.venues
set image_url = regexp_replace(image_url, '=s\d+-w\d+$', '=s1200-w600')
where image_url like '%googleusercontent.com%=s%-w%';
