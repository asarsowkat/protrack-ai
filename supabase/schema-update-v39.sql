-- ProTrack schema update v39 (ProTrackAI v3.35): Budget & Cost Management, Automatic WBS Classification (stages 1 and 2).
-- 1. Rights: bcm.upload (costing engineer: upload tender files, extract, classify), bcm.review (confirm, correct and
--    override classifications), bcm.master (propose WBS master, rule, mapping and setting changes), bcm.approve (approve
--    them). The Head of Planning and Cost Control holds bcm.review, bcm.master and bcm.approve by position. Seeing the
--    module needs money.view (cost figures). The screen 'bcm' joins pt_screens() for Settings → Role access.
-- 2. Master data (bcm_master): WBS elements, classification rules, approved mappings and the settings, each with the
--    version in force (cur) and at most one change waiting for approval (pend). A change is proposed by bcm.master and
--    approved by bcm.approve, never by the person who proposed it. Every version is kept in bcm_master_hist, so a past
--    classification can be reproduced. The starting WBS master and rules (working definitions from the specification)
--    arrive as proposals of "System seed": nothing classifies to them until the company approves them.
-- 3. Tender files: bcm_batches (project, tender reference and revision, currency, project type), bcm_files (one per
--    workbook: name, SHA-256, the stored original in the private bucket bcm-tender, sheets, control total, processing
--    log; the same file is refused a second time in a project) and bcm_lines (every non-empty row extracted, with sheet,
--    row, cell references, the original texts and values and the formula). Lines never change and are never deleted:
--    reading a file again (for example after a header mapping) is a new run beside the old one.
-- 4. Classification (bcm_class, one row per line, history in bcm_class_hist): the engine's result is stored through
--    bcm_classify, which checks on the server that the destination is an approved, active, postable element, and that
--    Auto-Classified comes only from an approved mapping or rule pointing at that element, at or above the threshold,
--    below the value limit, for an element that does not need review, with no data problem and a cost type. A person's
--    decision (Confirmed, Rejected, Excluded with Reason) is never overwritten by the engine. bcm_review records
--    decisions: confirm, override (with a reason), reject, exclude (with a reason), correct (description or row kind,
--    the source unchanged) and undo (a new action). A bulk confirmation skips lines that need individual review.
-- 5. Nothing is written directly: every change goes through these functions, with an audit entry (bcm_audit).
-- Not in this update (stages 3 and 4): duplicate and backup analysis, reconciliation, split allocations, budget versions,
-- the cost summary, SAP report import and the SAP loading workbook. No SAP connection exists or is simulated.
-- Needs schema-update-v16.sql (rights). Additive. Safe to run twice. Undo: schema-rollback-v39.sql.

do $$ begin
  if to_regprocedure('public.pt_right(uuid,text,boolean)') is null then raise exception 'Run schema-update-v16.sql (STAGE-13-SETUP) first, then this update'; end if;
  if to_regprocedure('public.pt_is_head(uuid)') is null then raise exception 'Run schema-update-v7.sql first, then this update'; end if;
end $$;

-- ------------------------------------------------------------------ 1. rights and the screen
do $$
declare cur text[] := pt_rights(); src text; k text; scr text[] := pt_screens();
begin
  foreach k in array array['bcm.upload','bcm.review','bcm.master','bcm.approve'] loop
    if not (k = any(cur)) then cur := cur || k; end if; end loop;
  execute format('create or replace function pt_rights() returns text[] language sql immutable as $f$ select %L::text[] $f$', cur::text);
  select prosrc into src from pg_proc where proname = 'pt_right_default' and pronamespace = 'public'::regnamespace and pronargs = 2;
  if position('bcm.upload' in src) = 0 then
    if position('else false end' in src) = 0 then raise exception 'pt_right_default does not have the expected shape; add the bcm rights by hand'; end if;
    src := regexp_replace(src, 'else false end', E'when ''bcm.upload''              then base = ''costing''\n    when ''bcm.review''              then base = ''costing''\n    when ''bcm.master''              then false\n    when ''bcm.approve''             then false\n    else false end');
    execute format('create or replace function pt_right_default(base text, k text) returns boolean language sql immutable as $f$%s$f$', src);
  end if;
  if not ('bcm' = any(scr)) then
    execute format('create or replace function pt_screens() returns text[] language sql immutable as $f$ select %L::text[] $f$', (scr || 'bcm'::text)::text); end if;
end $$;
create or replace function pt_bcm(u uuid, pid text, k text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((pid is null or user_sees(u, pid)) and pt_right(u, 'money.view', false) and pt_right(u, k, k in ('bcm.review','bcm.master','bcm.approve') and pt_is_head(u)), false) $$;
-- who reads: cost figures (money.view) and the project in access; master data needs money.view only
create or replace function pt_bcm_reads(pid text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(auth.uid() is not null and pt_right(auth.uid(), 'money.view', false) and (pid is null or user_sees(auth.uid(), pid)), false) $$;

-- ------------------------------------------------------------------ 2. tables
create table if not exists bcm_master (
  id text primary key check (id ~ '^(W|R|M)-[A-Za-z0-9._/-]{1,40}$' or id = 'cfg'),
  ent text not null check (ent in ('wbs','rule','map','cfg')),
  ver int not null default 0, cur jsonb, pend jsonb, status text not null default 'Proposed' check (status in ('Proposed','Approved','Rejected')),
  updated_by uuid references profiles(id), updated_at timestamptz not null default now());
create index if not exists bcm_master_ent on bcm_master (ent);
create table if not exists bcm_master_hist (
  id bigserial primary key, ref text not null, ent text not null, action text not null, ver int, data jsonb,
  proposed_by text, proposed_by_name text, proposed_at timestamptz, decided_by uuid references profiles(id), decided_by_name text, decided_at timestamptz not null default now(), note text);
create index if not exists bcm_master_hist_ref on bcm_master_hist (ref);
create table if not exists bcm_batches (
  id text primary key, project_id text not null references projects(id) on delete cascade,
  tender_ref text not null check (length(tender_ref) between 1 and 80), tender_rev text not null default '0' check (length(tender_rev) between 1 and 20),
  currency text not null check (currency ~ '^[A-Z]{3}$'), ptype text, title text check (title is null or length(title) <= 200),
  status text not null default 'Open' check (status in ('Open','Withdrawn')), note text,
  created_by uuid references profiles(id), created_by_name text, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create index if not exists bcm_batches_proj on bcm_batches (project_id);
create table if not exists bcm_files (
  id text primary key, batch_id text not null references bcm_batches(id) on delete cascade, project_id text not null references projects(id) on delete cascade,
  name text not null check (length(name) between 1 and 255), sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'), size bigint not null check (size > 0 and size <= 26214400),
  kind text not null check (kind in ('xlsx','xls','xlsm')), path text not null,
  status text not null default 'Uploaded' check (status in ('Uploaded','Extracting','Extracted','Needs header mapping','Failed','Withdrawn')),
  run int not null default 0, sheets jsonb, control jsonb, mappings jsonb, log jsonb not null default '[]'::jsonb, fingerprint text, engine text,
  created_by uuid references profiles(id), created_by_name text, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create index if not exists bcm_files_batch on bcm_files (batch_id);
create unique index if not exists bcm_files_sha on bcm_files (project_id, sha256) where status <> 'Withdrawn';
create table if not exists bcm_lines (
  id text primary key, file_id text not null references bcm_files(id) on delete cascade, run int not null, batch_id text not null, project_id text not null,
  n int not null, sheet text not null, row_no int not null, kind text not null check (kind in ('item','section','subtotal','total','note')),
  code text, descr text check (descr is null or length(descr) <= 4000), qty numeric(24,6), unit text, unit_n text, rate numeric(24,6), amount numeric(24,6),
  amount_src text, formula text, cur text, refs jsonb, secs jsonb, extra jsonb, flags jsonb, hidden_sheet boolean not null default false,
  created_by uuid references profiles(id), created_at timestamptz not null default now(), unique (file_id, run, n));
create index if not exists bcm_lines_batch on bcm_lines (batch_id, run);
create table if not exists bcm_class (
  line_id text primary key references bcm_lines(id) on delete cascade, project_id text not null, batch_id text not null,
  status text not null check (status in ('Extracted','Normalized','Proposed','Auto-Classified','Pending Review','Confirmed','Rejected','Split Required','Unclassified','Duplicate Review','Excluded with Reason','Not a cost line')),
  wbs_id text, cost_type text, conf numeric(5,4), layer text, explain text, evidence jsonb, alt jsonb, flags jsonb, refs jsonb, norm text, corr jsonb, engine text,
  override boolean not null default false, reason text, decided_by uuid references profiles(id), decided_by_name text, decided_at timestamptz, seq int not null default 0, updated_at timestamptz not null default now());
create index if not exists bcm_class_batch on bcm_class (batch_id);
create table if not exists bcm_class_hist (
  id bigserial primary key, line_id text not null, project_id text not null, seq int not null, action text not null, status text, wbs_id text, cost_type text,
  prev jsonb, reason text, by_user uuid, by_name text, at_time timestamptz not null default now());
create index if not exists bcm_class_hist_line on bcm_class_hist (line_id);
create table if not exists bcm_audit (
  id bigserial primary key, at_time timestamptz not null default now(), by_user uuid, by_name text, by_role text, action text not null, ent text, ref text, project_id text, detail jsonb);
create index if not exists bcm_audit_proj on bcm_audit (project_id);

-- source lines and history never change; a project's deletion still removes them (cascade)
create or replace function pt_bcm_frozen() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' and tg_table_name = 'bcm_lines' and not exists (select 1 from bcm_files where id = old.file_id) then return old; end if;
  if tg_op = 'DELETE' and tg_table_name in ('bcm_class_hist','bcm_audit','bcm_master_hist') and current_setting('protrack.bcm_purge', true) = 'on' then return old; end if;
  raise exception 'Source lines, classification history, master-data history and the audit log are never changed or deleted';
end $$;
drop trigger if exists bcm_lines_frozen on bcm_lines;
create trigger bcm_lines_frozen before update or delete on bcm_lines for each row execute function pt_bcm_frozen();
drop trigger if exists bcm_class_hist_frozen on bcm_class_hist;
create trigger bcm_class_hist_frozen before update or delete on bcm_class_hist for each row execute function pt_bcm_frozen();
drop trigger if exists bcm_master_hist_frozen on bcm_master_hist;
create trigger bcm_master_hist_frozen before update or delete on bcm_master_hist for each row execute function pt_bcm_frozen();
drop trigger if exists bcm_audit_frozen on bcm_audit;
create trigger bcm_audit_frozen before update or delete on bcm_audit for each row execute function pt_bcm_frozen();

do $$
declare t text;
begin
  foreach t in array array['bcm_master','bcm_master_hist','bcm_batches','bcm_files','bcm_lines','bcm_class','bcm_class_hist','bcm_audit'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists %I on %I', t || '_read', t);
    execute format('revoke all on %I from anon', t);
    execute format('revoke insert, update, delete, truncate on %I from authenticated', t);
    execute format('grant select on %I to authenticated', t);
  end loop;
end $$;
create policy bcm_master_read on bcm_master for select using (pt_bcm_reads(null));
create policy bcm_master_hist_read on bcm_master_hist for select using (pt_bcm_reads(null));
create policy bcm_batches_read on bcm_batches for select using (pt_bcm_reads(project_id));
create policy bcm_files_read on bcm_files for select using (pt_bcm_reads(project_id));
create policy bcm_lines_read on bcm_lines for select using (pt_bcm_reads(project_id));
create policy bcm_class_read on bcm_class for select using (pt_bcm_reads(project_id));
create policy bcm_class_hist_read on bcm_class_hist for select using (pt_bcm_reads(project_id));
create policy bcm_audit_read on bcm_audit for select using (pt_bcm_reads(project_id) or (project_id is null and pt_bcm_reads(null)));

-- ------------------------------------------------------------------ 3. helpers
create or replace function pt_bcm_me() returns table (uid uuid, who text, rl text) language plpgsql stable security definer set search_path = public as $$
begin
  uid := auth.uid(); if uid is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  select name into who from profiles where id = uid and active; rl := role_of(uid);
  if rl is null or who is null then raise exception 'Sign in first' using errcode = '42501'; end if; return next;
end $$;
create or replace function pt_bcm_log(u uuid, who text, rl text, act text, ent text, ref text, pid text, d jsonb) returns void language sql security definer set search_path = public as $$
  insert into bcm_audit (by_user, by_name, by_role, action, ent, ref, project_id, detail) values (u, who, rl, act, ent, ref, pid, d) $$;
-- an element a line can be classified to: approved, active, postable, in force on the day
create or replace function pt_bcm_wbs_ok(wid text, d date default current_date) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select m.cur is not null and coalesce((m.cur ->> 'active')::boolean, true) and coalesce((m.cur ->> 'postable')::boolean, true)
    and (m.cur ->> 'eff_from' is null or (m.cur ->> 'eff_from')::date <= d) and (m.cur ->> 'eff_to' is null or (m.cur ->> 'eff_to')::date >= d)
    from bcm_master m where m.id = wid and m.ent = 'wbs'), false) $$;
create or replace function pt_bcm_cfg() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select cur from bcm_master where id = 'cfg'), '{"auto":0.95,"review":0.80,"values":[]}'::jsonb) $$;
-- the value from which a line needs individual review, for its currency and project type (null: no limit set)
create or replace function pt_bcm_limit(c text, pt text) returns numeric language sql stable security definer set search_path = public as $$
  select (v ->> 'amount')::numeric from jsonb_array_elements(coalesce(pt_bcm_cfg() -> 'values', '[]'::jsonb)) v
   where coalesce(v ->> 'cur', 'SAR') = coalesce(c, 'SAR') and (coalesce(v ->> 'ptype', '') = '' or v ->> 'ptype' = pt)
   order by (coalesce(v ->> 'ptype', '') <> '') desc limit 1 $$;
-- flags that need a person (data problems, conflicts, combined costs, mandatory or high-value lines, provider problems)
create or replace function pt_bcm_forcing(f jsonb) returns boolean language sql immutable as $$
  select coalesce(exists (select 1 from jsonb_array_elements_text(coalesce(f, '[]'::jsonb)) x
    where x ~ '^(Conflicting|Mandatory review|High value|Cost type not set|Combined cost|Close alternative|AI|Invalid AI|Missing description|Formula error|Formula result missing|Missing amount|Amount is not a number|Negative amount|Quantity × rate|Quantity is not|Rate is not)'), false) $$;
-- does a line need individual review whatever its flags say? (the server's own reading of its amount and destination)
create or replace function pt_bcm_must_review(lid text, wid text) returns text language plpgsql stable security definer set search_path = public as $$
declare l bcm_lines; b bcm_batches; lim numeric; m jsonb;
begin
  select * into l from bcm_lines where id = lid; select * into b from bcm_batches where id = l.batch_id;
  if pt_bcm_forcing(l.flags) then return 'the source line has a data problem to check'; end if;
  select cur into m from bcm_master where id = wid and ent = 'wbs';
  if m is not null and coalesce((m ->> 'mandatory_review')::boolean, false) then return (m ->> 'code') || ' always needs individual review'; end if;
  lim := pt_bcm_limit(coalesce(l.cur, b.currency), b.ptype);
  if lim is not null and l.amount is not null and abs(l.amount) >= lim then return 'high value (at or above ' || lim || ' ' || coalesce(l.cur, b.currency) || ')'; end if;
  return null;
end $$;

-- ------------------------------------------------------------------ 4. master data: propose, approve, reject
create or replace function pt_bcm_check(e text, d jsonb, self text) returns void language plpgsql stable security definer set search_path = public as $$
declare c text; par text; n int := 0; v jsonb;
begin
  if jsonb_typeof(d) <> 'object' then raise exception 'Nothing to save'; end if;
  if length(d::text) > 60000 then raise exception 'The record is too large'; end if;
  if e = 'wbs' then
    c := d ->> 'code';
    if c is null or c !~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,29}$' then raise exception 'A WBS code is 1 to 30 letters, digits, dots, dashes or slashes (got "%")', coalesce(c, ''); end if;
    if length(coalesce(d ->> 'desc', '')) not between 2 and 200 then raise exception 'Give the WBS element a description of 2 to 200 characters'; end if;
    if exists (select 1 from bcm_master m where m.ent = 'wbs' and m.id <> coalesce(self, '') and (lower(m.cur ->> 'code') = lower(c) or lower(m.pend -> 'data' ->> 'code') = lower(c))) then
      raise exception 'The WBS code % is already used by another element', c; end if;
    par := d ->> 'parent';
    if par is not null then
      if not exists (select 1 from bcm_master where id = par and ent = 'wbs') then raise exception 'The parent element % does not exist', par; end if;
      -- no element may become its own ancestor
      while par is not null and n < 20 loop
        if par = self then raise exception 'An element cannot sit under itself'; end if;
        select coalesce(cur ->> 'parent', pend -> 'data' ->> 'parent') into par from bcm_master where id = par; n := n + 1; end loop; end if;
    if d ->> 'eff_from' is not null and d ->> 'eff_to' is not null and (d ->> 'eff_to')::date < (d ->> 'eff_from')::date then raise exception 'Effective-to is before effective-from'; end if;
  elsif e in ('rule','map') then
    if not pt_bcm_wbs_ok(d ->> 'wbs_id') then raise exception 'Choose an approved, active, postable WBS element (got %)', coalesce(d ->> 'wbs_id', 'none'); end if;
    if d ->> 'cost_type' is not null and not (d ->> 'cost_type' = any(array['Material','Manpower','Equipment','Subcontract','Services','Overhead','Financing','Reserve','Other'])) then raise exception 'Unknown cost type %', d ->> 'cost_type'; end if;
    if e = 'rule' then
      if length(coalesce(d ->> 'name', '')) not between 2 and 120 then raise exception 'Give the rule a name'; end if;
      if coalesce(jsonb_array_length(d -> 'any'), 0) + coalesce(jsonb_array_length(d -> 'all'), 0) = 0 then raise exception 'A rule needs at least one phrase to match'; end if;
      if coalesce((d ->> 'strength')::numeric, 0.96) not between 0 and 1 then raise exception 'A rule strength is from 0 to 1'; end if;
      if coalesce((d ->> 'priority')::int, 0) not between 0 and 100 then raise exception 'A rule priority is from 0 to 100'; end if;
    else
      if not (d ->> 'scope' = any(array['project','ptype','global'])) then raise exception 'A mapping is for a project, a project type or global'; end if;
      if coalesce(d ->> 'key', d ->> 'item_code', '') = '' then raise exception 'A mapping needs a description or an item code'; end if;
      if d ->> 'scope' = 'project' and not exists (select 1 from projects where id = d ->> 'project_id') then raise exception 'Choose the project of a project mapping'; end if;
      if d ->> 'scope' = 'ptype' and coalesce(d ->> 'ptype', '') = '' then raise exception 'Choose the project type of a project-type mapping'; end if;
    end if;
  elsif e = 'cfg' then
    if coalesce((d ->> 'auto')::numeric, -1) not between 0.5 and 1 then raise exception 'The automatic threshold is from 50%% to 100%%'; end if;
    if coalesce((d ->> 'review')::numeric, -1) not between 0 and (d ->> 'auto')::numeric then raise exception 'The review threshold is from 0 to the automatic threshold'; end if;
    for v in select * from jsonb_array_elements(coalesce(d -> 'values', '[]'::jsonb)) loop
      if coalesce(v ->> 'cur', '') !~ '^[A-Z]{3}$' or (v ->> 'amount') is null or (v ->> 'amount')::numeric < 0 then raise exception 'Each value limit needs a currency and an amount of 0 or more'; end if; end loop;
  end if;
end $$;
create or replace function bcm_master_act(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; who text; rl text; act text := p ->> 'action'; e text := p ->> 'ent'; rid text := p ->> 'id'; d jsonb := p -> 'data'; m bcm_master; ids text[]; res jsonb := '[]'::jsonb; x text;
begin
  select * into u, who, rl from pt_bcm_me();
  if act = 'approve_many' then
    ids := array(select jsonb_array_elements_text(coalesce(p -> 'ids', '[]'::jsonb)));
    if array_length(ids, 1) > 300 then raise exception 'At most 300 at a time'; end if;
    foreach x in array coalesce(ids, '{}') loop
      begin perform bcm_master_act(jsonb_build_object('action', 'approve', 'id', x, 'note', p ->> 'note')); res := res || jsonb_build_object('id', x, 'ok', true);
      exception when others then res := res || jsonb_build_object('id', x, 'ok', false, 'error', sqlerrm); end; end loop;
    return jsonb_build_object('results', res);
  end if;
  if act = 'propose' then
    -- a reviewer may propose a mapping from a decision (approval is still someone else's); everything else needs bcm.master
    if not (pt_bcm(u, null, 'bcm.master') or (e = 'map' and pt_bcm(u, case when d ->> 'scope' = 'project' then d ->> 'project_id' end, 'bcm.review'))) then
      raise exception 'You cannot propose master-data changes (the bcm.master right)' using errcode = '42501'; end if;
    if not (e = any(array['wbs','rule','map','cfg'])) then raise exception 'Unknown record type %', e; end if;
    if e = 'cfg' then rid := 'cfg'; end if;
    if rid is null then rid := case e when 'wbs' then 'W-' when 'rule' then 'R-' else 'M-' end || substr(md5(random()::text || clock_timestamp()::text), 1, 8); end if;
    select * into m from bcm_master where id = rid;
    if m.id is not null and m.ent <> e then raise exception 'That record is not a %', e; end if;
    if e = 'map' and d ->> 'scope' = 'project' and not user_sees(u, d ->> 'project_id') then raise exception 'You do not have access to that project' using errcode = '42501'; end if;
    perform pt_bcm_check(e, d, rid);
    insert into bcm_master (id, ent, ver, cur, pend, status, updated_by) values (rid, e, 0, null, null, 'Proposed', u) on conflict (id) do nothing;
    update bcm_master set pend = jsonb_build_object('data', d, 'by', u::text, 'by_name', who, 'at', now(), 'note', left(p ->> 'note', 500)),
      status = case when cur is null then 'Proposed' else status end, updated_by = u, updated_at = now() where id = rid;
    insert into bcm_master_hist (ref, ent, action, ver, data, proposed_by, proposed_by_name, proposed_at, decided_by, decided_by_name, note) values (rid, e, 'Proposed', null, d, u::text, who, now(), u, who, left(p ->> 'note', 500));
    perform pt_bcm_log(u, who, rl, 'Change proposed', e, rid, case when e = 'map' then d ->> 'project_id' end, jsonb_build_object('note', p ->> 'note'));
    return jsonb_build_object('ok', true, 'id', rid);
  end if;
  select * into m from bcm_master where id = rid for update;
  if m.id is null then raise exception 'Unknown record %', rid; end if;
  if m.pend is null then raise exception 'Nothing is waiting for approval on %', rid; end if;
  if act = 'approve' then
    if not pt_bcm(u, null, 'bcm.approve') then raise exception 'You cannot approve master-data changes (the bcm.approve right)' using errcode = '42501'; end if;
    if m.pend ->> 'by' = u::text then raise exception 'You proposed this change, so someone else approves it'; end if;
    perform pt_bcm_check(m.ent, m.pend -> 'data', m.id);
    if m.ent = 'wbs' and exists (select 1 from bcm_master o where o.ent = 'wbs' and o.id <> m.id and lower(o.cur ->> 'code') = lower(m.pend -> 'data' ->> 'code')) then raise exception 'Another approved element already has the code %', m.pend -> 'data' ->> 'code'; end if;
    if m.ent = 'wbs' and m.pend -> 'data' ->> 'parent' is not null and not exists (select 1 from bcm_master where id = m.pend -> 'data' ->> 'parent' and cur is not null) then raise exception 'Approve the parent element % first', m.pend -> 'data' ->> 'parent'; end if;
    update bcm_master set cur = m.pend -> 'data', ver = m.ver + 1, pend = null, status = 'Approved', updated_by = u, updated_at = now() where id = m.id;
    insert into bcm_master_hist (ref, ent, action, ver, data, proposed_by, proposed_by_name, proposed_at, decided_by, decided_by_name, note)
      values (m.id, m.ent, 'Approved', m.ver + 1, m.pend -> 'data', m.pend ->> 'by', m.pend ->> 'by_name', (m.pend ->> 'at')::timestamptz, u, who, left(p ->> 'note', 500));
    perform pt_bcm_log(u, who, rl, 'Change approved', m.ent, m.id, case when m.ent = 'map' then m.pend -> 'data' ->> 'project_id' end, jsonb_build_object('version', m.ver + 1));
    return jsonb_build_object('ok', true, 'id', m.id, 'ver', m.ver + 1);
  elsif act = 'reject' then
    if not (pt_bcm(u, null, 'bcm.approve') or m.pend ->> 'by' = u::text) then raise exception 'Only an approver rejects a change (or its proposer withdraws it)' using errcode = '42501'; end if;
    if length(coalesce(p ->> 'note', '')) < 3 then raise exception 'Give the reason'; end if;
    update bcm_master set pend = null, status = case when cur is null then 'Rejected' else 'Approved' end, updated_by = u, updated_at = now() where id = m.id;
    insert into bcm_master_hist (ref, ent, action, ver, data, proposed_by, proposed_by_name, proposed_at, decided_by, decided_by_name, note)
      values (m.id, m.ent, case when m.pend ->> 'by' = u::text then 'Withdrawn' else 'Rejected' end, null, m.pend -> 'data', m.pend ->> 'by', m.pend ->> 'by_name', (m.pend ->> 'at')::timestamptz, u, who, left(p ->> 'note', 500));
    perform pt_bcm_log(u, who, rl, 'Change rejected', m.ent, m.id, null, jsonb_build_object('note', p ->> 'note'));
    return jsonb_build_object('ok', true, 'id', m.id);
  end if;
  raise exception 'Unknown action %', act;
end $$;

-- ------------------------------------------------------------------ 5. tender batches, files and extracted lines
create or replace function bcm_batch_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; who text; rl text; pid text := p ->> 'project_id'; bid text; b bcm_batches;
begin
  select * into u, who, rl from pt_bcm_me();
  if p ->> 'action' = 'withdraw' then
    select * into b from bcm_batches where id = p ->> 'id' for update;
    if b.id is null then raise exception 'Unknown batch'; end if;
    if not (pt_bcm(u, b.project_id, 'bcm.review') or (b.created_by = u and pt_bcm(u, b.project_id, 'bcm.upload'))) then raise exception 'Only its uploader or a reviewer withdraws a batch' using errcode = '42501'; end if;
    if length(coalesce(p ->> 'reason', '')) < 3 then raise exception 'Give the reason'; end if;
    update bcm_batches set status = 'Withdrawn', note = left(p ->> 'reason', 500), updated_at = now() where id = b.id;
    update bcm_files set status = 'Withdrawn', updated_at = now(), log = log || jsonb_build_array(jsonb_build_object('at', now(), 'by', who, 'msg', 'Withdrawn with the batch: ' || left(p ->> 'reason', 300)))
     where batch_id = b.id and status <> 'Withdrawn';
    perform pt_bcm_log(u, who, rl, 'Batch withdrawn', 'batch', b.id, b.project_id, jsonb_build_object('reason', p ->> 'reason'));
    return jsonb_build_object('ok', true, 'id', b.id);
  end if;
  if pid is null or not exists (select 1 from projects where id = pid) then raise exception 'Choose the project'; end if;
  if not pt_bcm(u, pid, 'bcm.upload') then raise exception 'You cannot upload tender files on this project (the bcm.upload right)' using errcode = '42501'; end if;
  if coalesce(p ->> 'currency', '') !~ '^[A-Z]{3}$' then raise exception 'Choose the reporting currency'; end if;
  if length(coalesce(p ->> 'tender_ref', '')) not between 1 and 80 then raise exception 'Give the tender reference'; end if;
  bid := 'TB-' || to_char(now(), 'YYMMDD') || '-' || substr(md5(random()::text || clock_timestamp()::text), 1, 6);
  insert into bcm_batches (id, project_id, tender_ref, tender_rev, currency, ptype, title, created_by, created_by_name)
    values (bid, pid, trim(p ->> 'tender_ref'), coalesce(nullif(trim(p ->> 'tender_rev'), ''), '0'), p ->> 'currency', nullif(p ->> 'ptype', ''), nullif(left(p ->> 'title', 200), ''), u, who);
  perform pt_bcm_log(u, who, rl, 'Batch created', 'batch', bid, pid, jsonb_build_object('tender', p ->> 'tender_ref', 'rev', p ->> 'tender_rev', 'currency', p ->> 'currency'));
  return jsonb_build_object('ok', true, 'id', bid);
end $$;
create or replace function bcm_file_add(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; who text; rl text; b bcm_batches; f bcm_files; fid text; k text := lower(p ->> 'kind'); sha text := lower(p ->> 'sha256'); pth text;
begin
  select * into u, who, rl from pt_bcm_me();
  select * into b from bcm_batches where id = p ->> 'batch_id';
  if b.id is null then raise exception 'Unknown batch'; end if;
  if b.status <> 'Open' then raise exception 'The batch is withdrawn'; end if;
  if not pt_bcm(u, b.project_id, 'bcm.upload') then raise exception 'You cannot upload tender files on this project' using errcode = '42501'; end if;
  select * into f from bcm_files where project_id = b.project_id and sha256 = sha and status <> 'Withdrawn';
  if f.id is not null then raise exception 'This file was already uploaded: % in batch % on %. The same file is not taken twice.', f.name, f.batch_id, to_char(f.created_at, 'YYYY-MM-DD HH24:MI'); end if;
  pth := 'bcm/' || b.project_id || '/' || b.id || '/' || sha || '.' || k;
  if p ->> 'path' is distinct from pth then raise exception 'The stored file path must be %', pth; end if;
  if not exists (select 1 from storage.objects where bucket_id = 'bcm-tender' and name = pth) then raise exception 'Upload the file to storage first'; end if;
  fid := 'TF-' || substr(md5(random()::text || clock_timestamp()::text), 1, 10);
  insert into bcm_files (id, batch_id, project_id, name, sha256, size, kind, path, created_by, created_by_name, log)
    values (fid, b.id, b.project_id, left(p ->> 'name', 255), sha, (p ->> 'size')::bigint, k, pth, u, who, jsonb_build_array(jsonb_build_object('at', now(), 'by', who, 'msg', 'Uploaded')));
  perform pt_bcm_log(u, who, rl, 'File uploaded', 'file', fid, b.project_id, jsonb_build_object('name', p ->> 'name', 'sha256', sha, 'size', p ->> 'size'));
  return jsonb_build_object('ok', true, 'id', fid);
end $$;
-- a run: start (status Extracting, run+1), lines (in chunks), done (count checked), or fail (the error kept)
create or replace function bcm_file_run(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; who text; rl text; f bcm_files; st text := p ->> 'step'; n int; L jsonb; x jsonb; i int := 0; ns text;
begin
  select * into u, who, rl from pt_bcm_me();
  select * into f from bcm_files where id = p ->> 'file_id' for update;
  if f.id is null then raise exception 'Unknown file'; end if;
  if f.status = 'Withdrawn' then raise exception 'The file is withdrawn'; end if;
  if not pt_bcm(u, f.project_id, 'bcm.upload') then raise exception 'You cannot process tender files on this project' using errcode = '42501'; end if;
  if st = 'start' then
    if exists (select 1 from bcm_class c join bcm_lines l on l.id = c.line_id where l.file_id = f.id and l.run = f.run and c.status in ('Confirmed','Rejected','Excluded with Reason'))
       and not coalesce((p ->> 'confirm_rerun')::boolean, false) then raise exception 'People have already decided lines of this file; reading it again starts new lines without those decisions. Confirm to go on.'; end if;
    update bcm_files set status = 'Extracting', run = run + 1, mappings = coalesce(p -> 'mappings', mappings), engine = left(p ->> 'engine', 120), updated_at = now(),
      log = log || jsonb_build_array(jsonb_build_object('at', now(), 'by', who, 'msg', 'Reading started (run ' || (f.run + 1) || ')')) where id = f.id;
    return jsonb_build_object('ok', true, 'run', f.run + 1);
  end if;
  if (p ->> 'run')::int is distinct from f.run then raise exception 'That reading is no longer the current one'; end if;
  if st = 'lines' then
    if f.status <> 'Extracting' then raise exception 'The file is not being read'; end if;
    L := p -> 'lines'; if jsonb_typeof(L) <> 'array' or jsonb_array_length(L) > 1000 then raise exception 'Send 1 to 1000 lines at a time'; end if;
    for x in select * from jsonb_array_elements(L) loop
      insert into bcm_lines (id, file_id, run, batch_id, project_id, n, sheet, row_no, kind, code, descr, qty, unit, unit_n, rate, amount, amount_src, formula, cur, refs, secs, extra, flags, hidden_sheet, created_by)
      values (f.id || ':' || f.run || ':' || (x ->> 'n'), f.id, f.run, f.batch_id, f.project_id, (x ->> 'n')::int, left(x ->> 'sheet', 120), (x ->> 'row')::int, x ->> 'kind', left(x ->> 'code', 80), x ->> 'desc',
        (x ->> 'qty')::numeric, left(x ->> 'unit', 40), left(x ->> 'unit_n', 40), (x ->> 'rate')::numeric, (x ->> 'amount')::numeric, x ->> 'amount_src', left(x ->> 'f', 2000), left(x ->> 'cur', 3),
        x -> 'refs', x -> 'secs', x -> 'extra', x -> 'flags', coalesce((x ->> 'hidden_sheet')::boolean, false), u);
      i := i + 1; end loop;
    return jsonb_build_object('ok', true, 'n', i);
  end if;
  if st = 'done' then
    if f.status <> 'Extracting' then raise exception 'The file is not being read'; end if;
    select count(*) into n from bcm_lines where file_id = f.id and run = f.run;
    if n <> (p ->> 'n')::int then raise exception 'The server holds % lines of this reading, not %; read the file again', n, p ->> 'n'; end if;
    ns := case when exists (select 1 from jsonb_array_elements(coalesce(p -> 'sheets', '[]'::jsonb)) s where s ->> 'status' = 'Needs header mapping') then 'Needs header mapping' else 'Extracted' end;
    update bcm_files set status = ns, sheets = p -> 'sheets', control = p -> 'control', fingerprint = left(p ->> 'fingerprint', 128), updated_at = now(),
      log = log || jsonb_build_array(jsonb_build_object('at', now(), 'by', who, 'msg', 'Read: ' || n || ' rows (run ' || f.run || ')' || case when ns <> 'Extracted' then '; a sheet needs a header mapping' else '' end)) where id = f.id;
    perform pt_bcm_log(u, who, rl, 'File read', 'file', f.id, f.project_id, jsonb_build_object('run', f.run, 'rows', n, 'status', ns));
    return jsonb_build_object('ok', true, 'status', ns, 'n', n);
  end if;
  if st = 'fail' then
    update bcm_files set status = 'Failed', updated_at = now(), log = log || jsonb_build_array(jsonb_build_object('at', now(), 'by', who, 'msg', 'Failed: ' || left(p ->> 'error', 400))) where id = f.id;
    perform pt_bcm_log(u, who, rl, 'File failed', 'file', f.id, f.project_id, jsonb_build_object('error', left(p ->> 'error', 400)));
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'Unknown step %', st;
end $$;

-- ------------------------------------------------------------------ 6. classification: the engine's results, and people's decisions
create or replace function bcm_classify(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; who text; rl text; x jsonb; l bcm_lines; f bcm_files; c bcm_class; st text; w text; cfg jsonb := pt_bcm_cfg(); ref jsonb; why text; n int := 0; sk int := 0;
begin
  select * into u, who, rl from pt_bcm_me();
  if jsonb_typeof(p -> 'lines') <> 'array' or jsonb_array_length(p -> 'lines') > 1000 then raise exception 'Send 1 to 1000 results at a time'; end if;
  for x in select * from jsonb_array_elements(p -> 'lines') loop
    select * into l from bcm_lines where id = x ->> 'id';
    if l.id is null then raise exception 'Unknown line %', x ->> 'id'; end if;
    select * into f from bcm_files where id = l.file_id;
    if f.run <> l.run or f.status = 'Withdrawn' then raise exception 'Line % is from an earlier reading or a withdrawn file', l.id; end if;
    if not (pt_bcm(u, l.project_id, 'bcm.upload') or pt_bcm(u, l.project_id, 'bcm.review')) then raise exception 'You cannot classify lines of this project' using errcode = '42501'; end if;
    select * into c from bcm_class where line_id = l.id;
    if c.status in ('Confirmed','Rejected','Excluded with Reason') then sk := sk + 1; continue; end if;   -- a person's decision stands
    st := x ->> 'status'; w := nullif(x ->> 'wbs_id', '');
    if not (st = any(array['Normalized','Proposed','Auto-Classified','Pending Review','Split Required','Unclassified','Duplicate Review','Not a cost line'])) then raise exception 'The engine cannot set the status %', st; end if;
    if coalesce(c.corr ->> 'kind', l.kind) <> 'item' and st <> 'Not a cost line' then raise exception 'Line % is a % row, not a cost line', l.id, coalesce(c.corr ->> 'kind', l.kind); end if;
    if coalesce(c.corr ->> 'kind', l.kind) = 'item' and st = 'Not a cost line' then raise exception 'Line % is a cost line', l.id; end if;
    if w is not null and not pt_bcm_wbs_ok(w) then raise exception 'Line %: % is not an approved, active, postable WBS element', l.id, w; end if;
    if st in ('Proposed','Auto-Classified','Pending Review') and w is null then raise exception 'Line %: a proposal needs its WBS element', l.id; end if;
    if x ->> 'cost_type' is not null and not (x ->> 'cost_type' = any(array['Material','Manpower','Equipment','Subcontract','Services','Overhead','Financing','Reserve','Other'])) then raise exception 'Unknown cost type %', x ->> 'cost_type'; end if;
    if st = 'Auto-Classified' then
      ref := coalesce(x -> 'refs', '{}'::jsonb);
      if x ->> 'layer' not in ('map','rule') then raise exception 'Line %: only an approved mapping or rule classifies automatically', l.id; end if;
      if not exists (select 1 from bcm_master m where m.id = coalesce(ref ->> 'map', ref ->> 'rule') and m.ent = case when ref ? 'map' then 'map' else 'rule' end and m.cur ->> 'wbs_id' = w
                     and coalesce((m.cur ->> 'active')::boolean, true)) then raise exception 'Line %: the approved mapping or rule it names does not lead to %', l.id, w; end if;
      if coalesce((x ->> 'conf')::numeric, 0) < (cfg ->> 'auto')::numeric then raise exception 'Line %: below the automatic threshold', l.id; end if;
      if x ->> 'cost_type' is null then raise exception 'Line %: no cost type', l.id; end if;
      if pt_bcm_forcing(x -> 'flags') then raise exception 'Line %: it carries a flag that needs a person', l.id; end if;
      why := pt_bcm_must_review(l.id, w); if why is not null then raise exception 'Line %: %, so it needs individual review', l.id, why; end if;
    end if;
    insert into bcm_class (line_id, project_id, batch_id, status, wbs_id, cost_type, conf, layer, explain, evidence, alt, flags, refs, norm, engine, seq, updated_at)
      values (l.id, l.project_id, l.batch_id, st, w, x ->> 'cost_type', (x ->> 'conf')::numeric, x ->> 'layer', left(x ->> 'explain', 1000), x -> 'evidence', x -> 'alt', x -> 'flags', x -> 'refs', left(x ->> 'norm', 4000), left(x ->> 'engine', 120), 1, now())
      on conflict (line_id) do update set status = excluded.status, wbs_id = excluded.wbs_id, cost_type = excluded.cost_type, conf = excluded.conf, layer = excluded.layer, explain = excluded.explain,
        evidence = excluded.evidence, alt = excluded.alt, flags = excluded.flags, refs = excluded.refs, norm = excluded.norm, engine = excluded.engine, seq = bcm_class.seq + 1, updated_at = now();
    insert into bcm_class_hist (line_id, project_id, seq, action, status, wbs_id, cost_type, prev, by_user, by_name)
      values (l.id, l.project_id, coalesce(c.seq, 0) + 1, 'Engine', st, w, x ->> 'cost_type', case when c.line_id is null then null else jsonb_build_object('status', c.status, 'wbs_id', c.wbs_id, 'cost_type', c.cost_type) end, u, who);
    n := n + 1;
  end loop;
  if n > 0 then perform pt_bcm_log(u, who, rl, 'Lines classified', 'class', null, l.project_id, jsonb_build_object('n', n, 'kept', sk, 'engine', p -> 'lines' -> 0 ->> 'engine')); end if;
  return jsonb_build_object('ok', true, 'n', n, 'kept', sk);
end $$;
create or replace function bcm_review(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; who text; rl text; act text := p ->> 'action'; lid text; c bcm_class; l bcm_lines; h bcm_class_hist; ids text[]; w text; ct text; why text; ns text; rs text := left(trim(coalesce(p ->> 'reason', '')), 1000);
        done int := 0; skipped jsonb := '[]'::jsonb; bulk boolean; ov boolean; prv jsonb;
begin
  select * into u, who, rl from pt_bcm_me();
  ids := array(select jsonb_array_elements_text(coalesce(p -> 'ids', '[]'::jsonb)));
  if coalesce(array_length(ids, 1), 0) = 0 or array_length(ids, 1) > 500 then raise exception 'Choose 1 to 500 lines'; end if;
  bulk := array_length(ids, 1) > 1;
  if act in ('override','reject','exclude','correct','undo') and length(rs) < 5 then raise exception 'Give the reason (at least 5 characters)'; end if;
  if act = 'override' then
    w := p ->> 'wbs_id'; ct := p ->> 'cost_type';
    if not pt_bcm_wbs_ok(w) then raise exception '% is not an approved, active, postable WBS element', coalesce(w, 'No element'); end if;
    if not (ct = any(array['Material','Manpower','Equipment','Subcontract','Services','Overhead','Financing','Reserve','Other'])) then raise exception 'Choose the cost type'; end if;
  end if;
  foreach lid in array ids loop
    select * into c from bcm_class where line_id = lid for update; select * into l from bcm_lines where id = lid;
    if l.id is null then raise exception 'Unknown line %', lid; end if;
    if not pt_bcm(u, l.project_id, 'bcm.review') then raise exception 'You cannot review lines of this project (the bcm.review right)' using errcode = '42501'; end if;
    if c.line_id is null then insert into bcm_class (line_id, project_id, batch_id, status) values (l.id, l.project_id, l.batch_id, case when l.kind = 'item' then 'Extracted' else 'Not a cost line' end) returning * into c; end if;
    prv := jsonb_build_object('status', c.status, 'wbs_id', c.wbs_id, 'cost_type', c.cost_type, 'override', c.override, 'reason', c.reason, 'corr', c.corr);
    ns := null; ov := false;
    if act = 'confirm' then
      if not (c.status = any(array['Proposed','Auto-Classified','Pending Review','Split Required'])) then skipped := skipped || jsonb_build_object('id', lid, 'why', 'not a proposal (' || c.status || ')'); continue; end if;
      if c.wbs_id is null or not pt_bcm_wbs_ok(c.wbs_id) then skipped := skipped || jsonb_build_object('id', lid, 'why', 'its WBS element is not approved and active'); continue; end if;
      if c.cost_type is null then skipped := skipped || jsonb_build_object('id', lid, 'why', 'no cost type: override it with one'); continue; end if;
      if c.status = 'Split Required' and length(rs) < 5 then skipped := skipped || jsonb_build_object('id', lid, 'why', 'a combined line is confirmed as one line only with a reason'); continue; end if;
      if bulk then
        if c.status not in ('Proposed','Auto-Classified') then skipped := skipped || jsonb_build_object('id', lid, 'why', c.status || ' lines are confirmed one by one'); continue; end if;
        if pt_bcm_forcing(c.flags) then skipped := skipped || jsonb_build_object('id', lid, 'why', 'it carries a flag that needs individual review'); continue; end if;
        why := pt_bcm_must_review(lid, c.wbs_id); if why is not null then skipped := skipped || jsonb_build_object('id', lid, 'why', why); continue; end if;
      end if;
      ns := 'Confirmed';
    elsif act = 'override' then
      if c.status = 'Not a cost line' then skipped := skipped || jsonb_build_object('id', lid, 'why', 'not a cost line'); continue; end if;
      why := case when bulk then pt_bcm_must_review(lid, w) end;
      if why is not null then
        -- a bulk reassignment of a line that needs individual review only proposes the new destination
        update bcm_class set status = 'Pending Review', wbs_id = w, cost_type = ct, layer = 'person', conf = null, override = true, reason = rs, explain = 'Reassigned in bulk by ' || who || '; ' || why || ', so it waits for individual confirmation.',
          decided_by = null, decided_by_name = null, decided_at = null, seq = seq + 1, updated_at = now() where line_id = lid;
        insert into bcm_class_hist (line_id, project_id, seq, action, status, wbs_id, cost_type, prev, reason, by_user, by_name) values (lid, l.project_id, c.seq + 1, 'Reassigned (needs confirmation)', 'Pending Review', w, ct, prv, rs, u, who);
        skipped := skipped || jsonb_build_object('id', lid, 'why', why || ': proposed, waits for individual confirmation'); done := done + 1; continue; end if;
      ns := 'Confirmed'; ov := true;
    elsif act = 'reject' then
      if not (c.status = any(array['Proposed','Auto-Classified','Pending Review','Split Required','Confirmed'])) then skipped := skipped || jsonb_build_object('id', lid, 'why', 'nothing to reject (' || c.status || ')'); continue; end if;
      ns := 'Rejected';
    elsif act = 'exclude' then
      if c.status = 'Not a cost line' then skipped := skipped || jsonb_build_object('id', lid, 'why', 'not a cost line'); continue; end if;
      ns := 'Excluded with Reason';
    elsif act = 'correct' then
      if p ->> 'kind' is not null and not (p ->> 'kind' = any(array['item','section','subtotal','total','note'])) then raise exception 'Unknown row kind'; end if;
      update bcm_class set corr = coalesce(corr, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object('desc', left(p ->> 'desc', 2000), 'kind', p ->> 'kind', 'by', who, 'at', now())),
        status = case when coalesce(p ->> 'kind', corr ->> 'kind', l.kind) = 'item' then 'Normalized' else 'Not a cost line' end,
        wbs_id = null, cost_type = null, conf = null, layer = null, override = false, reason = rs, decided_by = u, decided_by_name = who, decided_at = now(), seq = seq + 1, updated_at = now() where line_id = lid returning * into c;
      insert into bcm_class_hist (line_id, project_id, seq, action, status, prev, reason, by_user, by_name) values (lid, l.project_id, c.seq, 'Corrected (source unchanged)', c.status, prv, rs, u, who);
      done := done + 1; continue;
    elsif act = 'undo' then
      select * into h from bcm_class_hist where line_id = lid and action not in ('Engine','Undo') order by seq desc, id desc limit 1;
      if h.id is null or h.prev is null then skipped := skipped || jsonb_build_object('id', lid, 'why', 'no decision to undo'); continue; end if;
      update bcm_class set status = h.prev ->> 'status', wbs_id = h.prev ->> 'wbs_id', cost_type = h.prev ->> 'cost_type', override = coalesce((h.prev ->> 'override')::boolean, false), reason = h.prev ->> 'reason', corr = h.prev -> 'corr',
        decided_by = u, decided_by_name = who, decided_at = now(), seq = seq + 1, updated_at = now() where line_id = lid returning * into c;
      insert into bcm_class_hist (line_id, project_id, seq, action, status, wbs_id, cost_type, prev, reason, by_user, by_name) values (lid, l.project_id, c.seq, 'Undo', c.status, c.wbs_id, c.cost_type, prv, 'Undo of "' || h.action || '" of ' || to_char(h.at_time, 'YYYY-MM-DD HH24:MI') || ': ' || rs, u, who);
      done := done + 1; continue;
    else raise exception 'Unknown action %', act; end if;
    update bcm_class set status = ns, wbs_id = case when ov then w else wbs_id end, cost_type = case when ov then ct else cost_type end, layer = case when ov then 'person' else layer end,
      override = ov or (override and ns = 'Confirmed'), reason = nullif(rs, ''), decided_by = u, decided_by_name = who, decided_at = now(), seq = seq + 1, updated_at = now() where line_id = lid returning * into c;
    insert into bcm_class_hist (line_id, project_id, seq, action, status, wbs_id, cost_type, prev, reason, by_user, by_name)
      values (lid, l.project_id, c.seq, case act when 'confirm' then case when bulk then 'Confirmed (bulk)' else 'Confirmed' end when 'override' then 'Overridden' when 'reject' then 'Rejected' else 'Excluded' end, ns, c.wbs_id, c.cost_type, prv, nullif(rs, ''), u, who);
    done := done + 1;
  end loop;
  perform pt_bcm_log(u, who, rl, 'Review: ' || act, 'class', case when not bulk then ids[1] end, l.project_id, jsonb_build_object('n', done, 'skipped', jsonb_array_length(skipped), 'reason', nullif(rs, '')));
  return jsonb_build_object('ok', true, 'done', done, 'skipped', skipped);
end $$;
-- the lines of a batch, with exact amounts as text (numbers in JSON would lose decimals); read rights as the tables (row level security)
create or replace function bcm_lines_read(bid text, off int default 0, cur_only boolean default true) returns jsonb language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'file_id', l.file_id, 'run', l.run, 'n', l.n, 'sheet', l.sheet, 'row', l.row_no, 'kind', l.kind, 'code', l.code, 'desc', l.descr,
    'qty', l.qty::text, 'unit', l.unit, 'unit_n', l.unit_n, 'rate', l.rate::text, 'amount', l.amount::text, 'amount_src', l.amount_src, 'f', l.formula, 'cur', l.cur,
    'refs', l.refs, 'secs', l.secs, 'extra', l.extra, 'flags', l.flags, 'hidden_sheet', l.hidden_sheet) order by l.file_id, l.run, l.n), '[]'::jsonb)
  from (select x.* from bcm_lines x join bcm_files f on f.id = x.file_id where x.batch_id = bid and (not cur_only or x.run = f.run) order by x.file_id, x.run, x.n limit 2000 offset greatest(off, 0)) l $$;
create or replace function bcm_features() returns jsonb language sql stable as $$ select '{"version": 39, "stages": [1, 2]}'::jsonb $$;

revoke execute on function pt_bcm(uuid, text, text), pt_bcm_me(), pt_bcm_log(uuid, text, text, text, text, text, text, jsonb), pt_bcm_wbs_ok(text, date), pt_bcm_cfg(), pt_bcm_limit(text, text),
  pt_bcm_must_review(text, text), pt_bcm_check(text, jsonb, text), pt_bcm_frozen() from public, anon, authenticated;
revoke execute on function bcm_master_act(jsonb), bcm_batch_save(jsonb), bcm_file_add(jsonb), bcm_file_run(jsonb), bcm_classify(jsonb), bcm_review(jsonb), pt_bcm_reads(text), bcm_lines_read(text, int, boolean) from public, anon;
grant execute on function bcm_master_act(jsonb), bcm_batch_save(jsonb), bcm_file_add(jsonb), bcm_file_run(jsonb), bcm_classify(jsonb), bcm_review(jsonb), bcm_features(), pt_bcm_reads(text), bcm_lines_read(text, int, boolean) to authenticated;
grant execute on function pt_bcm_forcing(jsonb) to authenticated;

-- ------------------------------------------------------------------ 7. the tender files (private bucket)
insert into storage.buckets (id, name, public, file_size_limit) values ('bcm-tender', 'bcm-tender', false, 26214400)
on conflict (id) do update set public = false, file_size_limit = 26214400;
-- path: bcm/<project>/<batch>/<sha256>.<xlsx|xls|xlsm>
create or replace function pt_bcm_file_can(u uuid, path text, w boolean) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(split_part(path, '/', 1) = 'bcm' and case when w then pt_bcm(u, split_part(path, '/', 2), 'bcm.upload')
    and exists (select 1 from bcm_batches b where b.id = split_part(path, '/', 3) and b.project_id = split_part(path, '/', 2) and b.status = 'Open')
    else pt_bcm(u, split_part(path, '/', 2), 'money.view') end, false) $$;
drop policy if exists protrack_bcm_read on storage.objects;
create policy protrack_bcm_read on storage.objects for select to authenticated using (bucket_id = 'bcm-tender' and public.pt_bcm_file_can(auth.uid(), name, false));
drop policy if exists protrack_bcm_add on storage.objects;
create policy protrack_bcm_add on storage.objects for insert to authenticated
  with check (bucket_id = 'bcm-tender' and array_length(string_to_array(name, '/'), 1) = 4 and name ~ '/[0-9a-f]{64}\.(xlsx|xls|xlsm)$' and public.pt_bcm_file_can(auth.uid(), name, true));
revoke execute on function pt_bcm_file_can(uuid, text, boolean) from public, anon;
grant execute on function pt_bcm_file_can(uuid, text, boolean) to authenticated;

-- ------------------------------------------------------------------ 8. the starting master data: proposals of System seed, and the settings
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-SM', 'wbs', 0, null, '{"data":{"code":"SM","parent":null,"desc":"Site Management / Overhead","aliases":[],"keywords":[],"cost_category":"Overhead","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":false,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-SM1', 'wbs', 0, null, '{"data":{"code":"SM1","parent":"W-SM","desc":"Salaries","aliases":["salaries","wages","site staff","payroll"],"keywords":["salary","salaries","wages","staff","project manager","site engineer"],"cost_category":"Overhead","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-SM2', 'wbs', 0, null, '{"data":{"code":"SM2","parent":"W-SM","desc":"Vehicles","aliases":["vehicles","site vehicles","pick-up"],"keywords":["vehicle","vehicles","pickup","pick-up","car","bus","fuel"],"cost_category":"Overhead","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-SM3', 'wbs', 0, null, '{"data":{"code":"SM3","parent":"W-SM","desc":"Office Expenses","aliases":["office expenses","stationery","consumables"],"keywords":["office","stationery","consumables","printing","internet","telephone","utilities"],"cost_category":"Overhead","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-SM4', 'wbs', 0, null, '{"data":{"code":"SM4","parent":"W-SM","desc":"Villa / Accommodation","aliases":["accommodation","villa rent","staff housing","camp"],"keywords":["villa","accommodation","camp","housing","rent"],"cost_category":"Overhead","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-SM5', 'wbs', 0, null, '{"data":{"code":"SM5","parent":"W-SM","desc":"Recruitment","aliases":["recruitment fees","visa","hiring"],"keywords":["recruitment","visa","iqama","hiring","agency"],"cost_category":"Overhead","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-SM6', 'wbs', 0, null, '{"data":{"code":"SM6","parent":"W-SM","desc":"Safety","aliases":["safety","HSE","PPE"],"keywords":["safety","hse","ppe","first aid","fire extinguisher"],"cost_category":"Overhead","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-SM7', 'wbs', 0, null, '{"data":{"code":"SM7","parent":"W-SM","desc":"Maintenance","aliases":["maintenance","repairs"],"keywords":["maintenance","repair","repairs"],"cost_category":"Overhead","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-SM8', 'wbs', 0, null, '{"data":{"code":"SM8","parent":"W-SM","desc":"Insurance","aliases":["insurance","CAR policy"],"keywords":["insurance","policy","all risk","car"],"cost_category":"Overhead","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-SM9', 'wbs', 0, null, '{"data":{"code":"SM9","parent":"W-SM","desc":"Site Office Establishment and Warranty-Period Expenses","aliases":["site establishment","site office set-up","warranty period"],"keywords":["establishment","porta cabin","site office","warranty","defects liability"],"cost_category":"Overhead","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-DES', 'wbs', 0, null, '{"data":{"code":"DES","parent":null,"desc":"Design","aliases":[],"keywords":[],"cost_category":"Services","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":false,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-DES-01', 'wbs', 0, null, '{"data":{"code":"DES-01","parent":"W-DES","desc":"Design packages by discipline","aliases":["design","design package"],"keywords":["design","package","discipline","drawings","calculations"],"cost_category":"Services","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-DES-02', 'wbs', 0, null, '{"data":{"code":"DES-02","parent":"W-DES","desc":"Engineering hours","aliases":["engineering hours","design hours"],"keywords":["engineering","hours","man-hours","manhours"],"cost_category":"Services","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-DES-03', 'wbs', 0, null, '{"data":{"code":"DES-03","parent":"W-DES","desc":"Design subcontract","aliases":["design subcontract","design consultant"],"keywords":["design","subcontract","consultant","consultancy"],"cost_category":"Subcontract","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-DES-09', 'wbs', 0, null, '{"data":{"code":"DES-09","parent":"W-DES","desc":"Other design costs","aliases":[],"keywords":["design","other"],"cost_category":"Services","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-ELM', 'wbs', 0, null, '{"data":{"code":"ELM","parent":null,"desc":"Electrical Material","aliases":[],"keywords":[],"cost_category":"Material","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":false,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-ELM-01', 'wbs', 0, null, '{"data":{"code":"ELM-01","parent":"W-ELM","desc":"Power cables","aliases":["power cable","XLPE cable","cables"],"keywords":["cable","cables","xlpe","power cable","conductor"],"cost_category":"Material","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-ELM-02', 'wbs', 0, null, '{"data":{"code":"ELM-02","parent":"W-ELM","desc":"Transformers","aliases":["transformer","power transformer"],"keywords":["transformer","transformers","mva"],"cost_category":"Material","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-ELM-03', 'wbs', 0, null, '{"data":{"code":"ELM-03","parent":"W-ELM","desc":"Switchgear","aliases":["switchgear","GIS","circuit breaker"],"keywords":["switchgear","gis","breaker","rmu","bay"],"cost_category":"Material","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-ELM-04', 'wbs', 0, null, '{"data":{"code":"ELM-04","parent":"W-ELM","desc":"Cable accessories","aliases":["termination kits","joints","glands"],"keywords":["termination","kit","kits","joint","jointing","glands","lugs","accessories"],"cost_category":"Material","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-ELM-05', 'wbs', 0, null, '{"data":{"code":"ELM-05","parent":"W-ELM","desc":"Electrical panels","aliases":["panels","distribution boards"],"keywords":["panel","panels","board","relay panel","control panel"],"cost_category":"Material","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-ELM-09', 'wbs', 0, null, '{"data":{"code":"ELM-09","parent":"W-ELM","desc":"Other electrical material","aliases":[],"keywords":["electrical","material","earthing","ladder","tray","conduit"],"cost_category":"Material","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-ELP', 'wbs', 0, null, '{"data":{"code":"ELP","parent":null,"desc":"Electrical Manpower","aliases":[],"keywords":[],"cost_category":"Manpower","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":false,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-ELP-01', 'wbs', 0, null, '{"data":{"code":"ELP-01","parent":"W-ELP","desc":"Cable laying manpower","aliases":["cable pulling","cable laying crew"],"keywords":["cable","laying","pulling","crew","technicians"],"cost_category":"Manpower","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-ELP-02', 'wbs', 0, null, '{"data":{"code":"ELP-02","parent":"W-ELP","desc":"Installation manpower","aliases":["installation crew","erection"],"keywords":["installation","erection","electricians","crew"],"cost_category":"Manpower","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-ELP-03', 'wbs', 0, null, '{"data":{"code":"ELP-03","parent":"W-ELP","desc":"Termination manpower","aliases":["cable jointing","termination crew"],"keywords":["termination","jointing","jointers","crew"],"cost_category":"Manpower","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-ELP-04', 'wbs', 0, null, '{"data":{"code":"ELP-04","parent":"W-ELP","desc":"Testing manpower","aliases":["testing technicians"],"keywords":["testing","technicians","engineers"],"cost_category":"Manpower","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-ELE', 'wbs', 0, null, '{"data":{"code":"ELE","parent":null,"desc":"Electrical Equipment","aliases":["electrical equipment"],"keywords":["equipment","tools","cable drum","winch"],"cost_category":"Equipment","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-TC', 'wbs', 0, null, '{"data":{"code":"TC","parent":null,"desc":"Testing & Commissioning","aliases":[],"keywords":[],"cost_category":"Services","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":false,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-TC-01', 'wbs', 0, null, '{"data":{"code":"TC-01","parent":"W-TC","desc":"Commissioning packages","aliases":["commissioning"],"keywords":["commissioning","energization","package"],"cost_category":"Services","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-TC-02', 'wbs', 0, null, '{"data":{"code":"TC-02","parent":"W-TC","desc":"Testing activities","aliases":["testing"],"keywords":["testing","tests","test"],"cost_category":"Services","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-TC-03', 'wbs', 0, null, '{"data":{"code":"TC-03","parent":"W-TC","desc":"Specialist services","aliases":["specialist services","relay testing"],"keywords":["specialist","services","relay testing","third party"],"cost_category":"Services","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-TC-04', 'wbs', 0, null, '{"data":{"code":"TC-04","parent":"W-TC","desc":"Testing & commissioning labour","aliases":["T&C labour"],"keywords":["labour","technicians","commissioning engineers"],"cost_category":"Manpower","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-TC-05', 'wbs', 0, null, '{"data":{"code":"TC-05","parent":"W-TC","desc":"Testing equipment","aliases":["testing equipment","test sets"],"keywords":["testing equipment","injection","test set","instrument"],"cost_category":"Equipment","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-CIV', 'wbs', 0, null, '{"data":{"code":"CIV","parent":null,"desc":"Civil Works","aliases":[],"keywords":[],"cost_category":"Subcontract","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":false,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-CIV-01', 'wbs', 0, null, '{"data":{"code":"CIV-01","parent":"W-CIV","desc":"Site preparation","aliases":["site preparation","clearing","grading"],"keywords":["site preparation","clearing","grading","levelling"],"cost_category":"Subcontract","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-CIV-02', 'wbs', 0, null, '{"data":{"code":"CIV-02","parent":"W-CIV","desc":"Investigation","aliases":["soil investigation","survey"],"keywords":["investigation","geotechnical","boreholes","survey"],"cost_category":"Services","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-CIV-03', 'wbs', 0, null, '{"data":{"code":"CIV-03","parent":"W-CIV","desc":"Excavation","aliases":["excavation","trenching"],"keywords":["excavation","trench","trenching","earthwork"],"cost_category":"Subcontract","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-CIV-04', 'wbs', 0, null, '{"data":{"code":"CIV-04","parent":"W-CIV","desc":"Backfill","aliases":["backfill","backfilling","compaction"],"keywords":["backfill","backfilling","compaction","selected material"],"cost_category":"Subcontract","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-CIV-05', 'wbs', 0, null, '{"data":{"code":"CIV-05","parent":"W-CIV","desc":"Concrete","aliases":["concrete","RCC","PCC"],"keywords":["concrete","rcc","pcc","blinding","foundations"],"cost_category":"Material","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-CIV-06', 'wbs', 0, null, '{"data":{"code":"CIV-06","parent":"W-CIV","desc":"Reinforcement / Rebar","aliases":["rebar","reinforcement steel"],"keywords":["rebar","reinforcement","steel","bars"],"cost_category":"Material","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-CIV-07', 'wbs', 0, null, '{"data":{"code":"CIV-07","parent":"W-CIV","desc":"Civil material","aliases":["civil material","cement","aggregate"],"keywords":["cement","aggregate","sand","blocks","formwork","waterproofing"],"cost_category":"Material","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-CIV-08', 'wbs', 0, null, '{"data":{"code":"CIV-08","parent":"W-CIV","desc":"Civil manpower by work area","aliases":["civil manpower","masons","carpenters"],"keywords":["manpower","crew","masons","carpenters","steel fixers","labour"],"cost_category":"Manpower","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-CIV-09', 'wbs', 0, null, '{"data":{"code":"CIV-09","parent":"W-CIV","desc":"Civil equipment","aliases":["civil equipment","crane","excavator"],"keywords":["crane","excavator","loader","roller","compactor","equipment"],"cost_category":"Equipment","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-CIV-10', 'wbs', 0, null, '{"data":{"code":"CIV-10","parent":"W-CIV","desc":"Other civil activities","aliases":[],"keywords":["civil","other","drainage","roads","fencing"],"cost_category":"Subcontract","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-OTH', 'wbs', 0, null, '{"data":{"code":"OTH","parent":null,"desc":"Other approved categories","aliases":[],"keywords":[],"cost_category":"Other","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":false,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-SAU', 'wbs', 0, null, '{"data":{"code":"SAU","parent":"W-OTH","desc":"Saudization","aliases":["saudization","nitaqat"],"keywords":["saudization","nitaqat","levy"],"cost_category":"Overhead","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":false},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-FIN', 'wbs', 0, null, '{"data":{"code":"FIN","parent":"W-OTH","desc":"Financing","aliases":["financing","finance cost","bank guarantee"],"keywords":["financing","finance","interest","bank","guarantee","bond","letter of credit"],"cost_category":"Financing","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-CON', 'wbs', 0, null, '{"data":{"code":"CON","parent":"W-OTH","desc":"Contingency","aliases":["contingency"],"keywords":["contingency","contingencies"],"cost_category":"Reserve","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('W-MR', 'wbs', 0, null, '{"data":{"code":"MR","parent":"W-OTH","desc":"Management Reserve","aliases":["management reserve"],"keywords":["management reserve","reserve"],"cost_category":"Reserve","ptypes":[],"sap_wbs":null,"eff_from":null,"eff_to":null,"active":true,"postable":true,"mandatory_review":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Working definition from the specification: confirm against the company WBS before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-001', 'rule', 0, null, '{"data":{"name":"Rebar supply","wbs_id":"W-CIV-06","cost_type":"Material","priority":10,"strength":0.96,"all":[],"any":["rebar","reinforcement steel","reinforcement bar","steel bars","deformed bars"],"none":["fixing","fixers","fixer","crew","labour","manpower"],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-002', 'rule', 0, null, '{"data":{"name":"Rebar fixing crew","wbs_id":"W-CIV-08","cost_type":"Manpower","priority":20,"strength":0.96,"all":["rebar|steel|reinforcement","fixing|fixers|fixer|crew|labour|manpower"],"any":[],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-003', 'rule', 0, null, '{"data":{"name":"Civil manpower","wbs_id":"W-CIV-08","cost_type":"Manpower","priority":18,"strength":0.96,"all":["civil|mason|masons|carpenter|carpenters|steel fixers","manpower|crew|labour|gang|masons|carpenters"],"any":[],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-004', 'rule', 0, null, '{"data":{"name":"Excavation","wbs_id":"W-CIV-03","cost_type":null,"priority":10,"strength":0.96,"all":[],"any":["excavation","excavate","trenching","earthwork"],"none":["backfill","backfilling"],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-005', 'rule', 0, null, '{"data":{"name":"Backfill","wbs_id":"W-CIV-04","cost_type":null,"priority":12,"strength":0.96,"all":[],"any":["backfill","backfilling","back filling","compaction"],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-006', 'rule', 0, null, '{"data":{"name":"Concrete","wbs_id":"W-CIV-05","cost_type":"Material","priority":10,"strength":0.96,"all":[],"any":["concrete","reinforced concrete","plain concrete","blinding"],"none":["rebar","reinforcement steel","formwork"],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-007', 'rule', 0, null, '{"data":{"name":"Site preparation","wbs_id":"W-CIV-01","cost_type":null,"priority":10,"strength":0.96,"all":[],"any":["site preparation","site clearing","clearing and grubbing","grading","levelling"],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-008', 'rule', 0, null, '{"data":{"name":"Investigation","wbs_id":"W-CIV-02","cost_type":"Services","priority":10,"strength":0.96,"all":[],"any":["soil investigation","geotechnical","boreholes","topographic survey"],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-009', 'rule', 0, null, '{"data":{"name":"Civil material","wbs_id":"W-CIV-07","cost_type":"Material","priority":8,"strength":0.96,"all":[],"any":["cement","aggregate","aggregates","blocks","bricks","formwork","waterproofing"],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-010', 'rule', 0, null, '{"data":{"name":"Civil equipment","wbs_id":"W-CIV-09","cost_type":"Equipment","priority":8,"strength":0.96,"all":[],"any":["crane","excavator","loader","roller","dump truck","compactor","civil equipment"],"none":["testing"],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-011', 'rule', 0, null, '{"data":{"name":"Transformer supply","wbs_id":"W-ELM-02","cost_type":"Material","priority":10,"strength":0.96,"all":["transformer|transformers","supply|procurement|purchase"],"any":[],"none":["crew","manpower","labour","technicians","erection","testing","commissioning","foundation"],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-012', 'rule', 0, null, '{"data":{"name":"Power cables","wbs_id":"W-ELM-01","cost_type":"Material","priority":5,"strength":0.96,"all":["cable|cables"],"any":[],"none":["termination","jointing","pulling","laying","ladder","tray","manpower","crew","technicians","labour","accessories","kits","kit","trench","excavation","glands","lugs","testing","drum"],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-013', 'rule', 0, null, '{"data":{"name":"Cable accessories","wbs_id":"W-ELM-04","cost_type":"Material","priority":10,"strength":0.96,"all":[],"any":["termination kit","termination kits","cable termination","joint kit","jointing kit","cable glands","lugs","cable accessories","cable joints"],"none":["manpower","crew","technicians","labour"],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-014', 'rule', 0, null, '{"data":{"name":"Switchgear","wbs_id":"W-ELM-03","cost_type":"Material","priority":10,"strength":0.96,"all":[],"any":["switchgear","gis","ring main unit","circuit breaker"],"none":["manpower","crew","testing","commissioning","transport","labour"],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-015', 'rule', 0, null, '{"data":{"name":"Electrical panels","wbs_id":"W-ELM-05","cost_type":"Material","priority":11,"strength":0.96,"all":[],"any":["panel","panels","distribution board","control panel","relay panel"],"none":["manpower","testing","crew"],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-016', 'rule', 0, null, '{"data":{"name":"Cable laying manpower","wbs_id":"W-ELP-01","cost_type":"Manpower","priority":20,"strength":0.96,"all":["cable|cables","pulling|laying|pullers"],"any":[],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-017', 'rule', 0, null, '{"data":{"name":"Termination manpower","wbs_id":"W-ELP-03","cost_type":"Manpower","priority":20,"strength":0.96,"all":["termination|jointing|jointers","technicians|crew|manpower|labour|jointers|team"],"any":[],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-018', 'rule', 0, null, '{"data":{"name":"Installation manpower","wbs_id":"W-ELP-02","cost_type":"Manpower","priority":19,"strength":0.96,"all":["installation|erection","technicians|electricians|crew|manpower|labour|fitters|team"],"any":[],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-019', 'rule', 0, null, '{"data":{"name":"Testing manpower","wbs_id":"W-ELP-04","cost_type":"Manpower","priority":19,"strength":0.96,"all":["testing","technicians|manpower|crew|labour"],"any":[],"none":["commissioning","equipment"],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-020', 'rule', 0, null, '{"data":{"name":"Commissioning","wbs_id":"W-TC-01","cost_type":"Services","priority":10,"strength":0.96,"all":[],"any":["commissioning"],"none":["manpower","labour"],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-021', 'rule', 0, null, '{"data":{"name":"Specialist testing services","wbs_id":"W-TC-03","cost_type":"Services","priority":12,"strength":0.96,"all":[],"any":["relay testing","specialist services","testing services","third party inspection"],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-022', 'rule', 0, null, '{"data":{"name":"Testing equipment","wbs_id":"W-TC-05","cost_type":"Equipment","priority":15,"strength":0.96,"all":["testing|test|injection","equipment|instrument|rental|hire|test set"],"any":[],"none":["manpower","technicians","labour"],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-023', 'rule', 0, null, '{"data":{"name":"Salaries","wbs_id":"W-SM1","cost_type":"Overhead","priority":15,"strength":0.96,"all":[],"any":["salary","salaries","wages","payroll","site staff","project manager","site engineer","safety officer"],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-024', 'rule', 0, null, '{"data":{"name":"Vehicles","wbs_id":"W-SM2","cost_type":"Overhead","priority":10,"strength":0.96,"all":[],"any":["vehicle","vehicles","pick up","pickup","car rental","bus rental"],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-025', 'rule', 0, null, '{"data":{"name":"Office expenses","wbs_id":"W-SM3","cost_type":"Overhead","priority":10,"strength":0.96,"all":[],"any":["office expenses","stationery","consumables","printing","office supplies","telephone","internet"],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-026', 'rule', 0, null, '{"data":{"name":"Accommodation","wbs_id":"W-SM4","cost_type":"Overhead","priority":10,"strength":0.96,"all":[],"any":["villa","accommodation","camp","housing"],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-027', 'rule', 0, null, '{"data":{"name":"Recruitment","wbs_id":"W-SM5","cost_type":"Overhead","priority":10,"strength":0.96,"all":[],"any":["recruitment","visa","iqama","hiring fees"],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-028', 'rule', 0, null, '{"data":{"name":"Safety","wbs_id":"W-SM6","cost_type":"Overhead","priority":10,"strength":0.96,"all":[],"any":["safety","ppe","hse","first aid"],"none":["testing"],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-029', 'rule', 0, null, '{"data":{"name":"Maintenance","wbs_id":"W-SM7","cost_type":"Overhead","priority":10,"strength":0.96,"all":[],"any":["maintenance","repairs"],"none":["warranty"],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-030', 'rule', 0, null, '{"data":{"name":"Insurance","wbs_id":"W-SM8","cost_type":"Overhead","priority":10,"strength":0.96,"all":[],"any":["insurance","car policy","all risk"],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-031', 'rule', 0, null, '{"data":{"name":"Site establishment and warranty","wbs_id":"W-SM9","cost_type":"Overhead","priority":15,"strength":0.96,"all":[],"any":["site office establishment","site establishment","porta cabin","portacabin","warranty period","defects liability"],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-032', 'rule', 0, null, '{"data":{"name":"Design packages","wbs_id":"W-DES-01","cost_type":"Services","priority":10,"strength":0.96,"all":[],"any":["design","design package"],"none":["subcontract","consultant","hours"],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-033', 'rule', 0, null, '{"data":{"name":"Engineering hours","wbs_id":"W-DES-02","cost_type":"Services","priority":15,"strength":0.96,"all":[],"any":["engineering hours","design hours","engineering man hours","engineering manhours"],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-034', 'rule', 0, null, '{"data":{"name":"Design subcontract","wbs_id":"W-DES-03","cost_type":"Subcontract","priority":15,"strength":0.96,"all":["design","subcontract|consultant|consultancy"],"any":[],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-035', 'rule', 0, null, '{"data":{"name":"Saudization","wbs_id":"W-SAU","cost_type":"Overhead","priority":10,"strength":0.96,"all":[],"any":["saudization","nitaqat"],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-036', 'rule', 0, null, '{"data":{"name":"Financing","wbs_id":"W-FIN","cost_type":"Financing","priority":10,"strength":0.96,"all":[],"any":["financing","finance cost","interest","bank charges","bank guarantee","performance bond","letter of credit"],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-037', 'rule', 0, null, '{"data":{"name":"Contingency","wbs_id":"W-CON","cost_type":"Reserve","priority":10,"strength":0.96,"all":[],"any":["contingency","contingencies"],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('R-038', 'rule', 0, null, '{"data":{"name":"Management reserve","wbs_id":"W-MR","cost_type":"Reserve","priority":12,"strength":0.96,"all":[],"any":["management reserve"],"none":[],"section":[],"units":[],"ptypes":[],"eff_from":null,"eff_to":null,"active":true},"by":"system","by_name":"System seed (working definition)","at":null,"note":"Default rule from the specification examples: check it before approving."}'::jsonb, 'Proposed') on conflict (id) do nothing;
insert into bcm_master (id, ent, ver, cur, pend, status) values ('cfg', 'cfg', 1, '{"auto":0.95,"review":0.8,"values":[{"cur":"SAR","ptype":"","amount":"1000000"},{"cur":"USD","ptype":"","amount":"270000"},{"cur":"EUR","ptype":"","amount":"250000"}],"abbr":[],"spell":[],"tolerance":{"abs":"1","pct":"0.01"}}'::jsonb, null, 'Approved') on conflict (id) do nothing;
insert into bcm_master_hist (ref, ent, action, ver, data, proposed_by, proposed_by_name, decided_by_name, note) select 'cfg', 'cfg', 'Approved', 1, cur, 'system', 'System seed', 'System seed', 'Initial thresholds from the specification (95% automatic, 80% review; value limits SAR 1,000,000, USD 270,000, EUR 250,000)' from bcm_master m where m.id = 'cfg' and not exists (select 1 from bcm_master_hist h where h.ref = 'cfg');

