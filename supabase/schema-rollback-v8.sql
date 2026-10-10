-- ProTrack: undo schema update v8. Puts back the v2/v5 read rules for invoices, upload history and import
-- batches (everyone with access to a project reads them again). No data is touched. Safe to run twice.
drop policy if exists inv_read on invoices;
create policy inv_read on invoices for select using (can_see(project_id));
drop policy if exists uh_read on upload_history;
create policy uh_read on upload_history for select using (can_see(project_id));
drop policy if exists ib_read on import_batches;
create policy ib_read on import_batches for select using (
  (project_id is not null and can_see(project_id)) or (project_id is null and my_role_text() in ('sa','exec','plan')));
drop function if exists pt_money_ok();
