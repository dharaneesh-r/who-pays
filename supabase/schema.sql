-- Who Pays? — Phase 5 room schema
--
-- Paste this into the Supabase SQL editor of a new project.
-- The server does very little on purpose: it holds a room, who is in it, and
-- who got caught. The game itself runs entirely on each phone.

-- ---------------------------------------------------------------------------
-- Rooms
-- ---------------------------------------------------------------------------
create table if not exists public.rooms (
  code         text primary key check (code ~ '^[A-Z]{4}$'),
  host_id      uuid        not null,
  stake        text        not null default 'bill',
  custom_stake text,
  target_ms    integer,                     -- null = until someone cracks
  status       text        not null default 'lobby'
                 check (status in ('lobby', 'settling', 'running', 'finished')),
  started_at   timestamptz,
  created_at   timestamptz not null default now()
);

-- Rooms are disposable. Anything older than a day is dead weight.
create index if not exists rooms_created_at_idx on public.rooms (created_at);

-- ---------------------------------------------------------------------------
-- Players
-- ---------------------------------------------------------------------------
create table if not exists public.room_players (
  id            uuid        primary key default gen_random_uuid(),
  room_code     text        not null references public.rooms (code) on delete cascade,
  device_id     uuid        not null,
  name          text        not null check (char_length(trim(name)) between 1 and 24),
  joined_at     timestamptz not null default now(),
  -- Set when this player is caught. Null means still in the game.
  caught_at     timestamptz,
  lasted_ms     integer,
  catch_reason  text,
  unique (room_code, device_id)
);

create index if not exists room_players_room_idx
  on public.room_players (room_code);

-- First to crack = earliest caught_at in the room. Computed, never stored,
-- so two phones reporting at the same moment cannot disagree.
create or replace view public.room_standings as
select
  p.room_code,
  p.id,
  p.name,
  p.lasted_ms,
  p.caught_at,
  p.catch_reason,
  rank() over (
    partition by p.room_code
    order by p.caught_at asc nulls last
  ) as crack_rank
from public.room_players p;

-- ---------------------------------------------------------------------------
-- Access
-- ---------------------------------------------------------------------------
-- There are no accounts. A four-letter code shared at one table is the only
-- credential, which is the right trade for a dinner game — but it means the
-- policies below are deliberately open, so never store anything sensitive here.
alter table public.rooms         enable row level security;
alter table public.room_players  enable row level security;

drop policy if exists rooms_anon_all on public.rooms;
create policy rooms_anon_all on public.rooms
  for all to anon using (true) with check (true);

drop policy if exists room_players_anon_all on public.room_players;
create policy room_players_anon_all on public.room_players
  for all to anon using (true) with check (true);

-- Realtime: every phone at the table subscribes to its own room.
alter publication supabase_realtime add table public.rooms;
alter publication supabase_realtime add table public.room_players;

-- ---------------------------------------------------------------------------
-- Housekeeping
-- ---------------------------------------------------------------------------
-- Run on a schedule (Supabase cron) so the table never grows without bound.
create or replace function public.purge_old_rooms()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.rooms where created_at < now() - interval '1 day';
$$;
