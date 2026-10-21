-- ProTrack: undo schema update v6. Removes the lifecycle functions; keeps the lifecycle stages and their
-- history (nothing is deleted). Supabase -> SQL Editor -> New query -> paste -> Run. Safe to run twice.
-- v3.28.2: safe to run even if schema-update-v6.sql was never applied (the table lifecycle_stages is not on the database): then it changes
-- nothing and its result says so. Otherwise it runs the rollback below, unchanged. The result is one row.

do $pt_rollback$
declare applied boolean := to_regclass('public.lifecycle_stages') is not null;
begin
  if not applied then
    perform set_config('protrack.rollback', 'schema-update-v6.sql is not on this database (never run, or already undone): nothing to undo, nothing was changed.', false);
    return;
  end if;
  execute $pt_rollback_body$
drop function if exists lifecycle_act(jsonb);
drop function if exists pt_lc_approver(uuid, text);
drop function if exists pt_lc_template(int);
drop function if exists pt_lc_dept(int);
$pt_rollback_body$;
  perform set_config('protrack.rollback', 'schema-update-v6.sql undone.', false);
end $pt_rollback$;
select current_setting('protrack.rollback', true) as result;
