-- ProTrack schema rollback v34 (ProTrackAI v3.27): undo schema-update-v34.sql.
-- The release strategy and the document text stop working on the server: the functions go, and signed-in people can no
-- longer read golive_cfg, golive_audit, doc_text_meta or doc_text. The app then counts every module as live (as before
-- v3.27) and RASA does not quote documents. The tables and what they hold are kept, so running v34 again brings them back.

drop function if exists golive_set(jsonb);
drop function if exists doc_text_set(jsonb);
drop function if exists doc_text_info();
drop function if exists doc_text_search(jsonb);
drop function if exists golive_features();
do $$ begin
  if to_regclass('public.golive_cfg') is not null then revoke select on golive_cfg, golive_audit from authenticated; end if;
  if to_regclass('public.doc_text') is not null then revoke select on doc_text_meta, doc_text from authenticated; end if;
end $$;
