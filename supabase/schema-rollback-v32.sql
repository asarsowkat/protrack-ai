-- ProTrack schema rollback v32: takes BOQ Engine's writes off the server (back to v3.24).
-- boq_save is removed: nobody can change BOQ Engine records on the server. The upload policy of the bucket boq-drawings
-- is removed; files stay readable. Everything is kept: the boq_* tables with their contents, the audit and the files.
-- The five boq rights stay in pt_rights() (a role's saved setting for them is harmless). Run schema-update-v32.sql again
-- to use them again. To remove the tables as well (not undoable), run separately:
-- drop table boq_audit, boq_master, boq_handoffs, boq_estimates, boq_assumptions, boq_specifications, boq_calculations, boq_dimensions, boq_drawings, boq_structures, boq_packages;
-- Safe to run twice.
-- v3.28.2: safe to run even if schema-update-v32.sql was never applied (the table boq_master is not on the database): then it changes
-- nothing and its result says so. Otherwise it runs the rollback below, unchanged. The result is one row.

do $pt_rollback$
declare applied boolean := to_regclass('public.boq_master') is not null;
begin
  if not applied then
    perform set_config('protrack.rollback', 'schema-update-v32.sql is not on this database (never run, or already undone): nothing to undo, nothing was changed.', false);
    return;
  end if;
  execute $pt_rollback_body$
drop function if exists boq_save(jsonb);
drop policy if exists protrack_boq_add on storage.objects;
$pt_rollback_body$;
  perform set_config('protrack.rollback', 'schema-update-v32.sql undone.', false);
end $pt_rollback$;
select current_setting('protrack.rollback', true) as result;
