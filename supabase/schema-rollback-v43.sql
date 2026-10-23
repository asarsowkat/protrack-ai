-- ProTrack rollback of schema update v43 (ProTrackAI v3.39): the budget supplement and change request forms.
-- Removes the functions that save, submit, decide and post the forms and the Approval Hub link (the hub's token stops
-- working). The forms, their history, the outbox and the rows already posted to the logs are kept, so running
-- schema-update-v43.sql again brings everything back. The log guard goes back to v35 (rows posted from a WF can then be
-- changed on the log screen like the others). The checks of a supplement row keep the Saudi date. The rights wf.initiate
-- and wf.record stay listed (unused).
-- Safe to run even if v43 was never applied.
drop function if exists wf_form_save(jsonb);
drop function if exists wf_form_act(jsonb);
drop function if exists wf_hub_next(jsonb);
drop function if exists wf_hub_update(jsonb);
drop function if exists wf_hub_setup(jsonb);
drop function if exists wf_hub_status();
drop function if exists pt_wf_decide(wf_forms, text, text, date, text, text, text, uuid, text);
drop function if exists pt_wf_post(text, uuid, text);
drop function if exists pt_wf_payload(wf_forms);
drop function if exists pt_wf_check(wf_forms);
drop function if exists pt_wf_hub_ok(text);
drop trigger if exists trg_bsu_wf_keep on budget_supplements;
drop function if exists pt_bsu_wf_keep();
create or replace function pt_bsu_guard() returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('protrack.supp_update', true), '') = 'on' then return case when tg_op = 'DELETE' then old else new end; end if;
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end $$;
