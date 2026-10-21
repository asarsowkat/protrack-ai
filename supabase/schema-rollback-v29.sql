-- ProTrack schema rollback v29: takes Reporting status's writes off the server (back to v3.21).
-- reporting_act and reporting_features() are removed: nobody can send reminders, exempt projects or change the rules on
-- the server. Everything is kept: rs_config, rs_exemptions and rs_reminders with their contents, still readable.
-- Run schema-update-v29.sql again to use them again. To remove them as well (not undoable), run separately:
-- drop table rs_reminders, rs_exemptions, rs_config;
-- Safe to run twice.
-- v3.28.2: safe to run even if schema-update-v29.sql was never applied (the table rs_config is not on the database): then it changes
-- nothing and its result says so. Otherwise it runs the rollback below, unchanged. The result is one row.

do $pt_rollback$
declare applied boolean := to_regclass('public.rs_config') is not null;
begin
  if not applied then
    perform set_config('protrack.rollback', 'schema-update-v29.sql is not on this database (never run, or already undone): nothing to undo, nothing was changed.', false);
    return;
  end if;
  execute $pt_rollback_body$
drop function if exists reporting_features();
drop function if exists reporting_act(jsonb);
drop function if exists pt_rs_reminder_ok(uuid, text);
$pt_rollback_body$;
  perform set_config('protrack.rollback', 'schema-update-v29.sql undone.', false);
end $pt_rollback$;
select current_setting('protrack.rollback', true) as result;
