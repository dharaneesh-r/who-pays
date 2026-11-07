-- Who Pays? — migration: Focus Duel
--
-- Paste into the Supabase SQL editor. Safe to run more than once.
--
-- A duel is the asynchronous mode. Nobody has to be free at the same time:
-- everyone plays a round whenever they like, and the longest one that day
-- wins the day. This is what gives the app a reason to exist on a Tuesday,
-- when nobody has organised a dinner.
--
-- Unlike a room, a duel is long-lived. Rooms are deleted after a day; a duel
-- is a standing group of flatmates or colleagues that keeps a daily score.

create table if not exists public.duels (
  code       text primary key check (code ~ '^[A-Z]{4}$'),
  name       text not null default 'Focus Duel'
               check (char_length(trim(name)) between 1 and 30),
  created_at timestamptz not null default now(),
  last_used  timestamptz not null default now()
);

-- One row per person per day. `best_ms` is the longest round they managed
-- that day — not the sum, because the duel is about one good stretch rather
-- than grinding out many short ones.
create table if not exists public.duel_scores (
  id         bigserial   primary key,
  duel_code  text        not null references public.duels (code) on delete cascade,
  device_id  uuid        not null,
  name       text        not null check (char_length(trim(name)) between 1 and 24),
  day        date        not null,
  best_ms    integer     not null check (best_ms >= 0),
  updated_at timestamptz not null default now(),
  unique (duel_code, device_id, day)
);

create index if not exists duel_scores_day_idx
  on public.duel_scores (duel_code, day desc, best_ms desc);

alter table public.duels       enable row level security;
alter table public.duel_scores enable row level security;

-- Same trade as rooms: a four-letter code shared between flatmates is the
-- only credential, so never put anything sensitive in here.
drop policy if exists duels_anon_all on public.duels;
create policy duels_anon_all on public.duels
  for all to anon using (true) with check (true);

drop policy if exists duel_scores_anon_all on public.duel_scores;
create policy duel_scores_anon_all on public.duel_scores
  for all to anon using (true) with check (true);

-- Today's board, ranked. Ties are broken by who got there first, so a draw
-- still produces one winner rather than an argument.
create or replace view public.duel_today as
select
  s.duel_code,
  s.device_id,
  s.name,
  s.best_ms,
  s.day,
  s.updated_at,
  rank() over (
    partition by s.duel_code, s.day
    order by s.best_ms desc, s.updated_at asc
  ) as position
from public.duel_scores s;

grant select on public.duel_today to anon;

-- How many days each person has won. The number people actually argue about.
create or replace view public.duel_wins as
select
  duel_code,
  device_id,
  name,
  count(*) as days_won
from (
  select
    s.duel_code, s.device_id, s.name,
    rank() over (
      partition by s.duel_code, s.day
      order by s.best_ms desc, s.updated_at asc
    ) as position
  from public.duel_scores s
) ranked
where position = 1
group by duel_code, device_id, name;

grant select on public.duel_wins to anon;

alter publication supabase_realtime add table public.duel_scores;

-- A duel nobody has played in for two months is abandoned.
create or replace function public.purge_dead_duels()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.duels where last_used < now() - interval '60 days';
$$;
