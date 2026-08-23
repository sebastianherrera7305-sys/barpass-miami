-- Some universities' real, official city (e.g. Coral Gables) doesn't match
-- the metro-area label BarPass groups its venues under (e.g. Miami). This
-- column is a true geographic fact — which BarPass venue-city metro area the
-- university belongs to — never a guess or a rebrand of the university's
-- actual city (still stored, unchanged, in `city`).
--
-- Idempotent, safe to re-run.

alter table public.universities
  add column if not exists metro_city text;

-- Coral Gables is part of Miami-Dade County / Greater Miami — a real,
-- verifiable geographic fact, not a research claim about the university
-- itself.
update public.universities
  set metro_city = 'Miami'
  where name = 'University of Miami' and city = 'Coral Gables';
