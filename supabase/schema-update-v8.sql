-- ProTrack schema update v8 (ProTrackAI v2.9, Phase 5: governed RASA answers)
-- Cost and billing rows are sent only to people whose role may see them. Foremen, site engineers and site
-- managers no longer receive invoice rows, invoice and costing import batches (which carry file totals) or the
-- older upload history for costing files and invoice registers. Everyone else keeps exactly the access they had.
-- RASA answers from what the browser receives, so this is the server-side half of "RASA never shows data the
-- person cannot open". Nothing is added to or removed from any table.
-- Run AFTER schema-update-v7.sql. Safe to run more than once. Undo: schema-rollback-v8.sql.

-- true when the signed-in person's role may see cost and billing figures (not a foreman, site engineer or site manager)
create or replace function pt_money_ok() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(my_role_text() not in ('foreman','eng','sm'), false) $$;

drop policy if exists inv_read on invoices;
create policy inv_read on invoices for select using (can_see(project_id) and pt_money_ok());

drop policy if exists uh_read on upload_history;
create policy uh_read on upload_history for select using (can_see(project_id) and (pt_money_ok() or kind not in ('costing','invoices')));

drop policy if exists ib_read on import_batches;
create policy ib_read on import_batches for select using (
  ((project_id is not null and can_see(project_id)) or (project_id is null and my_role_text() in ('sa','exec','plan')))
  and (pt_money_ok() or kind not in ('costing','invoices')));

revoke execute on function pt_money_ok() from public, anon;
grant execute on function pt_money_ok() to authenticated;
