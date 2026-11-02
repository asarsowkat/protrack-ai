-- ProTrack schema rollback v54 (ProTrackAI v3.53): undo schema-update-v54.sql.
-- Daily reports no longer keep site photos. Their records are removed from report_media (the weekly and monthly reports keep
-- the copies they took); the files stay in the bucket report-media under <project>/dpr/, where an administrator can delete them
-- in Storage. report_media_act and pt_rm_can are as in v47 again; media_features() reports version 47.
-- Safe to run when v54 was never applied.
delete from report_media where kind = 'dpr';
alter table report_media drop constraint if exists report_media_dpr_check;
alter table report_media drop constraint if exists report_media_kind_check;
alter table report_media add constraint report_media_kind_check check (kind in ('planning','client'));
alter table report_media drop constraint if exists report_media_period_type_check;
alter table report_media add constraint report_media_period_type_check check (period_type in ('week','month'));

create or replace function pt_rm_can(u uuid, pid text, k text, tp text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare pt text := split_part(tp, '-', 1); per text := substr(tp, length(split_part(tp, '-', 1)) + 2);
begin
  if u is null or k not in ('planning','client') or pt not in ('week','month') or not user_sees(u, pid) then return false; end if;
  if not (role_of(u) = 'sa' or pt_right(u, 'report.internal.prepare', false)) then return false; end if;
  if exists (select 1 from report_releases where project_id = pid and kind = k and period_type = pt and period = per and status in ('Draft','Submitted')) then
    return exists (select 1 from report_releases where project_id = pid and kind = k and period_type = pt and period = per and status = 'Draft');
  end if;
  return not exists (select 1 from report_releases where project_id = pid and kind = k and period_type = pt and period = per and status = 'Released');
end $$;
drop function if exists pt_dpr_edit(uuid, text, text);

create or replace function report_media_act(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); a text := p ->> 'action'; m report_media; pid text; k text; pt text; per text; pth text; cap text; tk date;
begin
  if me is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if a is null or a not in ('add','update','delete') then raise exception 'Unknown action'; end if;
  if p ? 'caption' then cap := nullif(btrim(coalesce(p ->> 'caption', '')), ''); if length(coalesce(cap, '')) > 300 then raise exception 'A caption is 300 characters at most'; end if; end if;
  if nullif(p ->> 'taken_on', '') is not null then
    if (p ->> 'taken_on') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'The date taken is not a date'; end if; tk := (p ->> 'taken_on')::date; end if;
  if a = 'add' then
    pid := p ->> 'project_id'; k := p ->> 'kind'; pt := p ->> 'period_type'; per := p ->> 'period'; pth := p ->> 'path';
    if coalesce(p ->> 'id', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception 'Give the id of the photo or video'; end if;
    if not pt_rm_can(me, pid, k, pt || '-' || per) then raise exception 'Only those who prepare the report add its photos and videos, while it is not approved' using errcode = '42501'; end if;
    if pth is null or split_part(pth, '/', 1) <> pid or split_part(pth, '/', 2) <> k or split_part(pth, '/', 3) <> pt || '-' || per or split_part(pth, '/', 4) !~ ('^' || (p ->> 'id') || '\.(jpg|png|webp|mp4|webm|mov)$') then
      raise exception 'The stored path does not match the report'; end if;
    if not exists (select 1 from storage.objects where bucket_id = 'report-media' and name = pth) then raise exception 'The file was not stored'; end if;
    if (select count(*) from report_media where project_id = pid and kind = k and period_type = pt and period = per) >= 40 then raise exception 'At most 40 photos and videos in a report'; end if;
    if (p ->> 'thumb') is not null and (length(p ->> 'thumb') > 90000 or (p ->> 'thumb') not like 'data:image/jpeg;base64,%') then raise exception 'The preview is too large'; end if;
    insert into report_media (id, project_id, kind, period_type, period, path, name, mime, size_bytes, thumb, duration_s, caption, taken_on, sort, copied_from, uploaded_by, uploaded_name)
    values ((p ->> 'id')::uuid, pid, k, pt, per, pth, left(coalesce(nullif(btrim(p ->> 'name'), ''), 'file'), 200), p ->> 'mime', (p ->> 'size')::bigint, p ->> 'thumb',
            nullif(p ->> 'duration', '')::numeric::int, cap, tk, nullif(p ->> 'sort', '')::int,
            case when coalesce(p ->> 'from', '') ~ '^[0-9a-f-]{36}$' then (p ->> 'from')::uuid end, me, name_of(me));
    return jsonb_build_object('id', p ->> 'id');
  end if;
  select * into m from report_media where id = (p ->> 'id')::uuid for update;
  if m.id is null then raise exception 'Unknown photo or video'; end if;
  if not pt_rm_can(me, m.project_id, m.kind, m.period_type || '-' || m.period) then raise exception 'The report is approved: its photos and videos are locked' using errcode = '42501'; end if;
  if a = 'delete' then delete from report_media where id = m.id; return jsonb_build_object('path', m.path); end if;
  update report_media set caption = case when p ? 'caption' then cap else caption end, taken_on = case when p ? 'taken_on' then tk else taken_on end, updated_at = now() where id = m.id;
  return jsonb_build_object('id', m.id);
end $$;

create or replace function media_features() returns jsonb language sql stable as $$ select jsonb_build_object('version', 47, 'logos', true, 'report_media', true) $$;
