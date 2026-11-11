-- Who Pays? — venue discovery and approval voting
--
-- Spec: VENUES.md §12–§14. Run this in the Supabase SQL editor after
-- schema.sql. Safe to re-run.
--
-- Design notes that matter:
--   * The host fetches nearby places ONCE and writes them here. Guests read
--     this table instead of calling any places provider, so a ten-person
--     table costs one API request, not ten.
--   * Voting is approval voting: a device may approve any number of venues,
--     so the ballot is a set of rows, not a single choice column.
--   * The winner is NOT stored as a computed result. Every phone works it out
--     from the same rows with the same deterministic tie-break, exactly as
--     room_standings does for the loser. One source of truth, no disagreement.

-- ---------------------------------------------------------------------------
-- Room status gains 'voting'
-- ---------------------------------------------------------------------------
-- lobby -> voting -> settling -> running -> finished
--
-- roomStatusFrom() in room_models.dart falls back to lobby for unrecognised
-- values, so an app or guest page older than this migration sees a voting
-- room as a lobby rather than crashing. Keep that property.
alter table public.rooms drop constraint if exists rooms_status_check;
alter table public.rooms add constraint rooms_status_check
  check (status in ('lobby', 'voting', 'settling', 'running', 'finished'));

-- ---------------------------------------------------------------------------
-- Candidate venues for one room
-- ---------------------------------------------------------------------------
create table if not exists public.room_venues (
  id          uuid    primary key default gen_random_uuid(),
  room_code   text    not null references public.rooms (code) on delete cascade,
  -- The provider's own id (Google place_id, OSM node id). Lets the same place
  -- be recognised across rooms later without trusting the name.
  place_id    text    not null,
  name        text    not null check (char_length(trim(name)) between 1 and 120),
  address     text,
  lat         double precision,
  lng         double precision,
  -- Metres from the host's fix. Stored because it is the vote tie-breaker and
  -- must be identical on every phone.
  distance_m  integer,
  rating      numeric(2, 1) check (rating is null or rating between 0 and 5),
  created_at  timestamptz not null default now(),
  -- The same place must not appear twice on one ballot.
  unique (room_code, place_id)
);

create index if not exists room_venues_room_idx
  on public.room_venues (room_code);

-- ---------------------------------------------------------------------------
-- The host's decision
-- ---------------------------------------------------------------------------
-- NOT the tally winner. The winner is computed identically on every phone and
-- is never stored — see the header. This column holds a decision somebody
-- committed to, which the host may make against the vote when the app is
-- wrong about what is open. A decision and a tally result are different
-- things, and only one of them belongs in a column.
--
-- Added after room_venues so the reference resolves.
alter table public.rooms
  add column if not exists decided_venue_id uuid
  references public.room_venues (id) on delete set null;

-- ---------------------------------------------------------------------------
-- Ballots
-- ---------------------------------------------------------------------------
-- One row = "this device is willing to go here". No row = not willing.
-- Un-tapping deletes the row rather than storing a negative, so a tally is
-- just a count.
create table if not exists public.venue_votes (
  id          uuid    primary key default gen_random_uuid(),
  room_code   text    not null references public.rooms (code) on delete cascade,
  venue_id    uuid    not null references public.room_venues (id) on delete cascade,
  device_id   uuid    not null,
  created_at  timestamptz not null default now(),
  -- One approval per device per venue. Makes a double-tap idempotent and
  -- stops one phone stuffing the ballot for its favourite restaurant.
  unique (venue_id, device_id)
);

create index if not exists venue_votes_room_idx
  on public.venue_votes (room_code);

-- ---------------------------------------------------------------------------
-- Live tally
-- ---------------------------------------------------------------------------
-- Counts DISTINCT devices, so the number means "people willing to go here"
-- even if the unique constraint above is ever relaxed.
create or replace view public.venue_tally as
select
  v.room_code,
  v.id            as venue_id,
  v.name,
  v.address,
  v.distance_m,
  v.rating,
  count(distinct t.device_id) as approvals
from public.room_venues v
left join public.venue_votes t on t.venue_id = v.id
group by v.room_code, v.id, v.name, v.address, v.distance_m, v.rating;

-- ---------------------------------------------------------------------------
-- Access
-- ---------------------------------------------------------------------------
-- Same trade as the rest of the schema: a four-letter code shared at one table
-- is the only credential. Deliberately open. Never store anything sensitive.
alter table public.room_venues enable row level security;
alter table public.venue_votes enable row level security;

drop policy if exists room_venues_anon_all on public.room_venues;
create policy room_venues_anon_all on public.room_venues
  for all to anon using (true) with check (true);

drop policy if exists venue_votes_anon_all on public.venue_votes;
create policy venue_votes_anon_all on public.venue_votes
  for all to anon using (true) with check (true);

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------
-- Guarded: adding a table twice is an error, and this migration is meant to be
-- safe to re-run.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'room_venues'
  ) then
    alter publication supabase_realtime add table public.room_venues;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'venue_votes'
  ) then
    alter publication supabase_realtime add table public.venue_votes;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Housekeeping
-- ---------------------------------------------------------------------------
-- Both tables cascade from rooms, so purge_old_rooms() in schema.sql already
-- cleans them up. Nothing to add here.
