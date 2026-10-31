-- ProTrack schema update v47 (ProTrackAI v3.44): the company logo, the customers with their logos, and the progress photos
-- and videos of the internal and client reports.
-- 1. pt_branding (one row): the company name and its official logo; customers: each customer's name and logo. Read by everyone
--    signed in (they are printed on reports); changed only by a super admin through branding_set(p) and customer_act(p).
--    A logo is an image (PNG, JPEG, WEBP, GIF or SVG) kept as a data URL of 400 KB at most; the app makes it web-sized.
--    Renaming a customer renames the client of its tenders and projects; a customer that is a client cannot be deleted.
-- 2. report_media: the photos and videos of an internal report ('planning') or a client report ('client') period, kept in the
--    private bucket report-media at <project>/<kind>/<period type>-<period>/<id>.<ext> (100 MB a file). Read by those who see
--    the project. Added, captioned and deleted through report_media_act(p) by those who prepare the report
--    (report.internal.prepare, or a super admin), with access to the project, while the period is not approved: no released
--    report yet, or a revision in draft. At most 40 a report. A file can be removed only once its record is gone.
-- 3. media_features() tells the app this update is in.
-- Needs schema-update-v16.sql (pt_right) and the client report update (report_releases with kind 'client'). Additive. Safe to
-- run twice. Undo: schema-rollback-v47.sql.

do $$ begin
  if to_regprocedure('public.pt_right(uuid,text,boolean)') is null or to_regclass('public.report_releases') is null then
    raise exception 'Run the Roles and rights update (schema-update-v16.sql) and the report release updates first, then this update'; end if;
end $$;

-- ------------------------------------------------------------------ 1. logos
create table if not exists pt_branding (
  id int primary key check (id = 1),
  company_name text check (company_name is null or length(company_name) <= 80),
  logo text check (logo is null or (length(logo) <= 560000 and logo ~ '^data:image/(png|jpeg|webp|gif|svg\+xml);base64,')),
  updated_by uuid references profiles(id), updated_name text, updated_at timestamptz not null default now());
insert into pt_branding (id) values (1) on conflict (id) do nothing;
create table if not exists customers (
  id bigserial primary key,
  name text not null check (length(btrim(name)) between 2 and 200),
  logo text check (logo is null or (length(logo) <= 560000 and logo ~ '^data:image/(png|jpeg|webp|gif|svg\+xml);base64,')),
  active boolean not null default true,
  created_by uuid references profiles(id), created_at timestamptz not null default now(),
  updated_by uuid references profiles(id), updated_name text, updated_at timestamptz not null default now());
create unique index if not exists customers_name_key on customers (lower(btrim(name)));
alter table pt_branding enable row level security;
alter table customers enable row level security;
drop policy if exists br_read on pt_branding;
create policy br_read on pt_branding for select to authenticated using (true);
drop policy if exists cu_read on customers;
create policy cu_read on customers for select to authenticated using (true);
revoke all on pt_branding, customers from anon;
revoke insert, update, delete, truncate on pt_branding, customers from authenticated;
grant select on pt_branding, customers to authenticated;

create or replace function pt_logo_ok(v text) returns boolean language sql immutable as $$
  select v is null or (length(v) <= 560000 and v ~ '^data:image/(png|jpeg|webp|gif|svg\+xml);base64,[A-Za-z0-9+/=]+$') $$;

-- p: {company_name, logo}
create or replace function branding_set(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); n text := nullif(btrim(coalesce(p ->> 'company_name', '')), ''); l text := nullif(p ->> 'logo', '');
begin
  if me is null or role_of(me) is distinct from 'sa' then raise exception 'Only the super admin sets the company logo' using errcode = '42501'; end if;
  if length(coalesce(n, '')) > 80 then raise exception 'The company name is 80 characters at most'; end if;
  if not pt_logo_ok(l) then raise exception 'The logo must be a PNG, JPG, WEBP, GIF or SVG image of 400 KB at most'; end if;
  if l like 'data:image/svg+xml%' and convert_from(decode(split_part(l, ',', 2), 'base64'), 'UTF8') ~* '<script|on[a-z]+=|javascript:' then raise exception 'This SVG contains scripts; export it again without them'; end if;
  update pt_branding set company_name = n, logo = l, updated_by = me, updated_name = name_of(me), updated_at = now() where id = 1;
  return jsonb_build_object('ok', true);
end $$;

-- p: {action: 'create' | 'update' | 'delete', id, name, logo, active}
create or replace function customer_act(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); a text := p ->> 'action'; n text := regexp_replace(btrim(coalesce(p ->> 'name', '')), '\s+', ' ', 'g'); l text := nullif(p ->> 'logo', '');
  cur customers; nid bigint;
begin
  if me is null or role_of(me) is distinct from 'sa' then raise exception 'Only the super admin keeps the customers' using errcode = '42501'; end if;
  if a is null or a not in ('create','update','delete') then raise exception 'Unknown action'; end if;
  if a <> 'create' then select * into cur from customers where id = (p ->> 'id')::bigint for update; if cur.id is null then raise exception 'Unknown customer'; end if; end if;
  if a = 'delete' then
    if exists (select 1 from projects where lower(btrim(client)) = lower(btrim(cur.name))) then raise exception 'This customer is the client of a tender or project: make it inactive instead'; end if;
    delete from customers where id = cur.id; return jsonb_build_object('id', cur.id);
  end if;
  if length(n) < 2 or length(n) > 200 then raise exception 'The customer name is 2 to 200 characters'; end if;
  if exists (select 1 from customers where lower(btrim(name)) = lower(n) and id is distinct from cur.id) then raise exception 'A customer with this name already exists'; end if;
  if not pt_logo_ok(l) then raise exception 'The logo must be a PNG, JPG, WEBP, GIF or SVG image of 400 KB at most'; end if;
  if l like 'data:image/svg+xml%' and convert_from(decode(split_part(l, ',', 2), 'base64'), 'UTF8') ~* '<script|on[a-z]+=|javascript:' then raise exception 'This SVG contains scripts; export it again without them'; end if;
  if a = 'create' then
    insert into customers (name, logo, active, created_by, updated_by, updated_name) values (n, l, coalesce((p ->> 'active')::boolean, true), me, me, name_of(me)) returning id into nid;
    return jsonb_build_object('id', nid);
  end if;
  if lower(cur.name) <> lower(n) then update projects set client = n where lower(btrim(client)) = lower(btrim(cur.name)); end if;
  update customers set name = n, logo = l, active = coalesce((p ->> 'active')::boolean, true), updated_by = me, updated_name = name_of(me), updated_at = now() where id = cur.id;
  return jsonb_build_object('id', cur.id);
end $$;

-- ------------------------------------------------------------------ 2. report photos and videos
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('report-media', 'report-media', false, 104857600, array['image/jpeg','image/png','image/webp','video/mp4','video/webm','video/quicktime'])
on conflict (id) do update set public = false, file_size_limit = 104857600, allowed_mime_types = excluded.allowed_mime_types;

create table if not exists report_media (
  id uuid primary key,
  project_id text not null references projects(id) on delete cascade,
  kind text not null check (kind in ('planning','client')),
  period_type text not null check (period_type in ('week','month')),
  period text not null check (length(period) between 6 and 10),
  path text not null unique,
  name text not null check (length(name) between 1 and 200),
  mime text not null check (mime in ('image/jpeg','image/png','image/webp','video/mp4','video/webm','video/quicktime')),
  size_bytes bigint not null check (size_bytes > 0 and size_bytes <= 104857600),
  thumb text check (thumb is null or (length(thumb) <= 90000 and thumb like 'data:image/jpeg;base64,%')),
  duration_s int check (duration_s is null or duration_s >= 0),
  caption text check (caption is null or length(caption) <= 300),
  taken_on date,
  sort int,
  copied_from uuid,
  uploaded_by uuid references profiles(id), uploaded_name text, uploaded_at timestamptz not null default now(),
  updated_at timestamptz not null default now());
create index if not exists report_media_period on report_media (project_id, kind, period_type, period);
alter table report_media enable row level security;
drop policy if exists rm_read on report_media;
create policy rm_read on report_media for select to authenticated using (user_sees(auth.uid(), project_id));
revoke all on report_media from anon;
revoke insert, update, delete, truncate on report_media from authenticated;
grant select on report_media to authenticated;

-- may u add or change the photos and videos of this report period? tp is '<period type>-<period>' (as in the stored path)
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
-- a stored file may be removed once no record points to it, by someone who may change that report period
create or replace function pt_rm_gone(u uuid, path text) returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from report_media m where m.path = pt_rm_gone.path)
     and pt_rm_can(u, split_part(path, '/', 1), split_part(path, '/', 2), split_part(path, '/', 3)) $$;
revoke execute on function pt_rm_can(uuid, text, text, text), pt_rm_gone(uuid, text) from public, anon;
grant execute on function pt_rm_can(uuid, text, text, text), pt_rm_gone(uuid, text) to authenticated;

drop policy if exists protrack_rm_read on storage.objects;
create policy protrack_rm_read on storage.objects for select to authenticated
  using (bucket_id = 'report-media' and public.user_sees(auth.uid(), split_part(name, '/', 1)));
drop policy if exists protrack_rm_add on storage.objects;
create policy protrack_rm_add on storage.objects for insert to authenticated
  with check (bucket_id = 'report-media' and array_length(string_to_array(name, '/'), 1) = 4 and name ~* '\.(jpe?g|png|webp|mp4|webm|mov)$'
              and public.pt_rm_can(auth.uid(), split_part(name, '/', 1), split_part(name, '/', 2), split_part(name, '/', 3)));
drop policy if exists protrack_rm_del on storage.objects;
create policy protrack_rm_del on storage.objects for delete to authenticated
  using (bucket_id = 'report-media' and public.pt_rm_gone(auth.uid(), name));

-- p: {action: 'add', id, project_id, kind, period_type, period, path, name, mime, size, thumb, duration, caption, taken_on, sort, from}
--    {action: 'update', id, caption, taken_on}   {action: 'delete', id}
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
revoke execute on function branding_set(jsonb), customer_act(jsonb), report_media_act(jsonb), media_features() from public, anon;
grant execute on function branding_set(jsonb), customer_act(jsonb), report_media_act(jsonb), media_features() to authenticated;
