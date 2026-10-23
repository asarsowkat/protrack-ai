-- ProTrack rollback of schema update v38 (ProTrackAI v3.34): back to v3.33, where emails were prepared but not sent.
-- Removes the functions that queue and re-queue emails. The outbox table and every email in it are kept, so running
-- schema-update-v38.sql again brings everything back. Safe to run even if v38 was never applied.
drop function if exists mail_queue(jsonb);
drop function if exists mail_retry(jsonb);
drop function if exists mail_features();
drop function if exists pt_mail_person(uuid);
drop function if exists pt_mail_addr(uuid);
