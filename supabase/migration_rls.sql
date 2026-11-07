-- Who Pays? — migration: lock down who may change what
--
-- Run in the SQL editor of project uhslpvssmpmhtmlmncxo, AFTER
-- migration_fix.sql. Safe to run more than once.
--
-- The problem this fixes
-- ---------------------
-- Both tables were `for all to anon using (true)`, which means anyone holding
-- the publishable key — and that key ships inside the app and is served to
-- every visitor of the guest page — could change or delete ANY row. Table
-- codes are four characters from a 24-letter alphabet, about 331,000
-- combinations, so they can simply be enumerated. Someone could delete every
-- live table, or set another player's caught_at and frame them for the bill.
--
-- How this fixes it
-- -----------------
-- Every client now declares which device it is, in an `x-device-id` header,
-- and the policies below only let it touch rows carrying that device id.
--
-- Be clear about the limit: this is NOT authentication. A caller can put any
-- device id in that header. What it buys is that the id must be *known*, and
-- device ids are random v4 UUIDs rather than four guessable letters. The
-- enumeration attack dies; impersonating one specific person you already know
-- the device id of does not. Proper auth means anonymous sign-in and
-- auth.uid(), which is a bigger change than belongs in a launch week.

-- ---------------------------------------------------------------------------
-- 1. Who is calling?
-- ---------------------------------------------------------------------------
create or replace function public.caller_device()
returns uuid
language plpgsql
stable
as $$
declare raw text;
begin
  raw := current_setting('request.headers', true)::json ->> 'x-device-id';
  -- Anything malformed is treated as "no device", never as an error: a bad
  -- header must fail the policy, not blow up the request with a 500.
  if raw is null or raw !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  then
    return null;
  end if;
  return raw::uuid;
exception when others then
  return null;
end $$;

grant execute on function public.caller_device() to anon;

-- ---------------------------------------------------------------------------
-- 2. Rooms — anyone may read or create; only the host may change or remove.
-- ---------------------------------------------------------------------------
drop policy if exists rooms_anon_all     on public.rooms;
drop policy if exists rooms_read         on public.rooms;
drop policy if exists rooms_create       on public.rooms;
drop policy if exists rooms_host_update  on public.rooms;
drop policy if exists rooms_host_delete  on public.rooms;

-- Reading stays open: you need the code to find a room, and the row holds
-- nothing but the rules of the game.
create policy rooms_read on public.rooms
  for select to anon using (true);

-- You may only create a room with yourself as host.
create policy rooms_create on public.rooms
  for insert to anon with check (host_id = public.caller_device());

create policy rooms_host_update on public.rooms
  for update to anon
  using (host_id = public.caller_device())
  with check (host_id = public.caller_device());

create policy rooms_host_delete on public.rooms
  for delete to anon using (host_id = public.caller_device());

-- ---------------------------------------------------------------------------
-- 3. Players — read the whole table you are at, write only your own row.
-- ---------------------------------------------------------------------------
drop policy if exists room_players_anon_all on public.room_players;
drop policy if exists room_players_read     on public.room_players;
drop policy if exists room_players_join     on public.room_players;
drop policy if exists room_players_own_update on public.room_players;
drop policy if exists room_players_own_delete on public.room_players;

-- Everyone at the table has to see everyone else, and the standings view
-- reads through this policy too.
create policy room_players_read on public.room_players
  for select to anon using (true);

create policy room_players_join on public.room_players
  for insert to anon with check (device_id = public.caller_device());

-- Covers the heartbeat, reporting your own catch, and the update half of the
-- join upsert. The `with check` matters as much as the `using`: without it
-- you could edit your own row to carry someone else's device id.
create policy room_players_own_update on public.room_players
  for update to anon
  using (device_id = public.caller_device())
  with check (device_id = public.caller_device());

create policy room_players_own_delete on public.room_players
  for delete to anon using (device_id = public.caller_device());

-- ---------------------------------------------------------------------------
-- 4. The one legitimate exception.
--
-- "Play again" clears the catch on EVERY row in the room, which per-row
-- policies correctly forbid. Rather than loosening the policy for everyone,
-- it runs here as a definer function that checks the caller really is the
-- host of that specific room.
-- ---------------------------------------------------------------------------
create or replace function public.reset_round(p_code text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.rooms
    where code = p_code and host_id = public.caller_device()
  ) then
    raise exception 'only the host of % may reset the round', p_code
      using errcode = '42501';
  end if;

  update public.room_players
     set caught_at = null, lasted_ms = null, catch_reason = null
   where room_code = p_code;
end $$;

revoke all on function public.reset_round(text) from public;
grant execute on function public.reset_round(text) to anon;

-- ---------------------------------------------------------------------------
-- 5. Proof. All four must be true.
-- ---------------------------------------------------------------------------
select
  (select count(*) from pg_policies
     where schemaname='public' and tablename='rooms') = 4        as rooms_policies_ok,
  (select count(*) from pg_policies
     where schemaname='public' and tablename='room_players') = 4 as players_policies_ok,
  (select not exists (select 1 from pg_policies
     where schemaname='public' and policyname like '%anon_all%')) as blanket_policies_gone,
  (select exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname='reset_round'))      as reset_round_exists;
