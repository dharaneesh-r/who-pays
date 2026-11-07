-- Three lines. They settle, with no room for doubt, whether the SQL editor
-- you are typing into is connected to the database the app actually uses.
--
-- Run this on its own, then tell me. I will try to read it from outside.
--   - If I can see it, we are on the same database and the problem is in the
--     migration scripts, which is my problem to fix.
--   - If I cannot, the editor is on a different project, and no amount of
--     re-running the migrations will ever help.

create table if not exists public.probe_marker (note text primary key);

insert into public.probe_marker (note)
values ('hello-from-the-sql-editor')
on conflict (note) do nothing;

grant select on public.probe_marker to anon;

alter table public.probe_marker enable row level security;
drop policy if exists probe_read on public.probe_marker;
create policy probe_read on public.probe_marker for select to anon using (true);

select 'probe written' as result, current_database() as db, now() as at;
