-- ProTrack: undo schema update v9 (ProTrackAI v3.0). Removes the functions that prepare releases and upload the
-- logs. Keeps every release, revision, history entry, change order and claim log, and budget supplement log
-- (nothing is deleted), and keeps them read-only for the people who could read them. Safe to run twice.
drop function if exists release_act(jsonb);
drop function if exists log_import(jsonb);
drop function if exists pt_rel_log(uuid, text, text, jsonb);
drop function if exists pt_supp_approved(text, text);
drop function if exists pt_month_of(text);
drop function if exists pt_period_ok(text, text);
drop function if exists pt_release_preparer(uuid, text);
drop policy if exists ib_read on import_batches;
create policy ib_read on import_batches for select using (
  ((project_id is not null and can_see(project_id)) or (project_id is null and my_role_text() in ('sa','exec','plan')))
  and (pt_money_ok() or kind not in ('costing','invoices','volog','supplements')));
