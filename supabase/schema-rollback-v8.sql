-- ProTrack: undo schema update v8. Puts back the v2/v5 read rules for invoices, upload history and import
-- batches (everyone with access to a project reads them again). No data is touched. Safe to run twice.
-- v3.28.2: safe to run even if schema-update-v8.sql was never applied (the function pt_money_ok is not on the database): then it changes
-- nothing and its result says so. Otherwise it runs the rollback below, unchanged. The result is one row.

do $pt_rollback$
declare applied boolean := exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'pt_money_ok');
begin
  if not applied then
    perform set_config('protrack.rollback', 'schema-update-v8.sql is not on this database (never run, or already undone): nothing to undo, nothing was changed.', false);
    return;
  end if;
  execute $pt_rollback_body$
drop policy if exists inv_read on invoices;
create policy inv_read on invoices for select using (can_see(project_id));
drop policy if exists uh_read on upload_history;
create policy uh_read on upload_history for select using (can_see(project_id));
drop policy if exists ib_read on import_batches;
create policy ib_read on import_batches for select using (
  (project_id is not null and can_see(project_id)) or (project_id is null and my_role_text() in ('sa','exec','plan')));
drop function if exists pt_money_ok();
$pt_rollback_body$;
  perform set_config('protrack.rollback', 'schema-update-v8.sql undone.', false);
end $pt_rollback$;
select current_setting('protrack.rollback', true) as result;
