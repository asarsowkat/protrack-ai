-- ProTrack rollback of schema update v44 (ProTrackAI v3.40): deleting an uploaded tender costing file.
-- Removes bcm_file_delete and the bucket's delete rule; the app then shows no Delete button (bcm_features says version 42).
-- Files already deleted stay deleted; their audit log entries are kept.
-- Safe to run even if v44 was never applied.
drop function if exists bcm_file_delete(jsonb);
drop policy if exists protrack_bcm_del on storage.objects;
drop function if exists pt_bcm_file_gone(uuid, text);
create or replace function bcm_features() returns jsonb language sql stable as $$ select '{"version": 42, "stages": [1, 2, 3, 4], "sap_wbs": true}'::jsonb $$;
grant execute on function bcm_features() to authenticated;
