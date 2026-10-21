-- ProTrack: undo schema update v13 (ProTrackAI v3.4). Stops new documents and box changes: removes doc_act and the
-- rule that lets people add files to the "project-docs" bucket. Keeps every box, document, file and history entry,
-- still readable by the same people. Safe to run twice.
-- v3.28.2: safe to run even if schema-update-v13.sql was never applied (the table doc_boxes is not on the database): then it changes
-- nothing and its result says so. Otherwise it runs the rollback below, unchanged. The result is one row.

do $pt_rollback$
declare applied boolean := to_regclass('public.doc_boxes') is not null;
begin
  if not applied then
    perform set_config('protrack.rollback', 'schema-update-v13.sql is not on this database (never run, or already undone): nothing to undo, nothing was changed.', false);
    return;
  end if;
  execute $pt_rollback_body$
drop policy if exists protrack_docs_add on storage.objects;
drop function if exists doc_act(jsonb);
$pt_rollback_body$;
  perform set_config('protrack.rollback', 'schema-update-v13.sql undone.', false);
end $pt_rollback$;
select current_setting('protrack.rollback', true) as result;
