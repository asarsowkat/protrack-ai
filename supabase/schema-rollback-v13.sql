-- ProTrack: undo schema update v13 (ProTrackAI v3.4). Stops new documents and box changes: removes doc_act and the
-- rule that lets people add files to the "project-docs" bucket. Keeps every box, document, file and history entry,
-- still readable by the same people. Safe to run twice.
drop policy if exists protrack_docs_add on storage.objects;
drop function if exists doc_act(jsonb);
