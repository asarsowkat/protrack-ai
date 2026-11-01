-- ProTrack schema rollback v51 (ProTrackAI v3.48): undo schema-update-v51.sql. Removes the Client Invoice Builder's tables
-- (Schedule-C revisions and items, the P6 mapping and its reviews, the client invoices and their audit trail) and its
-- functions, and takes the six cib.* rights and the screen 'cib' out of the lists. The rights' default lines added to
-- pt_right_default stay (unused). The app then shows "The Client Invoice Builder needs the v51 database update" on its
-- screen; the invoice register and the cash pages keep working with the uploaded register.
drop function if exists cib_act(jsonb);
drop function if exists cib_features();
drop function if exists cib_head_clean(jsonb);
drop function if exists pt_cib_compute(text,text,int,date,date);
drop function if exists pt_cib_prog(text,uuid,text,jsonb,date);
drop function if exists pt_cib_log(text,text,text,jsonb,jsonb,text);
drop table if exists cib_audit, cib_invoices, cib_map_reviews, cib_maps, cib_items, cib_schedules cascade;
drop function if exists pt_cib_pay(jsonb,numeric,numeric,boolean,boolean);
drop function if exists pt_cib_rule_err(jsonb);
drop function if exists pt_cib_rule(jsonb,text,jsonb);
drop function if exists pt_cib_can(uuid,text,text);
do $$
declare cur text[] := pt_rights(); scr text[] := pt_screens();
begin
  cur := array(select x from unnest(cur) x where x not in ('cib.setup','cib.map','cib.prepare','cib.review','cib.approve','cib.certify'));
  execute format('create or replace function pt_rights() returns text[] language sql immutable as $f$ select %L::text[] $f$', cur::text);
  scr := array(select x from unnest(scr) x where x <> 'cib');
  execute format('create or replace function pt_screens() returns text[] language sql immutable as $f$ select %L::text[] $f$', scr::text);
end $$;
