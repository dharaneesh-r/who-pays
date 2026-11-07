-- Who Pays? — repair migration
--
-- Run this in the Supabase SQL editor of the project the app actually points
-- at. Check the project ref in your browser's address bar first; it must be:
--
--     uhslpvssmpmhtmlmncxo
--
-- That check is the whole point of this file. The presence migration was run
-- and reported success, but the app's database still has no `last_seen`
-- column — which means it was almost certainly run against a different
-- project. Running good SQL on the wrong database looks exactly like success.
--
-- Safe to run as many times as you like.

-- ---------------------------------------------------------------------------
-- 1. The column the app cannot join a table without.
--
-- Until this exists, PostgREST rejects the whole join request and nobody can
-- enter a room at all. Everything else in this file is housekeeping; this is
-- the outage.
-- ---------------------------------------------------------------------------
alter table public.room_players
  add column if not exists last_seen timestamptz not null default now();

-- ---------------------------------------------------------------------------
-- 2. Housekeeping, each guarded on its own.
--
-- The SQL editor runs a script as one transaction, so a single refused
-- statement at the bottom would roll back the column above. Each block below
-- therefore swallows its own failure and reports it as a notice.
-- ---------------------------------------------------------------------------
do $$ begin
  execute 'create index if not exists room_players_last_seen_idx
             on public.room_players (room_code, last_seen)';
exception when others then raise notice 'index skipped: %', sqlerrm;
end $$;

do $$ begin
  -- Dropped rather than replaced: `create or replace view` can only append
  -- columns at the end, and this inserts last_seen before crack_rank.
  execute 'drop view if exists public.room_standings cascade';
  execute '
    create view public.room_standings as
    select
      p.room_code, p.id, p.name, p.lasted_ms, p.caught_at, p.catch_reason,
      p.last_seen,
      (p.caught_at is not null
        or p.last_seen > now() - interval ''45 seconds'') as still_at_table,
      rank() over (
        partition by p.room_code order by p.caught_at asc nulls last
      ) as crack_rank
    from public.room_players p';
  execute 'grant select on public.room_standings to anon';
exception when others then raise notice 'standings view skipped: %', sqlerrm;
end $$;

do $$ begin
  -- Sweeps rows left by phones that vanished without leaving the table.
  -- Two minutes, deliberately longer than the 45 seconds used for the live
  -- standings: a brief disconnect should grey someone out, not delete them.
  execute '
    create or replace function public.purge_absent_players()
    returns void language sql security definer set search_path = public as $f$
      delete from public.room_players
      where caught_at is null and last_seen < now() - interval ''2 minutes'';
    $f$';
exception when others then raise notice 'purge function skipped: %', sqlerrm;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Actually run the purges on a schedule.
--
-- The four purge functions have existed all along but nothing ever called
-- them, so no data was being deleted. The privacy policy says data is removed
-- after a set time; until this block runs, that sentence is not true.
--
-- pg_cron is available on Supabase but not enabled by default, and on some
-- plans cannot be enabled at all — hence the guard. If this is skipped, see
-- the note at the bottom.
-- ---------------------------------------------------------------------------
do $$
declare
  jobs text[][] := array[
    ['who-pays-purge-absent-players', '*/2 * * * *',  'select public.purge_absent_players()'],
    ['who-pays-purge-old-rooms',      '17 * * * *',   'select public.purge_old_rooms()'],
    ['who-pays-purge-dead-duels',     '23 3 * * *',   'select public.purge_dead_duels()'],
    ['who-pays-purge-old-events',     '41 3 * * *',   'select public.purge_old_events()']
  ];
  j text[];
begin
  create extension if not exists pg_cron;

  foreach j slice 1 in array jobs loop
    -- Unschedule first so re-running this file updates rather than duplicates.
    begin
      perform cron.unschedule(j[1]);
    exception when others then null;
    end;
    perform cron.schedule(j[1], j[2], j[3]);
  end loop;

  raise notice 'scheduled % purge jobs', array_length(jobs, 1);
exception when others then
  raise notice 'cron scheduling skipped: % — schedule these from the Supabase dashboard instead (Database -> Cron Jobs)', sqlerrm;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Proof. All four must be true.
-- ---------------------------------------------------------------------------
select
  (select exists (select 1 from information_schema.columns
     where table_schema='public' and table_name='room_players'
       and column_name='last_seen'))                    as last_seen_exists,
  (select exists (select 1 from information_schema.columns
     where table_schema='public' and table_name='room_standings'
       and column_name='still_at_table'))               as standings_updated,
  (select exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname='purge_absent_players')) as purge_fn_exists,
  -- Deliberately NOT a query against cron.job. If pg_cron is unavailable that
  -- table does not exist, and Postgres fails such a statement at planning
  -- time even inside a CASE — which would roll back this entire script and
  -- undo the column in step 1. The cron result is reported as a notice by the
  -- block above instead; read it in the Messages tab.
  (select count(*) from pg_extension where extname='pg_cron') = 1
                                                      as pg_cron_installed;

-- If pg_cron_installed comes back false, pg_cron is not available on
-- this project. Everything else still works; schedule the four functions from
-- the dashboard under Database -> Cron Jobs, or call them from any external
-- scheduler. Nothing in the app depends on them running on time.
