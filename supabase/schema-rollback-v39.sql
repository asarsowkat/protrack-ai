-- ProTrack rollback of schema update v39 (ProTrackAI v3.35): Budget & Cost Management, Automatic WBS Classification.
-- Removes every way to write (the functions and the upload rule of the bucket). The tables, the stored tender files,
-- the extracted lines, the classifications, the master data and every history and audit row are kept, so running
-- schema-update-v39.sql again brings everything back as it was. The rights and the screen stay listed (unused).
-- Safe to run even if v39 was never applied.
drop function if exists bcm_master_act(jsonb);
drop function if exists bcm_batch_save(jsonb);
drop function if exists bcm_file_add(jsonb);
drop function if exists bcm_file_run(jsonb);
drop function if exists bcm_classify(jsonb);
drop function if exists bcm_review(jsonb);
drop function if exists bcm_features();
drop function if exists bcm_lines_read(text, int, boolean);
do $$ begin
  if to_regclass('storage.objects') is not null then execute 'drop policy if exists protrack_bcm_add on storage.objects'; end if;
end $$;
