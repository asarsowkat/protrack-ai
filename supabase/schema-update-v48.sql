-- ProTrack schema update v48 (ProTrackAI v3.45): client report formats, and the log of client report exports.
-- 1. client_report_formats: a customer's client report format (or the default one when customer is null): its name, the weekly
--    and/or monthly reports it is for, its style (colours, font, cover lines, footer) and its pages in order. A page is filled
--    from ProTrack ('auto:<source>') or entered by the planning engineer ('manual:text', 'manual:table' with its columns,
--    'manual:images'). Read by everyone signed in; kept by the super admin through crf_save(p) (create, change, delete).
-- 2. client_report_format_picks: the format a project uses instead of its customer's; set through crf_pick(p) by those who
--    prepare the client report (report.internal.prepare) with access to the project, or a super admin.
-- 3. client_report_exports: every PowerPoint, Word or PDF made of a client report: who, when, the format, a review or client
--    copy, and the pages that were not updated. Written through crx_log(p); cannot be changed or deleted.
-- 4. The pages the planning engineer enters are kept with the client report in narrative.pages and narrative.review, which
--    release_act already stores whole: nothing changes there.
-- Needs schema-update-v47.sql (customers). Additive. Safe to run twice. Undo: schema-rollback-v48.sql.

do $$ begin
  if to_regclass('public.customers') is null or to_regprocedure('public.pt_right(uuid,text,boolean)') is null then
    raise exception 'Run schema-update-v47.sql (STAGE-41-SETUP) first, then this update'; end if;
end $$;

create table if not exists client_report_formats (
  id bigserial primary key,
  name text not null check (length(btrim(name)) between 3 and 120),
  customer text check (customer is null or length(customer) <= 200),
  periods text[] not null default array['week','month'] check (periods <@ array['week','month'] and cardinality(periods) >= 1),
  style jsonb not null default '{}'::jsonb check (jsonb_typeof(style) = 'object'),
  sections jsonb not null check (jsonb_typeof(sections) = 'array' and jsonb_array_length(sections) between 1 and 80),
  active boolean not null default true,
  rev int not null default 1,
  created_by uuid references profiles(id), created_at timestamptz not null default now(),
  updated_by uuid references profiles(id), updated_name text, updated_at timestamptz not null default now());
create table if not exists client_report_format_picks (
  project_id text primary key references projects(id) on delete cascade,
  format_id bigint not null references client_report_formats(id) on delete cascade,
  set_by uuid references profiles(id), set_at timestamptz not null default now());
create table if not exists client_report_exports (
  id bigserial primary key,
  release_id uuid,
  project_id text not null references projects(id) on delete cascade,
  period_type text not null check (period_type in ('week','month')),
  period text not null,
  format_id text, format_name text,
  file_kind text not null check (file_kind in ('PowerPoint','Word','PDF')),
  copy_kind text not null check (copy_kind in ('review','client')),
  pages_not_updated text[] not null default '{}',
  by_user uuid references profiles(id), by_name text, at_time timestamptz not null default now());
alter table client_report_formats enable row level security;
alter table client_report_format_picks enable row level security;
alter table client_report_exports enable row level security;
drop policy if exists crf_read on client_report_formats;
create policy crf_read on client_report_formats for select to authenticated using (true);
drop policy if exists crfp_read on client_report_format_picks;
create policy crfp_read on client_report_format_picks for select to authenticated using (user_sees(auth.uid(), project_id));
drop policy if exists crx_read on client_report_exports;
create policy crx_read on client_report_exports for select to authenticated using (user_sees(auth.uid(), project_id));
drop trigger if exists trg_crx_append on client_report_exports;
create trigger trg_crx_append before update or delete on client_report_exports for each row execute function pt_append_only();
drop trigger if exists trg_crx_truncate on client_report_exports;
create trigger trg_crx_truncate before truncate on client_report_exports execute function pt_no_truncate();
revoke all on client_report_formats, client_report_format_picks, client_report_exports from anon;
revoke insert, update, delete, truncate on client_report_formats, client_report_format_picks, client_report_exports from authenticated;
grant select on client_report_formats, client_report_format_picks, client_report_exports to authenticated;

-- the app's checks (crfCheck): name, periods, colours, footer, pages (key, title, source, table columns, guidance)
create or replace function pt_crf_check(p jsonb) returns text language plpgsql immutable as $$
declare s jsonb; keys text[] := '{}'; k text; src text;
begin
  if length(btrim(coalesce(p ->> 'name', ''))) < 3 or length(p ->> 'name') > 120 then return 'Give the format a name (3 to 120 characters)'; end if;
  if jsonb_typeof(p -> 'sections') is distinct from 'array' or jsonb_array_length(p -> 'sections') = 0 then return 'Add at least one page'; end if;
  if jsonb_array_length(p -> 'sections') > 80 then return 'At most 80 pages in a format'; end if;
  if jsonb_typeof(p -> 'periods') is distinct from 'array' or jsonb_array_length(p -> 'periods') = 0 then return 'Choose weekly, monthly or both'; end if;
  if coalesce(p #>> '{style,c1}', '') !~ '^[0-9A-Fa-f]{6}$' or coalesce(p #>> '{style,c2}', '') !~ '^[0-9A-Fa-f]{6}$' then return 'The colours are 6-digit hex codes, for example 40916C'; end if;
  if length(coalesce(p #>> '{style,footer}', '')) > 200 then return 'The footer is 200 characters at most'; end if;
  for s in select * from jsonb_array_elements(p -> 'sections') loop
    k := s ->> 'key'; src := s ->> 'src';
    if k is null or k = any(keys) then return 'Each page needs its own key'; end if; keys := keys || k;
    if length(btrim(coalesce(s ->> 'title', ''))) = 0 or length(s ->> 'title') > 120 then return 'Each page needs a title of up to 120 characters'; end if;
    if src is null or src !~ '^(auto:(cover|contents|info|summary|scurve|phases|baselines|milestones|keyms|ep|look|manpower|issues|contract|photos|thanks|note:(summary|achieved|next|issues|remarks))|manual:(text|table|images))$' then
      return format('Page "%s": unknown source', s ->> 'title'); end if;
    if src = 'manual:table' and (jsonb_typeof(s -> 'cols') is distinct from 'array' or jsonb_array_length(s -> 'cols') not between 1 and 12) then return format('Page "%s": give 1 to 12 column headings', s ->> 'title'); end if;
    if length(coalesce(s ->> 'hint', '')) > 300 then return format('Page "%s": the guidance is 300 characters at most', s ->> 'title'); end if;
  end loop;
  return null;
end $$;

-- p: {id, name, customer, periods, style, sections, active} or {id, delete: true}
create or replace function crf_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); e text; nid bigint; pr text[];
begin
  if me is null or role_of(me) is distinct from 'sa' then raise exception 'Only the super admin keeps the client report formats' using errcode = '42501'; end if;
  if coalesce((p ->> 'delete')::boolean, false) then delete from client_report_formats where id = (p ->> 'id')::bigint; return jsonb_build_object('deleted', p ->> 'id'); end if;
  e := pt_crf_check(p); if e is not null then raise exception '%', e; end if;
  select array_agg(x) into pr from jsonb_array_elements_text(p -> 'periods') x;
  if not (pr <@ array['week','month']) then raise exception 'Choose weekly, monthly or both'; end if;
  if nullif(p ->> 'id', '') is null then
    insert into client_report_formats (name, customer, periods, style, sections, active, created_by, updated_by, updated_name)
    values (btrim(p ->> 'name'), nullif(btrim(coalesce(p ->> 'customer', '')), ''), pr, p -> 'style', p -> 'sections', coalesce((p ->> 'active')::boolean, true), me, me, name_of(me)) returning id into nid;
    return jsonb_build_object('id', nid);
  end if;
  update client_report_formats set name = btrim(p ->> 'name'), customer = nullif(btrim(coalesce(p ->> 'customer', '')), ''), periods = pr, style = p -> 'style', sections = p -> 'sections',
    active = coalesce((p ->> 'active')::boolean, true), rev = rev + 1, updated_by = me, updated_name = name_of(me), updated_at = now() where id = (p ->> 'id')::bigint;
  if not found then raise exception 'Unknown format'; end if;
  return jsonb_build_object('id', p ->> 'id');
end $$;

-- p: {project_id, format_id (null: back to the customer's format)}
create or replace function crf_pick(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); pid text := p ->> 'project_id';
begin
  if me is null or not user_sees(me, pid) or not (role_of(me) = 'sa' or pt_right(me, 'report.internal.prepare', false)) then
    raise exception 'Only those who prepare the client report choose its format' using errcode = '42501'; end if;
  if nullif(p ->> 'format_id', '') is null then delete from client_report_format_picks where project_id = pid; return jsonb_build_object('ok', true); end if;
  if not exists (select 1 from client_report_formats where id = (p ->> 'format_id')::bigint and active) then raise exception 'Unknown format'; end if;
  insert into client_report_format_picks (project_id, format_id, set_by) values (pid, (p ->> 'format_id')::bigint, me)
  on conflict (project_id) do update set format_id = excluded.format_id, set_by = excluded.set_by, set_at = now();
  return jsonb_build_object('ok', true);
end $$;

-- p: {release_id, project_id, period_type, period, format_id, format_name, file, copy, pages_not_updated}
create or replace function crx_log(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); pid text := p ->> 'project_id'; nu text[];
begin
  if me is null or not user_sees(me, pid) or not (role_of(me) = 'sa' or pt_right(me, 'report.internal.prepare', false)) then
    raise exception 'Only those who prepare the client report export it' using errcode = '42501'; end if;
  if coalesce(p ->> 'file', '') not in ('PowerPoint','Word','PDF') or coalesce(p ->> 'copy', '') not in ('review','client') then raise exception 'Unknown export'; end if;
  select coalesce(array_agg(left(x, 120)), '{}') into nu from (select jsonb_array_elements_text(coalesce(p -> 'pages_not_updated', '[]'::jsonb)) x limit 80) q;
  insert into client_report_exports (release_id, project_id, period_type, period, format_id, format_name, file_kind, copy_kind, pages_not_updated, by_user, by_name)
  values (case when coalesce(p ->> 'release_id', '') ~ '^[0-9a-f-]{36}$' then (p ->> 'release_id')::uuid end, pid, p ->> 'period_type', left(p ->> 'period', 12), left(p ->> 'format_id', 40), left(p ->> 'format_name', 120),
          p ->> 'file', p ->> 'copy', nu, me, name_of(me));
  return jsonb_build_object('ok', true);
end $$;

create or replace function crf_features() returns jsonb language sql stable as $$ select jsonb_build_object('version', 48, 'client_report_formats', true) $$;
revoke execute on function crf_save(jsonb), crf_pick(jsonb), crx_log(jsonb), crf_features(), pt_crf_check(jsonb) from public, anon;
grant execute on function crf_save(jsonb), crf_pick(jsonb), crx_log(jsonb), crf_features() to authenticated;
