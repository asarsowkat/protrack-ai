-- ProTrack schema update v42 (ProTrackAI v3.38): Budget & Cost Management, stage 4 (reporting and SAP preparation).
-- 1. Rights: bcm.sap.import (import the monthly SAP ECC reports; costing engineers) and bcm.sap (the SAP authorized
--    user: prepare the SAP loading workbook of an approved budget version and record its loading with the SAP reference;
--    nobody by default, the super admin gives it).
-- 2. SAP reports (bcm_sap_reports, bcm_sap_lines): one report per project, period and kind
--    - budget, actual and commitment by WBS element, as S_ALR_87013558 gives;
--    - actual cost line items, as CJI3 gives (postings of the period, or to the end of the period);
--    - open commitment line items, as CJI5 gives.
--    The rows are checked on the server, the figures by WBS element are worked out on the server (a report with totals at
--    each level counts on an element only what is not already in the elements below it), and the report is frozen.
--    A new report for the same period and kind supersedes the earlier one, which is kept. The original file is kept in
--    the private bucket under bcm/<project>/sap/<sha256>.
-- 3. Column templates for the reports (bcm_sap_tpls).
-- 4. The SAP loading workbook (bcm_sap_exports): made from an approved budget version, on the server
--    - the amounts by SAP WBS ID, every one a valid SAP WBS ID of the project (else nothing is made);
--    - the first loading of a project as its original budget, later ones as supplements and returns against the version
--      last confirmed as loaded.
--    The version becomes "Ready for SAP Loading". Only a SAP authorized user records "SAP Loading Confirmed", with the
--    SAP reference and date; or returns it with a reason. Nothing is sent to SAP and no loading is simulated.
-- 5. A fix of v41: the lines of a budget version are read only with their project (they were readable by people with
--    cost figures outside the project).
-- Needs schema-update-v41.sql. Additive. Safe to run twice. Undo: schema-rollback-v42.sql.

do $$ begin
  if to_regprocedure('public.bcm_version_act(jsonb)') is null then raise exception 'Run schema-update-v41.sql first, then this update'; end if;
end $$;

-- ------------------------------------------------------------------ 1. rights
do $$
declare cur text[] := pt_rights(); src text; k text;
begin
  foreach k in array array['bcm.sap.import','bcm.sap'] loop if not (k = any(cur)) then cur := cur || k; end if; end loop;
  execute format('create or replace function pt_rights() returns text[] language sql immutable as $f$ select %L::text[] $f$', cur::text);
  select prosrc into src from pg_proc where proname = 'pt_right_default' and pronamespace = 'public'::regnamespace and pronargs = 2;
  if position('bcm.sap.import' in src) = 0 then
    if position('else false end' in src) = 0 then raise exception 'pt_right_default does not have the expected shape; add the bcm.sap rights by hand'; end if;
    src := regexp_replace(src, 'else false end', E'when ''bcm.sap.import''          then base = ''costing''\n    when ''bcm.sap''                 then false\n    else false end');
    execute format('create or replace function pt_right_default(base text, k text) returns boolean language sql immutable as $f$%s$f$', src);
  end if;
end $$;

-- ------------------------------------------------------------------ 2. tables
create table if not exists bcm_sap_tpls (
  id text primary key, name text not null unique, kind text not null check (kind in ('wbs','actual','commit')), map jsonb not null, opts jsonb,
  by_user uuid, by_name text, at_time timestamptz not null default now());
create table if not exists bcm_sap_reports (
  id text primary key, project_id text not null references projects(id) on delete cascade, period text not null check (period ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  kind text not null check (kind in ('wbs','actual','commit')), cumulative boolean not null default false, currency text not null check (currency ~ '^[A-Z]{3}$'),
  file jsonb not null, template text, has jsonb not null, hier boolean not null default true, agg jsonb not null, totals jsonb not null, warns jsonb, n int not null,
  status text not null default 'Frozen' check (status in ('Frozen','Superseded')), superseded_by text, imported_by uuid, imported_by_name text, imported_at timestamptz not null default now());
create index if not exists bcm_sap_reports_p on bcm_sap_reports (project_id, period, kind);
create table if not exists bcm_sap_lines (
  report_id text not null references bcm_sap_reports(id) on delete cascade, n int not null, row_no int, wbs text not null, descr text,
  budget numeric(24,6), actual numeric(24,6), commit numeric(24,6), eac numeric(24,6), etc numeric(24,6), posting_date date, cost_element text, doc text, primary key (report_id, n));
create table if not exists bcm_sap_exports (
  id text primary key, version_id text not null references bcm_versions(id) on delete cascade, project_id text not null, seq int not null,
  content jsonb not null, check_md5 text not null, status text not null default 'Generated' check (status in ('Generated','Confirmed','Returned')),
  generated_by uuid, generated_by_name text, generated_at timestamptz not null default now(),
  sap_ref text, sap_date date, note text, closed_by uuid, closed_by_name text, closed_at timestamptz, reason text, unique (version_id, seq));

-- the rows of a SAP report never change once it is frozen
create or replace function pt_bcm_sap_frozen() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' and not exists (select 1 from bcm_sap_reports where id = old.report_id) then return old; end if;
  if tg_op = 'INSERT' and current_setting('protrack.bcm_sap_import', true) = 'on' then return new; end if;
  raise exception 'The rows of an imported SAP report never change; import the report again';
end $$;
drop trigger if exists bcm_sap_lines_frozen on bcm_sap_lines;
create trigger bcm_sap_lines_frozen before insert or update or delete on bcm_sap_lines for each row execute function pt_bcm_sap_frozen();

do $$
declare t text;
begin
  foreach t in array array['bcm_sap_tpls','bcm_sap_reports','bcm_sap_lines','bcm_sap_exports'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists %I on %I', t || '_read', t);
    execute format('revoke all on %I from anon', t);
    execute format('revoke insert, update, delete, truncate on %I from authenticated', t);
    execute format('grant select on %I to authenticated', t);
  end loop;
end $$;
-- a row read through its parent: the parent is looked up past its own read rule, and a missing parent never means "no project"
-- (this also closes a gap of v41: the lines of a budget version were readable by people with cost figures outside the project)
create or replace function pt_bcm_reads_ver(vid text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select pt_bcm_reads(v.project_id) from bcm_versions v where v.id = vid), false) $$;
create or replace function pt_bcm_reads_sr(rid text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select pt_bcm_reads(r.project_id) from bcm_sap_reports r where r.id = rid), false) $$;
revoke execute on function pt_bcm_reads_ver(text), pt_bcm_reads_sr(text) from public, anon;
grant execute on function pt_bcm_reads_ver(text), pt_bcm_reads_sr(text) to authenticated;
drop policy if exists bcm_version_lines_read on bcm_version_lines;
create policy bcm_version_lines_read on bcm_version_lines for select using (pt_bcm_reads_ver(version_id));
create policy bcm_sap_tpls_read on bcm_sap_tpls for select using (pt_bcm_reads(null));
create policy bcm_sap_reports_read on bcm_sap_reports for select using (pt_bcm_reads(project_id));
create policy bcm_sap_lines_read on bcm_sap_lines for select using (pt_bcm_reads_sr(report_id));
create policy bcm_sap_exports_read on bcm_sap_exports for select using (pt_bcm_reads(project_id));

-- the original SAP report is kept in the private bucket under bcm/<project>/sap/<sha256>.<ext>
create or replace function pt_bcm_file_can(u uuid, path text, w boolean) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(split_part(path, '/', 1) = 'bcm' and case
    when w and split_part(path, '/', 3) = 'sap' then pt_bcm(u, split_part(path, '/', 2), 'bcm.sap.import')
    when w then pt_bcm(u, split_part(path, '/', 2), 'bcm.upload')
      and exists (select 1 from bcm_batches b where b.id = split_part(path, '/', 3) and b.project_id = split_part(path, '/', 2) and b.status = 'Open')
    else pt_bcm(u, split_part(path, '/', 2), 'money.view') end, false) $$;

-- ------------------------------------------------------------------ 3. helpers
-- why an ID is not a valid SAP WBS ID of the project (its PE number, then segments of the digits of each level), or null
create or replace function pt_bcm_sap_bad(sid text, pid text) returns text language plpgsql stable security definer set search_path = public as $$
declare pc text := (select coalesce(pe_number, id) from projects where id = pid); sep text := coalesce(pt_bcm_cfg() -> 'sap' ->> 'sep', '-');
        dg jsonb := coalesce(pt_bcm_cfg() -> 'sap' -> 'digits', '[2,3,2]'::jsonb); segs text[]; i int; d int;
begin
  if coalesce(btrim(sid), '') = '' then return 'no SAP WBS ID'; end if;
  if left(sid, length(pc) + length(sep)) <> pc || sep then return 'does not start with the project''s PE number ' || pc; end if;
  segs := string_to_array(substr(sid, length(pc) + length(sep) + 1), sep);
  for i in 1 .. coalesce(array_length(segs, 1), 0) loop
    d := (dg ->> least(i - 1, jsonb_array_length(dg) - 1))::int;
    if segs[i] !~ ('^[0-9]{' || d || '}$') then return format('level %s should be %s digits ("%s")', i, d, segs[i]); end if;
  end loop;
  return null;
end $$;
-- the content of a SAP loading workbook for a version: amounts by SAP WBS ID, and the change from the version last loaded
create or replace function pt_bcm_sap_content(vid text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v bcm_versions; pv bcm_versions; items jsonb; ch jsonb := null; ex jsonb; tot numeric; ptot numeric := null;
begin
  select * into v from bcm_versions where id = vid;
  select o.* into pv from bcm_versions o join bcm_sap_exports e on e.version_id = o.id and e.status = 'Confirmed'
    where o.project_id = v.project_id and o.id <> v.id and o.status = 'SAP Loading Confirmed' order by e.closed_at desc limit 1;
  with a as (select coalesce(btrim(sap_wbs_id), '') as sap, min(descr) as descr, min(user_field) as uf, min(wbs_code) as code, sum(amount) as amount, jsonb_agg(n order by n) as ns
               from bcm_version_lines where version_id = vid group by 1)
  select coalesce(jsonb_agg(jsonb_build_object('sap', sap, 'desc', descr, 'uf', uf, 'code', code, 'amount', amount::numeric(24,6)::text) order by sap), '[]'::jsonb),
         coalesce(jsonb_agg(jsonb_build_object('sap', case when sap = '' then '(none)' else sap end, 'lines', ns, 'reason', pt_bcm_sap_bad(sap, v.project_id)) order by sap) filter (where pt_bcm_sap_bad(sap, v.project_id) is not null), '[]'::jsonb),
         coalesce(sum(amount), 0)
    into items, ex, tot from a;
  if pv.id is not null then
    select sum(amount) into ptot from bcm_version_lines where version_id = pv.id;
    with a as (select btrim(sap_wbs_id) as sap, min(descr) as descr, sum(amount) as amount from bcm_version_lines where version_id = vid group by 1),
         b as (select btrim(sap_wbs_id) as sap, min(descr) as descr, sum(amount) as amount from bcm_version_lines where version_id = pv.id group by 1),
         c as (select coalesce(a.sap, b.sap) as sap, coalesce(a.descr, b.descr) as descr, coalesce(b.amount, 0) as prev, coalesce(a.amount, 0) as now from a full join b on a.sap = b.sap)
    select coalesce(jsonb_agg(jsonb_build_object('sap', sap, 'desc', descr, 'prev', prev::numeric(24,6)::text, 'now', now::numeric(24,6)::text, 'diff', (now - prev)::numeric(24,6)::text) order by sap) filter (where now <> prev), '[]'::jsonb)
      into ch from c;
  end if;
  return jsonb_build_object('items', items, 'changes', ch, 'excluded', ex, 'total', tot::numeric(24,6)::text, 'prev_total', ptot::numeric(24,6)::text,
    'prev', case when pv.id is null then null else jsonb_build_object('id', pv.id, 'kind', pv.kind, 'rev_no', pv.rev_no, 'sap_ref', pv.sap_ref) end);
end $$;

-- ------------------------------------------------------------------ 4. column templates
create or replace function bcm_sap_tpl(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; who text; rl text; nm text := btrim(coalesce(p ->> 'name', '')); tid text;
begin
  select * into u, who, rl from pt_bcm_me();
  if not pt_bcm(u, null, 'bcm.sap.import') then raise exception 'You cannot keep SAP report templates (the bcm.sap.import right)' using errcode = '42501'; end if;
  if p ->> 'action' = 'drop' then delete from bcm_sap_tpls where id = p ->> 'id'; perform pt_bcm_log(u, who, rl, 'SAP report template removed', 'sap_tpl', p ->> 'id', null, '{}'::jsonb); return jsonb_build_object('ok', true); end if;
  if length(nm) < 3 or length(nm) > 80 then raise exception 'Give the template a name of 3 to 80 characters'; end if;
  if not (p ->> 'kind' = any(array['wbs','actual','commit'])) then raise exception 'Choose the kind of report'; end if;
  if jsonb_typeof(p -> 'map') <> 'object' or not (p -> 'map' ? 'wbs') then raise exception 'The template needs at least the WBS element column'; end if;
  tid := coalesce((select id from bcm_sap_tpls where name = nm), 'ST-' || substr(md5(random()::text || clock_timestamp()::text), 1, 8));
  insert into bcm_sap_tpls (id, name, kind, map, opts, by_user, by_name) values (tid, nm, p ->> 'kind', p -> 'map', p -> 'opts', u, who)
    on conflict (id) do update set kind = excluded.kind, map = excluded.map, opts = excluded.opts, by_user = u, by_name = who, at_time = now();
  perform pt_bcm_log(u, who, rl, 'SAP report template saved', 'sap_tpl', tid, null, jsonb_build_object('name', nm, 'kind', p ->> 'kind', 'map', p -> 'map'));
  return jsonb_build_object('ok', true, 'id', tid);
end $$;

-- ------------------------------------------------------------------ 5. importing a SAP report
create or replace function bcm_sap_import(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; who text; rl text; pid text := p ->> 'project_id'; per text := p ->> 'period'; knd text := p ->> 'kind'; cum boolean := coalesce((p ->> 'cumulative')::boolean, false);
        cur text := p ->> 'currency'; vhier boolean := coalesce((p ->> 'hier')::boolean, true); sep text := coalesce(pt_bcm_cfg() -> 'sap' ->> 'sep', '-');
        x jsonb; cnt int := 0; rid text; vhas jsonb; meas text[] := array['budget','actual','commit','eac','etc']; m text; vagg jsonb; vtots jsonb := '{}'::jsonb; warns jsonb := '[]'::jsonb;
        ps date; pe date; d date; dup text; s numeric; ft numeric; tol numeric; old text; pth text;
begin
  select * into u, who, rl from pt_bcm_me();
  if not exists (select 1 from projects where id = pid) then raise exception 'Choose the project'; end if;
  if not pt_bcm(u, pid, 'bcm.sap.import') then raise exception 'You cannot import SAP reports on this project (the bcm.sap.import right)' using errcode = '42501'; end if;
  if coalesce(per, '') !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'Choose the period (year and month)'; end if;
  if per > to_char(current_date, 'YYYY-MM') then raise exception 'The period % is in the future', per; end if;
  if not (knd = any(array['wbs','actual','commit'])) then raise exception 'Choose the kind of report'; end if;
  if coalesce(cur, '') !~ '^[A-Z]{3}$' then raise exception 'Choose the currency'; end if;
  if jsonb_typeof(p -> 'rows') <> 'array' or jsonb_array_length(p -> 'rows') = 0 or jsonb_array_length(p -> 'rows') > 20000 then raise exception 'Send 1 to 20000 rows'; end if;
  if coalesce(p -> 'file' ->> 'sha256', '') !~ '^[0-9a-f]{64}$' then raise exception 'The file fingerprint is missing'; end if;
  select id into old from bcm_sap_reports where project_id = pid and file ->> 'sha256' = p -> 'file' ->> 'sha256' limit 1;
  if old is not null then raise exception 'This file is already imported (report %)', old; end if;
  pth := p -> 'file' ->> 'path';
  if pth is null or pth <> 'bcm/' || pid || '/sap/' || (p -> 'file' ->> 'sha256') || '.' || coalesce(p -> 'file' ->> 'kind', 'xlsx') or not exists (select 1 from storage.objects where bucket_id = 'bcm-tender' and name = pth) then
    raise exception 'Upload the file to storage first'; end if;
  vhas := case when knd = 'wbs' then (select jsonb_object_agg(k, coalesce((p -> 'has' ->> k)::boolean, false)) from unnest(meas) k) else jsonb_build_object(knd, true) end;
  if knd = 'wbs' and not exists (select 1 from jsonb_each_text(vhas) where value = 'true') then raise exception 'The report has no Budget, Actual, Commitment or forecast column'; end if;
  ps := (per || '-01')::date; pe := (ps + interval '1 month' - interval '1 day')::date;
  rid := 'SR-' || replace(per, '-', '') || '-' || substr(md5(random()::text || clock_timestamp()::text), 1, 6);
  insert into bcm_sap_reports (id, project_id, period, kind, cumulative, currency, file, template, has, hier, agg, totals, n, imported_by, imported_by_name)
    values (rid, pid, per, knd, cum, cur, p -> 'file', nullif(left(p ->> 'template', 80), ''), vhas, vhier, '{}'::jsonb, '{}'::jsonb, 0, u, who);
  perform set_config('protrack.bcm_sap_import', 'on', true);
  for x in select * from jsonb_array_elements(p -> 'rows') loop
    cnt := cnt + 1;
    if coalesce(btrim(x ->> 'wbs'), '') = '' then raise exception 'Row %: no WBS element', coalesce(x ->> 'row', cnt::text); end if;
    if length(x ->> 'wbs') > 60 then raise exception 'Row %: the WBS element is longer than 60 characters', x ->> 'row'; end if;
    foreach m in array meas loop
      if (vhas ->> m)::boolean is true and x ->> m is not null and (x ->> m) !~ '^-?[0-9]+(\.[0-9]+)?$' then raise exception 'Row %: % "%" is not a number', x ->> 'row', m, x ->> m; end if;
    end loop;
    d := null;
    if knd <> 'wbs' and nullif(x ->> 'date', '') is not null then
      if (x ->> 'date') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Row %: the date % is not a date', x ->> 'row', x ->> 'date'; end if;
      d := (x ->> 'date')::date;
      if knd = 'actual' and d > pe then raise exception 'Row %: posted on %, after the period %', x ->> 'row', d, per; end if;
      if knd = 'actual' and not cum and d < ps then raise exception 'Row %: posted on %, before the period % (or choose postings to the end of the period)', x ->> 'row', d, per; end if;
    end if;
    insert into bcm_sap_lines (report_id, n, row_no, wbs, descr, budget, actual, commit, eac, etc, posting_date, cost_element, doc)
      values (rid, cnt, (x ->> 'row')::int, btrim(x ->> 'wbs'), left(x ->> 'desc', 300),
              case when (vhas ->> 'budget')::boolean then (x ->> 'budget')::numeric end, case when (vhas ->> 'actual')::boolean then (x ->> 'actual')::numeric end,
              case when (vhas ->> 'commit')::boolean then (x ->> 'commit')::numeric end, case when (vhas ->> 'eac')::boolean then (x ->> 'eac')::numeric end,
              case when (vhas ->> 'etc')::boolean then (x ->> 'etc')::numeric end, d, left(x ->> 'ce', 60), left(x ->> 'doc', 60));
  end loop;
  perform set_config('protrack.bcm_sap_import', 'off', true);
  if knd = 'wbs' then
    select min(l.wbs) into dup from bcm_sap_lines l where report_id = rid group by lower(l.wbs) having count(*) > 1 limit 1;
    if dup is not null then raise exception '% is repeated in the report', dup; end if;
    -- with totals at each level, an element counts only what is not in the elements below it
    with l as (select lower(wbs) as k, * from bcm_sap_lines where report_id = rid),
         pr as (select a.k, (select b.k from l b where b.k <> a.k and a.k like b.k || sep || '%' order by length(b.k) desc limit 1) as parent from l a),
         ch as (select parent as k, sum(l.budget) as budget, sum(l.actual) as actual, sum(l.commit) as commit, sum(l.eac) as eac, sum(l.etc) as etc from pr join l on l.k = pr.k where parent is not null group by parent),
         o as (select l.k, l.wbs, l.descr, (ch.k is not null) as parent_row,
                 l.budget - case when vhier then coalesce(ch.budget, 0) else 0 end as budget, l.actual - case when vhier then coalesce(ch.actual, 0) else 0 end as actual,
                 l.commit - case when vhier then coalesce(ch.commit, 0) else 0 end as commit, l.eac - case when vhier then coalesce(ch.eac, 0) else 0 end as eac,
                 l.etc - case when vhier then coalesce(ch.etc, 0) else 0 end as etc
               from l left join ch on ch.k = l.k)
    select jsonb_object_agg(k, jsonb_strip_nulls(jsonb_build_object('wbs', wbs, 'desc', descr, 'parent_row', parent_row, 'budget', budget::numeric(24,6)::text, 'actual', actual::numeric(24,6)::text,
             'commit', commit::numeric(24,6)::text, 'eac', eac::numeric(24,6)::text, 'etc', etc::numeric(24,6)::text))) into vagg from o;
  else
    select jsonb_object_agg(k, jsonb_build_object('wbs', wbs, 'desc', descr, 'n', n, knd, v::numeric(24,6)::text, 'inP', vp::numeric(24,6)::text)) into vagg
      from (select lower(wbs) as k, min(wbs) as wbs, min(descr) as descr, count(*) as n, sum(coalesce(case when knd = 'actual' then actual else commit end, 0)) as v,
                   sum(coalesce(case when knd = 'actual' then actual else commit end, 0)) filter (where posting_date is null or posting_date >= ps) as vp
              from bcm_sap_lines where report_id = rid group by lower(wbs)) z;
  end if;
  foreach m in array meas loop
    if (vhas ->> m)::boolean is true then
      select sum((value ->> m)::numeric) into s from jsonb_each(vagg);
      vtots := vtots || jsonb_build_object(m, coalesce(s, 0)::numeric(24,6)::text);
      if p -> 'ftot' ->> m is not null then
        ft := (p -> 'ftot' ->> m)::numeric; tol := pt_bcm_tol(cur, null, coalesce(s, 0));
        if abs(ft - coalesce(s, 0)) > tol then raise exception 'The total row gives % %, the elements add up to %', m, ft, coalesce(s, 0); end if;
      end if;
    end if;
  end loop;
  update bcm_sap_reports set agg = coalesce(vagg, '{}'::jsonb), totals = vtots, n = cnt, warns = coalesce(p -> 'warns', '[]'::jsonb) where id = rid;
  update bcm_sap_reports set status = 'Superseded', superseded_by = rid where project_id = pid and period = per and kind = knd and status = 'Frozen' and id <> rid;
  perform pt_bcm_log(u, who, rl, 'SAP report imported', 'sap_report', rid, pid, jsonb_build_object('period', per, 'kind', knd, 'rows', cnt, 'totals', vtots, 'file', p -> 'file' ->> 'name'));
  return jsonb_build_object('ok', true, 'id', rid, 'n', cnt, 'totals', vtots);
end $$;

-- ------------------------------------------------------------------ 6. the SAP loading workbook and its confirmation
create or replace function bcm_sap_export(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; who text; rl text; act text := p ->> 'action'; v bcm_versions; e bcm_sap_exports; c jsonb; eid text; sq int; w text; lc bcm_versions; rs text := left(btrim(coalesce(p ->> 'reason', '')), 1000);
        ref text := btrim(coalesce(p ->> 'sap_ref', '')); sd date;
begin
  select * into u, who, rl from pt_bcm_me();
  if act = 'generate' then
    select * into v from bcm_versions where id = p ->> 'version_id' for update;
    if v.id is null then raise exception 'Unknown version'; end if;
    if not pt_bcm(u, v.project_id, 'bcm.sap') then raise exception 'Only a SAP authorized user (bcm.sap) prepares the SAP loading workbook' using errcode = '42501'; end if;
    if v.kind = 'Tender estimate' then raise exception 'A Tender estimate is not loaded in SAP; load Rev 0 or a revision'; end if;
    if v.status not in ('Approved in ProTrackAI','Ready for SAP Loading') then raise exception 'Only a version approved in ProTrackAI is prepared for SAP (this one is %)', v.status; end if;
    select o.kind || ' ' || o.rev_no into w from bcm_versions o where o.project_id = v.project_id and o.id <> v.id and o.status = 'Ready for SAP Loading' limit 1;
    if w is not null then raise exception '% is waiting for its SAP loading confirmation; confirm or return it first', w; end if;
    select o.* into lc from bcm_versions o where o.project_id = v.project_id and o.id <> v.id and o.status = 'SAP Loading Confirmed' order by o.approved_at desc limit 1;
    if lc.id is not null and lc.approved_at > v.approved_at then raise exception 'A later version (% %) is already loaded in SAP', lc.kind, lc.rev_no; end if;
    c := pt_bcm_sap_content(v.id);
    if jsonb_array_length(c -> 'excluded') > 0 then
      raise exception 'Not every amount has a valid SAP WBS ID of the project: %', (select string_agg((x ->> 'sap') || ' (' || (x ->> 'reason') || ')', '; ') from jsonb_array_elements(c -> 'excluded') x); end if;
    if jsonb_typeof(c -> 'changes') = 'array' and jsonb_array_length(c -> 'changes') = 0 then raise exception 'Nothing changes from the version last loaded (% %)', c -> 'prev' ->> 'kind', c -> 'prev' ->> 'rev_no'; end if;
    update bcm_sap_exports set status = 'Returned', reason = 'Replaced by a new workbook', closed_by = u, closed_by_name = who, closed_at = now() where version_id = v.id and status = 'Generated';
    select coalesce(max(seq), 0) + 1 into sq from bcm_sap_exports where version_id = v.id;
    eid := 'SX-' || to_char(now(), 'YYMMDD') || '-' || substr(md5(random()::text || clock_timestamp()::text), 1, 6);
    insert into bcm_sap_exports (id, version_id, project_id, seq, content, check_md5, generated_by, generated_by_name) values (eid, v.id, v.project_id, sq, c, md5(c::text), u, who);
    update bcm_versions set status = 'Ready for SAP Loading', updated_at = now() where id = v.id;
    insert into bcm_version_hist (version_id, project_id, action, status, reason, by_user, by_name) values (v.id, v.project_id, 'SAP loading workbook ' || sq, 'Ready for SAP Loading', null, u, who);
    perform pt_bcm_log(u, who, rl, 'SAP loading workbook prepared', 'version', v.id, v.project_id, jsonb_build_object('export', eid, 'seq', sq, 'total', c ->> 'total', 'check', md5(c::text)));
    return jsonb_build_object('ok', true, 'id', eid, 'seq', sq, 'content', c, 'check', md5(c::text));
  end if;
  select * into e from bcm_sap_exports where id = p ->> 'export_id' for update;
  if e.id is null then raise exception 'Unknown SAP loading workbook'; end if;
  select * into v from bcm_versions where id = e.version_id for update;
  if not pt_bcm(u, v.project_id, 'bcm.sap') then raise exception 'Only a SAP authorized user (bcm.sap) records the SAP loading' using errcode = '42501'; end if;
  if e.status <> 'Generated' or v.status <> 'Ready for SAP Loading' then raise exception 'This workbook is % (the version is %)', lower(e.status), v.status; end if;
  if act = 'confirm' then
    if length(ref) < 3 or length(ref) > 60 then raise exception 'Give the SAP reference (3 to 60 characters), as SAP gave it'; end if;
    if coalesce(p ->> 'sap_date', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Give the date of the loading in SAP'; end if;
    sd := (p ->> 'sap_date')::date;
    if sd > current_date then raise exception 'The loading date % is in the future', sd; end if;
    if sd < e.generated_at::date then raise exception 'The loading date % is before the workbook was prepared (%)', sd, e.generated_at::date; end if;
    update bcm_sap_exports set status = 'Confirmed', sap_ref = ref, sap_date = sd, note = nullif(left(p ->> 'note', 500), ''), closed_by = u, closed_by_name = who, closed_at = now() where id = e.id;
    update bcm_versions set status = 'SAP Loading Confirmed', sap_ref = ref, updated_at = now() where id = v.id;
    insert into bcm_version_hist (version_id, project_id, action, status, reason, by_user, by_name) values (v.id, v.project_id, 'SAP loading confirmed: ' || ref || ' on ' || sd, 'SAP Loading Confirmed', nullif(left(p ->> 'note', 500), ''), u, who);
    perform pt_bcm_log(u, who, rl, 'SAP loading confirmed', 'version', v.id, v.project_id, jsonb_build_object('export', e.id, 'sap_ref', ref, 'sap_date', sd));
    return jsonb_build_object('ok', true, 'status', 'SAP Loading Confirmed');
  elsif act = 'return' then
    if length(rs) < 5 then raise exception 'Give the reason (at least 5 characters)'; end if;
    update bcm_sap_exports set status = 'Returned', reason = rs, closed_by = u, closed_by_name = who, closed_at = now() where id = e.id;
    update bcm_versions set status = 'Approved in ProTrackAI', updated_at = now() where id = v.id;
    insert into bcm_version_hist (version_id, project_id, action, status, reason, by_user, by_name) values (v.id, v.project_id, 'SAP loading workbook ' || e.seq || ' returned', 'Approved in ProTrackAI', rs, u, who);
    perform pt_bcm_log(u, who, rl, 'SAP loading workbook returned', 'version', v.id, v.project_id, jsonb_build_object('export', e.id, 'reason', rs));
    return jsonb_build_object('ok', true, 'status', 'Approved in ProTrackAI');
  end if;
  raise exception 'Unknown action %', act;
end $$;
create or replace function bcm_features() returns jsonb language sql stable as $$ select '{"version": 42, "stages": [1, 2, 3, 4], "sap_wbs": true}'::jsonb $$;

revoke execute on function pt_bcm_sap_bad(text, text), pt_bcm_sap_content(text), pt_bcm_sap_frozen() from public, anon, authenticated;
revoke execute on function bcm_sap_tpl(jsonb), bcm_sap_import(jsonb), bcm_sap_export(jsonb) from public, anon;
grant execute on function bcm_sap_tpl(jsonb), bcm_sap_import(jsonb), bcm_sap_export(jsonb), bcm_features() to authenticated;
