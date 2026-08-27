-- Adds a real Ticketmaster static seatmap image URL per stadium. Same
-- physical venue geometry is reused across events at that venue, so one
-- current event's seatmap image is a stable stand-in for "the stadium's
-- seatmap" rather than something tied to a single game.
alter table public.stadiums add column if not exists seatmap_url text;
