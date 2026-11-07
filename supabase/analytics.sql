-- Who Pays? — anonymous product analytics
--
-- Paste into the Supabase SQL editor after schema.sql.
--
-- Why this exists: Play Console knows installs and AdMob knows revenue, but
-- neither can answer "did anyone finish a second round" or "which pack do
-- people pick". This table does, and it costs nothing.
--
-- There is no personal data here. `device_id` is a random UUID generated on
-- the phone, tied to nothing, and wiped when the app is uninstalled.

create table if not exists public.app_events (
  id         bigserial   primary key,
  device_id  uuid        not null,
  event      text        not null check (char_length(event) between 1 and 40),
  props      jsonb       not null default '{}'::jsonb,
  app_version text,
  platform   text,
  created_at timestamptz not null default now()
);

create index if not exists app_events_created_idx on public.app_events (created_at);
create index if not exists app_events_event_idx   on public.app_events (event, created_at);
create index if not exists app_events_device_idx  on public.app_events (device_id);

alter table public.app_events enable row level security;

-- Phones may write events and nothing else. They can never read them back,
-- so one user's app cannot enumerate everybody else's activity.
drop policy if exists app_events_insert on public.app_events;
create policy app_events_insert on public.app_events
  for insert to anon with check (true);

-- ---------------------------------------------------------------------------
-- Dashboard views
--
-- Views run with the owner's rights, so the dashboard can read these
-- aggregates with the publishable key while the raw event rows stay private.
-- Only totals are exposed — never a row that could be traced to a device.
-- ---------------------------------------------------------------------------

create or replace view public.stats_daily as
select
  (created_at at time zone 'Asia/Kolkata')::date      as day,
  count(*) filter (where event = 'app_open')          as opens,
  count(distinct device_id)                           as active_devices,
  count(distinct device_id) filter (where event = 'first_open') as new_devices,
  count(*) filter (where event = 'round_started')     as rounds_started,
  count(*) filter (where event = 'round_finished')    as rounds_finished,
  count(*) filter (where event = 'room_created')      as tables_hosted,
  count(*) filter (where event = 'room_joined')       as tables_joined,
  count(*) filter (where event = 'result_shared')     as shares,
  count(*) filter (where event = 'ad_shown')          as ads_shown
from public.app_events
group by 1
order by 1 desc;

create or replace view public.stats_totals as
select
  count(distinct device_id)                                   as total_devices,
  count(distinct device_id) filter
    (where created_at > now() - interval '1 day')             as devices_today,
  count(distinct device_id) filter
    (where created_at > now() - interval '7 days')            as devices_7d,
  count(distinct device_id) filter
    (where created_at > now() - interval '30 days')           as devices_30d,
  count(*) filter (where event = 'round_finished')            as rounds_all_time,
  count(*) filter (where event = 'ad_shown')                  as ads_all_time,
  count(*) filter (where event = 'result_shared')             as shares_all_time
from public.app_events;

-- Why people get caught. Tells you whether detection thresholds are sane:
-- a flood of 'motion' with very short rounds means false positives.
create or replace view public.stats_catch_reasons as
select
  props ->> 'reason'           as reason,
  count(*)                     as hits,
  round(avg((props ->> 'lasted_ms')::numeric) / 1000, 1) as avg_seconds
from public.app_events
where event = 'round_finished' and props ? 'reason'
group by 1
order by 2 desc;

create or replace view public.stats_packs as
select
  props ->> 'pack'  as pack,
  count(*)          as picks
from public.app_events
where event = 'pack_selected' and props ? 'pack'
group by 1
order by 2 desc;

-- Retention: of the devices first seen on a day, how many came back later.
create or replace view public.stats_retention as
with firsts as (
  select device_id, min(created_at) as first_seen
  from public.app_events
  group by device_id
)
select
  (f.first_seen at time zone 'Asia/Kolkata')::date as cohort_day,
  count(distinct f.device_id)                      as new_devices,
  count(distinct f.device_id) filter (
    where exists (
      select 1 from public.app_events e
      where e.device_id = f.device_id
        and e.created_at > f.first_seen + interval '1 day'
    )
  ) as returned_later
from firsts f
group by 1
order by 1 desc;

grant select on public.stats_daily,
                public.stats_totals,
                public.stats_catch_reasons,
                public.stats_packs,
                public.stats_retention
  to anon;

-- Housekeeping: events older than a year are not worth storing.
create or replace function public.purge_old_events()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.app_events where created_at < now() - interval '365 days';
$$;
