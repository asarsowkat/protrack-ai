-- ProTrack schema rollback v31: the screen 'boq' (BOQ Engine) leaves Screens by role on the server (back to v3.23).
-- A role's saved choice for BOQ Engine is no longer accepted; the app then uses its default (management, planning,
-- costing and project managers). Safe to run twice.
-- v3.28.2: safe to run even if schema-update-v31.sql was never applied (the screen 'boq' in pt_screens() is not on the database): then it changes
-- nothing and its result says so. Otherwise it runs the rollback below, unchanged. The result is one row.

do $pt_rollback$
declare applied boolean := false;
begin
  if to_regprocedure('public.pt_screens()') is not null then execute $q$select 'boq' = any(pt_screens())$q$ into applied; end if;
  if not applied then
    perform set_config('protrack.rollback', 'schema-update-v31.sql is not on this database (never run, or already undone): nothing to undo, nothing was changed.', false);
    return;
  end if;
  execute $pt_rollback_body$
do $$
declare scr text[] := pt_screens();
begin
  if 'boq' = any(scr) then
    execute format('create or replace function pt_screens() returns text[] language sql immutable as $f$ select %L::text[] $f$', array_remove(scr, 'boq')::text); end if;
end $$;
$pt_rollback_body$;
  perform set_config('protrack.rollback', 'schema-update-v31.sql undone.', false);
end $pt_rollback$;
select current_setting('protrack.rollback', true) as result;
