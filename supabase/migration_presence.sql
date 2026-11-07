-- Who Pays? — migration: player presence
--
-- Paste into the Supabase SQL editor and Run. Safe to run more than once.
--
-- Why: a player who closed the app mid-round left a row that was neither
-- caught nor present. The round then had two "players still in" forever, so it
-- never resolved and the table was stuck. Phones now touch `last_seen` while
-- they are in a room, and anyone who stops reporting is treated as gone.
--
-- Every optional step below is wrapped so it cannot fail. The SQL editor runs
-- a script as a single transaction, so one refused statement at the end would
-- otherwise roll back the column this whole feature depends on — which is
-- exactly what happened on the first two attempts.

-- ---------------------------------------------------------------------------
-- 1. The one thing that matters.
-- ---------------------------------------------------------------------------
alter table public.room_players
  add column if not exists last_seen timestamptz not null default now();

-- ---------------------------------------------------------------------------
-- 2. Everything else, individually guarded.
-- ---------------------------------------------------------------------------
do $$
begin
  execute 'create index if not exists room_players_last_seen_idx
             on public.room_players (room_code, last_seen)';
exception when others then
  raise notice 'index skipped: %', sqlerrm;
end $$;

do $$
begin
  -- Dropped rather than replaced: `create or replace view` can only append
  -- columns at the end, and this inserts last_seen before crack_rank.
  execute 'drop view if exists public.room_standings cascade';
  execute '
    create view public.room_standings as
    select
      p.room_code,
      p.id,
      p.name,
      p.lasted_ms,
      p.caught_at,
      p.catch_reason,
      p.last_seen,
      (p.caught_at is not null
        or p.last_seen > now() - interval ''45 seconds'') as still_at_table,
      rank() over (
        partition by p.room_code
        order by p.caught_at asc nulls last
      ) as crack_rank
    from public.room_players p';
  execute 'grant select on public.room_standings to anon';
exception when others then
  raise notice 'standings view skipped: %', sqlerrm;
end $$;

do $$
begin
  -- Sweeps rows left by phones that went away without leaving the table.
  -- Two minutes is deliberately longer than the 45 seconds used for the live
  -- standings: a brief disconnect should grey someone out, not delete them.
  execute '
    create or replace function public.purge_absent_players()
    returns void
    language sql
    security definer
    set search_path = public
    as $f$
      delete from public.room_players
      where caught_at is null
        and last_seen < now() - interval ''2 minutes'';
    $f$';
exception when others then
  raise notice 'purge function skipped: %', sqlerrm;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Proof it worked. This must return one row saying true.
-- ---------------------------------------------------------------------------
select exists (
  select 1 from information_schema.columns
  where table_schema = 'public'
    and table_name = 'room_players'
    and column_name = 'last_seen'
) as last_seen_column_exists;
