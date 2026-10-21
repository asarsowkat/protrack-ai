-- ProTrack schema rollback v26: takes away recording letters on delay events (back to v3.19 / v3.19.1 on the server).
-- delay_corr_act, delay_corr_features() and the rule to add files to the "delay-docs" bucket are removed, so nobody
-- can add or remove a record, and an event with letters can be deleted again.
-- Everything is kept: delay_corr with every record (removed ones too), the files in "delay-docs" and their read rule,
-- so live.html still lists the letters and opens them. Run schema-update-v26.sql again to record letters again.
-- To remove them as well (not undoable), empty the bucket in Supabase -> Storage, then run separately:
-- drop table delay_corr;
-- Safe to run twice.
-- v3.28.2: safe to run even if schema-update-v26.sql was never applied (the table delay_corr is not on the database): then it changes
-- nothing and its result says so. Otherwise it runs the rollback below, unchanged. The result is one row.

do $pt_rollback$
declare applied boolean := to_regclass('public.delay_corr') is not null;
begin
  if not applied then
    perform set_config('protrack.rollback', 'schema-update-v26.sql is not on this database (never run, or already undone): nothing to undo, nothing was changed.', false);
    return;
  end if;
  execute $pt_rollback_body$
drop function if exists delay_corr_features();
drop function if exists delay_corr_act(jsonb);
drop function if exists pt_dly_corr_link(delay_events, delay_corr);
drop policy if exists protrack_delay_docs_add on storage.objects;
drop trigger if exists trg_dly_corr_guard on delay_events;
drop function if exists pt_dly_corr_guard();
$pt_rollback_body$;
  perform set_config('protrack.rollback', 'schema-update-v26.sql undone.', false);
end $pt_rollback$;
select current_setting('protrack.rollback', true) as result;
