-- ProTrack schema rollback v23: back to the v3.16 server rules for the report email lists and the cost report columns.
-- margin_mail_features(), release_act_cv(), report_mail_set() and the cv_by trigger are removed, so live.html goes back
-- to keeping the email lists in each browser and working out the contract value of each cost report column in the
-- browser, as before v23. release_act and release_act_bl are not touched (v23 did not replace them).
-- Everything is kept: the table report_mail_lists with every list (nobody can read it until schema-update-v23.sql is run
-- again, which uses it again), and the cv_by saved with cost reports (a released version cannot be changed; the app
-- reads it). Safe to run twice.
-- v3.28.2: safe to run even if schema-update-v23.sql was never applied (the table report_mail_lists is not on the database): then it changes
-- nothing and its result says so. Otherwise it runs the rollback below, unchanged. The result is one row.

do $pt_rollback$
declare applied boolean := to_regclass('public.report_mail_lists') is not null;
begin
  if not applied then
    perform set_config('protrack.rollback', 'schema-update-v23.sql is not on this database (never run, or already undone): nothing to undo, nothing was changed.', false);
    return;
  end if;
  execute $pt_rollback_body$
drop function if exists margin_mail_features();
drop function if exists release_act_cv(jsonb);
drop trigger if exists trg_rr_cvby on report_releases;
drop function if exists pt_release_cvby();
drop function if exists pt_cost_cv_by(text, text);
drop function if exists pt_cv_cols();
drop function if exists report_mail_set(jsonb);
do $$ begin
  if to_regclass('public.report_mail_lists') is not null then
    execute 'drop policy if exists rml_read on report_mail_lists';
  end if;
end $$;
drop function if exists pt_rel_mail_region_keeper(uuid, text);
drop function if exists pt_rel_mail_reader(uuid);
drop function if exists pt_mail_roles();
$pt_rollback_body$;
  perform set_config('protrack.rollback', 'schema-update-v23.sql undone.', false);
end $pt_rollback$;
select current_setting('protrack.rollback', true) as result;
