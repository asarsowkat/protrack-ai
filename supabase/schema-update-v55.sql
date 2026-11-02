-- ProTrack schema update v55 (ProTrackAI v3.54): the weather, major constraints / issues and recovery actions / next steps
-- of a daily report, printed on the Daily Productivity Report and in its approval email.
-- 1. dprs: weather (60 characters), issues_text and recovery_text (1,000 characters each). Read with the report, as before.
-- 2. dpr_notes_set(p): {id, weather, issues, recovery}. Kept by whoever may edit the report (pt_dpr_edit, v54: the rule of
--    dpr_save), so the app saves them right after dpr_save and before it submits the report.
-- 3. media_features() reports version 55.
-- Needs schema-update-v54.sql (pt_dpr_edit). Additive. Safe to run twice. Undo: schema-rollback-v55.sql.

do $$ begin
  if to_regprocedure('public.pt_dpr_edit(uuid,text,text)') is null then
    raise exception 'Run schema-update-v54.sql (STAGE-48-SETUP) first, then this update'; end if;
end $$;

alter table dprs add column if not exists weather text;
alter table dprs add column if not exists issues_text text;
alter table dprs add column if not exists recovery_text text;
alter table dprs drop constraint if exists dprs_notes_len;
alter table dprs add constraint dprs_notes_len check (length(coalesce(weather, '')) <= 60 and length(coalesce(issues_text, '')) <= 1000 and length(coalesce(recovery_text, '')) <= 1000);

-- p: {id, weather, issues, recovery}
create or replace function dpr_notes_set(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); d dprs; w text := nullif(btrim(coalesce(p ->> 'weather', '')), ''); i text := nullif(btrim(coalesce(p ->> 'issues', '')), '');
  rc text := nullif(btrim(coalesce(p ->> 'recovery', '')), '');
begin
  if me is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  select * into d from dprs where id = p ->> 'id';
  if d.id is null then raise exception 'Unknown daily report'; end if;
  if not pt_dpr_edit(me, d.project_id, d.id) then raise exception 'Only those who may edit the daily report change it, while it is not approved' using errcode = '42501'; end if;
  if length(coalesce(w, '')) > 60 then raise exception 'The weather is 60 characters at most'; end if;
  if length(coalesce(i, '')) > 1000 or length(coalesce(rc, '')) > 1000 then raise exception 'Constraints and recovery actions are 1,000 characters at most each'; end if;
  update dprs set weather = w, issues_text = i, recovery_text = rc, updated_at = now() where id = d.id;
  return jsonb_build_object('id', d.id);
end $$;
revoke execute on function dpr_notes_set(jsonb) from public, anon;
grant execute on function dpr_notes_set(jsonb) to authenticated;

create or replace function media_features() returns jsonb language sql stable as $$ select jsonb_build_object('version', 55, 'logos', true, 'report_media', true, 'dpr_media', true, 'dpr_notes', true) $$;
revoke execute on function media_features() from public, anon;
grant execute on function media_features() to authenticated;
