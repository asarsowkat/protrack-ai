-- ProTrack schema rollback v50 (ProTrackAI v3.47): undo schema-update-v50.sql. Removes RASA Intelligence's tables (the knowledge
-- index, proposals, publications, gaps, feedback, questions, activity and settings) and its functions, and takes the four
-- rasa.* rights and the screen 'rasa' out of the lists. The rights' default lines added to pt_right_default stay (unused).
-- The app then shows "RASA Intelligence needs the v50 database update" on its screen; the RASA assistant keeps working.
drop function if exists rasa_act(jsonb);
drop function if exists rasa_sync(jsonb);
drop function if exists rasa_search(jsonb);
drop function if exists rasa_passages(jsonb);
drop function if exists rasa_features();
drop function if exists pt_rk_taught();
drop function if exists pt_rk_log(text,text,text,text,text,jsonb);
drop function if exists pt_rk_cls_ok(text,text,text,text);
drop table if exists rasa_chunks, rasa_sources, rasa_runs, rasa_publications, rasa_proposals, rasa_gaps, rasa_feedback, rasa_questions, rasa_activity, rasa_config cascade;
drop sequence if exists rasa_prop_seq;
drop sequence if exists rasa_gap_seq;
drop function if exists pt_rk_sees(uuid,text,text,text,text);
drop function if exists pt_rk_can(uuid,text);
do $$
declare cur text[] := pt_rights(); scr text[] := pt_screens();
begin
  cur := array(select x from unnest(cur) x where x not in ('rasa.teach','rasa.sync','rasa.review','rasa.company'));
  execute format('create or replace function pt_rights() returns text[] language sql immutable as $f$ select %L::text[] $f$', cur::text);
  scr := array(select x from unnest(scr) x where x <> 'rasa');
  execute format('create or replace function pt_screens() returns text[] language sql immutable as $f$ select %L::text[] $f$', scr::text);
end $$;
