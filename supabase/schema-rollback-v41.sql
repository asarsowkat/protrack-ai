-- ProTrack rollback of schema update v41 (ProTrackAI v3.37): back to stages 1 and 2 of Budget & Cost Management.
-- Removes the functions that write sheet roles, duplicate decisions, splits, explanations and budget versions, and the
-- server totals. The tables and every record in them are kept, so running schema-update-v41.sql again brings everything
-- back. The rights bcm.budget and bcm.budget.approve stay listed (unused). Safe to run even if v41 was never applied.
drop function if exists bcm_stage3(jsonb);
drop function if exists bcm_version_act(jsonb);
drop function if exists bcm_totals(text);
drop function if exists pt_bcm_eval(text);
drop function if exists pt_bcm_sap_id(text, text);
drop function if exists pt_bcm_tol(text, text, numeric);
create or replace function bcm_features() returns jsonb language sql stable as $$ select '{"version": 40, "stages": [1, 2], "sap_wbs": true}'::jsonb $$;
grant execute on function bcm_features() to authenticated;
