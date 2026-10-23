-- ProTrack rollback of schema update v42 (ProTrackAI v3.38): back to stages 1 to 3 of Budget & Cost Management.
-- Removes the functions that import SAP reports, keep their templates and prepare or confirm the SAP loading workbook.
-- The tables, the imported reports, the workbooks, their confirmations and the stored files are kept, so running
-- schema-update-v42.sql again brings everything back. A version left "Ready for SAP Loading" stays so until then.
-- The rights bcm.sap.import and bcm.sap stay listed (unused). Safe to run even if v42 was never applied.
drop function if exists bcm_sap_tpl(jsonb);
drop function if exists bcm_sap_import(jsonb);
drop function if exists bcm_sap_export(jsonb);
drop function if exists pt_bcm_sap_content(text);
drop function if exists pt_bcm_sap_bad(text, text);
create or replace function bcm_features() returns jsonb language sql stable as $$ select '{"version": 41, "stages": [1, 2, 3], "sap_wbs": true}'::jsonb $$;
grant execute on function bcm_features() to authenticated;
