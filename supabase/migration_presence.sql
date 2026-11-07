-- Who Pays? — migration: player presence
--
-- Paste into the Supabase SQL editor. Safe to run more than once.
--
-- Why: a player who closed the app mid-round left a row that was neither
-- caught nor present. The round then had two "players still in" forever, so it
-- never resolved and the table was stuck. Phones now touch `last_seen` while
-- they are in a room, and anyone who stops reporting is treated as gone.

alter table public.room_players
  add column if not exists last_seen timestamptz not null default now();

create index if not exists room_players_last_seen_idx
  on public.room_players (room_code, last_seen);

-- Dropped and rebuilt, not replaced. `create or replace view` can only append
-- columns at the end — inserting `last_seen` before `crack_rank` makes it
-- fail, and because the SQL editor runs the script in one transaction that
-- failure rolled back the `alter table` above it too.
drop view if exists public.room_standings;

create view public.room_standings as
select
  p.room_code,
  p.id,
  p.name,
  p.lasted_ms,
  p.caught_at,
  p.catch_reason,
  p.last_seen,
  (p.caught_at is not null or p.last_seen > now() - interval '45 seconds')
    as still_at_table,
  rank() over (
    partition by p.room_code
    order by p.caught_at asc nulls last
  ) as crack_rank
from public.room_players p;

grant select on public.room_standings to anon;

-- Sweeps rows left by phones that went away without leaving the table.
-- Two minutes is deliberately longer than the 45 seconds used for the live
-- standings: a brief disconnect should grey someone out, not delete them.
create or replace function public.purge_absent_players()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.room_players
  where caught_at is null
    and last_seen < now() - interval '2 minutes';
$$;
