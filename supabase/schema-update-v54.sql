-- ProTrack schema update v54 (ProTrackAI v3.53): site photos on the daily reports, which the weekly and monthly internal
-- reports pick from.
-- 1. report_media (v47) also keeps a daily report's site photos: kind 'dpr', period type 'dpr', period = the report's id, in the
--    private bucket report-media at <project>/dpr/dpr-<report id>/<id>.<ext>. Photos only (JPG, PNG, WEBP), at most 20 a report.
--    Read by those who see the project. Added, captioned and removed through report_media_act(p) by those who may edit the
--    report, with the same rule as dpr_save: while it is a draft, the one who prepares it (a foreman only their own), the site
--    engineers, the project manager and the super admin; once submitted or reviewed, the assigned site engineer, those with
--    dpr.approve and the super admin; never once it is approved or rejected.
-- 2. A weekly or monthly internal report takes a daily report's photo (or a weekly report's) as its own copy: the app copies the
--    stored file to the report's own path and adds it with 'from' = the photo it came from, as the client report already does
--    with the internal report's photos. No change is needed for that: the copy is checked like any photo of that report.
-- 3. media_features() reports version 54 with dpr_media.
-- Needs schema-update-v47.sql (report_media) and schema-update-v16.sql (dpr.create, dpr.approve). Additive. Safe to run twice.
-- Undo: schema-rollback-v54.sql.

do $$ begin
  if to_regclass('public.report_media') is null or to_regprocedure('public.report_media_act(jsonb)') is null then
    raise exception 'Run schema-update-v47.sql (STAGE-41-SETUP) first, then this update'; end if;
end $$;

-- ------------------------------------------------------------------ 1. the daily report's photos in report_media
alter table report_media drop constraint if exists report_media_kind_check;
alter table report_media add constraint report_media_kind_check check (kind in ('planning','client','dpr'));
alter table report_media drop constraint if exists report_media_period_type_check;
alter table report_media add constraint report_media_period_type_check check (period_type in ('week','month','dpr'));
alter table report_media drop constraint if exists report_media_dpr_check;
alter table report_media add constraint report_media_dpr_check check ((kind = 'dpr') = (period_type = 'dpr') and (kind <> 'dpr' or mime like 'image/%'));

-- may u edit this daily report, and so add or change its photos? (the rule of dpr_save, v16)
create or replace function pt_dpr_edit(u uuid, pid text, did text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare d dprs; r text := role_of(u); boss boolean;
begin
  if u is null or r is null or not user_sees(u, pid) then return false; end if;
  select * into d from dprs where id = did and project_id = pid;
  if d.id is null then return false; end if;
  if not (r in ('pm','sa') or pt_right(u, 'dpr.create')) then return false; end if;
  boss := pt_right(u, 'dpr.approve');
  if d.status = 'Draft' then
    return r in ('pm','sa') or boss or r <> 'foreman' or (d.foreman_id = u or (d.foreman_id is null and d.foreman = name_of(u)));
  elsif d.status in ('Submitted','Reviewed') then
    return r = 'sa' or boss or (r = 'eng' and dpr_reviewer(d.project_id, d.foreman_id) = u);
  end if;
  return false;
end $$;

-- may u add or change the photos and videos of this report period? tp is '<period type>-<period>' (as in the stored path)
create or replace function pt_rm_can(u uuid, pid text, k text, tp text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare pt text := split_part(tp, '-', 1); per text := substr(tp, length(split_part(tp, '-', 1)) + 2);
begin
  if u is null then return false; end if;
  if k = 'dpr' then return pt = 'dpr' and pt_dpr_edit(u, pid, per); end if;
  if k not in ('planning','client') or pt not in ('week','month') or not user_sees(u, pid) then return false; end if;
  if not (role_of(u) = 'sa' or pt_right(u, 'report.internal.prepare', false)) then return false; end if;
  if exists (select 1 from report_releases where project_id = pid and kind = k and period_type = pt and period = per and status in ('Draft','Submitted')) then
    return exists (select 1 from report_releases where project_id = pid and kind = k and period_type = pt and period = per and status = 'Draft');
  end if;
  return not exists (select 1 from report_releases where project_id = pid and kind = k and period_type = pt and period = per and status = 'Released');
end $$;
revoke execute on function pt_dpr_edit(uuid, text, text) from public, anon;
grant execute on function pt_dpr_edit(uuid, text, text) to authenticated;

-- p: {action: 'add', id, project_id, kind, period_type, period, path, name, mime, size, thumb, duration, caption, taken_on, sort, from}
--    {action: 'update', id, caption, taken_on}   {action: 'delete', id}
create or replace function report_media_act(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); a text := p ->> 'action'; m report_media; pid text; k text; pt text; per text; pth text; cap text; tk date; lim int;
begin
  if me is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if a is null or a not in ('add','update','delete') then raise exception 'Unknown action'; end if;
  if p ? 'caption' then cap := nullif(btrim(coalesce(p ->> 'caption', '')), ''); if length(coalesce(cap, '')) > 300 then raise exception 'A caption is 300 characters at most'; end if; end if;
  if nullif(p ->> 'taken_on', '') is not null then
    if (p ->> 'taken_on') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'The date taken is not a date'; end if; tk := (p ->> 'taken_on')::date; end if;
  if a = 'add' then
    pid := p ->> 'project_id'; k := p ->> 'kind'; pt := p ->> 'period_type'; per := p ->> 'period'; pth := p ->> 'path';
    if coalesce(p ->> 'id', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception 'Give the id of the photo or video'; end if;
    if not pt_rm_can(me, pid, k, pt || '-' || per) then
      if k = 'dpr' then raise exception 'Only those who may edit the daily report add its photos, while it is not approved' using errcode = '42501'; end if;
      raise exception 'Only those who prepare the report add its photos and videos, while it is not approved' using errcode = '42501'; end if;
    if pth is null or split_part(pth, '/', 1) <> pid or split_part(pth, '/', 2) <> k or split_part(pth, '/', 3) <> pt || '-' || per or split_part(pth, '/', 4) !~ ('^' || (p ->> 'id') || '\.(jpg|png|webp|mp4|webm|mov)$') then
      raise exception 'The stored path does not match the report'; end if;
    if k = 'dpr' and coalesce(p ->> 'mime', '') not in ('image/jpeg','image/png','image/webp') then raise exception 'A daily report takes photos only'; end if;
    if not exists (select 1 from storage.objects where bucket_id = 'report-media' and name = pth) then raise exception 'The file was not stored'; end if;
    lim := case when k = 'dpr' then 20 else 40 end;
    if (select count(*) from report_media where project_id = pid and kind = k and period_type = pt and period = per) >= lim then
      raise exception '%', case when k = 'dpr' then 'At most 20 photos in a daily report' else 'At most 40 photos and videos in a report' end; end if;
    if (p ->> 'thumb') is not null and (length(p ->> 'thumb') > 90000 or (p ->> 'thumb') not like 'data:image/jpeg;base64,%') then raise exception 'The preview is too large'; end if;
    insert into report_media (id, project_id, kind, period_type, period, path, name, mime, size_bytes, thumb, duration_s, caption, taken_on, sort, copied_from, uploaded_by, uploaded_name)
    values ((p ->> 'id')::uuid, pid, k, pt, per, pth, left(coalesce(nullif(btrim(p ->> 'name'), ''), 'file'), 200), p ->> 'mime', (p ->> 'size')::bigint, p ->> 'thumb',
            nullif(p ->> 'duration', '')::numeric::int, cap, tk, nullif(p ->> 'sort', '')::int,
            case when coalesce(p ->> 'from', '') ~ '^[0-9a-f-]{36}$' then (p ->> 'from')::uuid end, me, name_of(me));
    return jsonb_build_object('id', p ->> 'id');
  end if;
  select * into m from report_media where id = (p ->> 'id')::uuid for update;
  if m.id is null then raise exception 'Unknown photo or video'; end if;
  if not pt_rm_can(me, m.project_id, m.kind, m.period_type || '-' || m.period) then
    if m.kind = 'dpr' then raise exception 'The daily report''s photos are locked: only those who may edit the report change them' using errcode = '42501'; end if;
    raise exception 'The report is approved: its photos and videos are locked' using errcode = '42501'; end if;
  if a = 'delete' then delete from report_media where id = m.id; return jsonb_build_object('path', m.path); end if;
  update report_media set caption = case when p ? 'caption' then cap else caption end, taken_on = case when p ? 'taken_on' then tk else taken_on end, updated_at = now() where id = m.id;
  return jsonb_build_object('id', m.id);
end $$;

create or replace function media_features() returns jsonb language sql stable as $$ select jsonb_build_object('version', 54, 'logos', true, 'report_media', true, 'dpr_media', true) $$;
revoke execute on function report_media_act(jsonb), media_features() from public, anon;
grant execute on function report_media_act(jsonb), media_features() to authenticated;
