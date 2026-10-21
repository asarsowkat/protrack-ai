-- ProTrack schema rollback v34 (ProTrackAI v3.27): undo schema-update-v34.sql.
-- The release strategy and the document text stop working on the server: the functions go, and signed-in people can no
-- longer read golive_cfg, golive_audit, doc_text_meta or doc_text. The app then counts every module as live (as before
-- v3.27) and RASA does not quote documents. The tables and what they hold are kept, so running v34 again brings them back.
-- v3.28.2: safe to run even if schema-update-v34.sql was never applied (the table golive_cfg is not on the database): then it changes
-- nothing and its result says so. Otherwise it runs the rollback below, unchanged. The result is one row.

do $pt_rollback$
declare applied boolean := to_regclass('public.golive_cfg') is not null;
begin
  if not applied then
    perform set_config('protrack.rollback', 'schema-update-v34.sql is not on this database (never run, or already undone): nothing to undo, nothing was changed.', false);
    return;
  end if;
  execute $pt_rollback_body$
drop function if exists golive_set(jsonb);
drop function if exists doc_text_set(jsonb);
drop function if exists doc_text_info();
drop function if exists doc_text_search(jsonb);
drop function if exists golive_features();
do $$ begin
  if to_regclass('public.golive_cfg') is not null then revoke select on golive_cfg, golive_audit from authenticated; end if;
  if to_regclass('public.doc_text') is not null then revoke select on doc_text_meta, doc_text from authenticated; end if;
end $$;
$pt_rollback_body$;
  perform set_config('protrack.rollback', 'schema-update-v34.sql undone.', false);
end $pt_rollback$;
select current_setting('protrack.rollback', true) as result;
