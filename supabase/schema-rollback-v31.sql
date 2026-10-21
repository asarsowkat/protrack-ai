-- ProTrack schema rollback v31: the screen 'boq' (BOQ Engine) leaves Screens by role on the server (back to v3.23).
-- A role's saved choice for BOQ Engine is no longer accepted; the app then uses its default (management, planning,
-- costing and project managers). Safe to run twice.

do $$
declare scr text[] := pt_screens();
begin
  if 'boq' = any(scr) then
    execute format('create or replace function pt_screens() returns text[] language sql immutable as $f$ select %L::text[] $f$', array_remove(scr, 'boq')::text); end if;
end $$;
