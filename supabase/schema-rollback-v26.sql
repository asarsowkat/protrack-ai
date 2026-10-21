-- ProTrack schema rollback v26: takes away recording letters on delay events (back to v3.19 / v3.19.1 on the server).
-- delay_corr_act, delay_corr_features() and the rule to add files to the "delay-docs" bucket are removed, so nobody
-- can add or remove a record, and an event with letters can be deleted again.
-- Everything is kept: delay_corr with every record (removed ones too), the files in "delay-docs" and their read rule,
-- so live.html still lists the letters and opens them. Run schema-update-v26.sql again to record letters again.
-- To remove them as well (not undoable), empty the bucket in Supabase -> Storage, then run separately:
-- drop table delay_corr;
-- Safe to run twice.

drop function if exists delay_corr_features();
drop function if exists delay_corr_act(jsonb);
drop function if exists pt_dly_corr_link(delay_events, delay_corr);
drop policy if exists protrack_delay_docs_add on storage.objects;
drop trigger if exists trg_dly_corr_guard on delay_events;
drop function if exists pt_dly_corr_guard();
