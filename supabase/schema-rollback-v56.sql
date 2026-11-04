-- ProTrack schema rollback v56 (ProTrackAI v3.57): undo schema-update-v56.sql.
-- The invoicing phase can no longer be set or changed from an activity code; the phases already set stay on the
-- activities and are still used, and the project choices are kept, so running v56 again carries on from them.
-- media_features() reports version 55. Safe to run when v56 was never applied.
drop function if exists act_inv_phase_set(jsonb);
create or replace function media_features() returns jsonb language sql stable as $$ select jsonb_build_object('version', 55, 'logos', true, 'report_media', true, 'dpr_media', true, 'dpr_notes', true) $$;
