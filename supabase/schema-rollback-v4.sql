-- ProTrack: undo schema update v4 (only if you need to go back to the v2.4 app behaviour).
-- Removes the v4 guards and functions and restores the v3 write rules for daily reports.
-- It deletes NO data: the added columns, the import_batches table and every report, line and audit
-- entry stay where they are (the old app simply ignores them).
-- Supabase -> SQL Editor -> New query -> paste -> Run. Safe to run more than once.

drop trigger if exists trg_guard_dprs on dprs;
drop trigger if exists trg_guard_lines on dpr_lines;
drop trigger if exists trg_audit_chain on dpr_audit;
drop trigger if exists trg_audit_truncate on dpr_audit;
drop trigger if exists trg_log_append on change_log;
drop trigger if exists trg_log_truncate on change_log;

drop function if exists dpr_save(jsonb);
drop function if exists dpr_act(text, text, text, int);
drop function if exists import_invoices(text, text, text, jsonb, text);
drop function if exists apply_costing(text, text, text, jsonb);
drop function if exists import_baseline(text, text, text, jsonb);
drop function if exists export_project(text);
drop function if exists migrate_dprs(jsonb);
drop function if exists dpr_audit_verify(text);
drop function if exists team_directory();
drop function if exists admin_save_person(jsonb);
drop function if exists pt_batch_seen(text, text, text);
drop function if exists pt_timing(jsonb, text, int);
drop function if exists pt_audit(text, text, text);
drop function if exists pt_guard();
drop function if exists pt_audit_chain();
drop function if exists pt_audit_hash(text, text, text, text, uuid, text, timestamptz);
drop function if exists pt_no_truncate();
drop function if exists pt_append_only();
drop function if exists pt_begin();
drop function if exists dpr_reviewer(text, uuid);
drop function if exists dpr_approver(text, uuid);
drop function if exists user_sees(uuid, text);
drop function if exists role_of(uuid);
drop function if exists name_of(uuid);

-- the v3 write rules, as they were
drop policy if exists d_insert on dprs;
drop policy if exists d_update on dprs;
drop policy if exists dl_write on dpr_lines;
drop policy if exists da_write on dpr_audit;
create policy d_insert on dprs for insert with check (can_edit_dpr(project_id));
create policy d_update on dprs for update using (
  (can_edit_dpr(project_id) and status in ('Draft','Submitted','Rejected')) or can_approve(project_id));
create policy dl_write on dpr_lines for all using (exists (select 1 from dprs d where d.id=dpr_id and can_edit_dpr(d.project_id)))
  with check (exists (select 1 from dprs d where d.id=dpr_id and can_edit_dpr(d.project_id)));
create policy da_write on dpr_audit for insert with check (exists (select 1 from dprs d where d.id=dpr_id and can_see(d.project_id)));

drop policy if exists cl_write on change_log;
create policy cl_write on change_log for insert with check (auth.uid() is not null);
alter table change_log alter column by_user drop default;
