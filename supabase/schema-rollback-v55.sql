-- ProTrack schema rollback v55 (ProTrackAI v3.54): undo schema-update-v55.sql.
-- The weather, constraints and recovery actions can no longer be changed; the columns and what was written in them are kept,
-- so running v55 again brings them back. media_features() reports version 54. Safe to run when v55 was never applied.
drop function if exists dpr_notes_set(jsonb);
create or replace function media_features() returns jsonb language sql stable as $$ select jsonb_build_object('version', 54, 'logos', true, 'report_media', true, 'dpr_media', true) $$;
