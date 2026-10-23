-- ProTrack schema update v41 (ProTrackAI v3.37): Budget & Cost Management, stage 3 (financial controls).
-- 1. Rights: bcm.budget (prepare, import and submit budget versions; costing engineers) and bcm.budget.approve (approve
--    them; the Head of Planning and Cost Control by position). Never one's own.
-- 2. Sheet roles (bcm_roles): each sheet of a reading is an authoritative summary, a detailed cost breakdown, a
--    supporting backup, an alternative quotation, a previous revision or reference only. ProTrack proposes, a reviewer
--    confirms. Only summary and breakdown lines count; the others are kept and shown, never added.
-- 3. Duplicate and backup candidates (bcm_dups): exact duplicates, the same figures with a similar description,
--    similar descriptions with different specifications, a summary line repeated in a backup, repeated totals.
--    Proposed by ProTrack, decided by a reviewer:
--    - valid independent cost, duplicate of another line, supporting backup only (count the summary line or the backup
--      lines), superseded revision, or excluded with justification;
--    - the server works out which lines stop counting; nothing is deleted.
-- 4. Split allocations (bcm_alloc) of a combined line: rows of WBS, cost type and amount that add up to the line within
--    the tolerance, with method and evidence; approved by a reviewer other than the proposer.
-- 5. Reconciliation: pt_bcm_eval and bcm_totals work out, on the server, which lines count and where. A variance is
--    explained with a reason (bcm_recon_notes, append only), never adjusted.
-- 6. Budget versions (bcm_versions, bcm_version_lines): Tender estimate, Rev 0, Revised Rev 0, Approved revision.
--    - Made from a classified tender batch (the server computes the figures and refuses a batch that is not ready) or
--      imported for an existing project with its actual SAP WBS IDs.
--    - Draft → Submitted → Under Review → Approved in ProTrackAI (or Rejected, Cancelled); reviewer and approver are not
--      the preparer or the submitter.
--    - Lines never change after the draft; a correction is a new version.
--    - "Approved in ProTrackAI" is not "loaded in SAP": SAP loading comes in stage 4, and nothing is sent to SAP.
-- Needs schema-update-v39.sql and v40. Additive. Safe to run twice. Undo: schema-rollback-v41.sql.

do $$ begin
  if to_regprocedure('public.bcm_master_act(jsonb)') is null or to_regprocedure('public.pt_bcm_seed_upd(text,jsonb,jsonb)') is null then
    raise exception 'Run schema-update-v39.sql and v40 first, then this update'; end if;
end $$;

-- ------------------------------------------------------------------ 1. rights
do $$
declare cur text[] := pt_rights(); src text; k text;
begin
  foreach k in array array['bcm.budget','bcm.budget.approve'] loop if not (k = any(cur)) then cur := cur || k; end if; end loop;
  execute format('create or replace function pt_rights() returns text[] language sql immutable as $f$ select %L::text[] $f$', cur::text);
  select prosrc into src from pg_proc where proname = 'pt_right_default' and pronamespace = 'public'::regnamespace and pronargs = 2;
  if position('bcm.budget' in src) = 0 then
    if position('else false end' in src) = 0 then raise exception 'pt_right_default does not have the expected shape; add the bcm.budget rights by hand'; end if;
    src := regexp_replace(src, 'else false end', E'when ''bcm.budget''              then base = ''costing''\n    when ''bcm.budget.approve''      then false\n    else false end');
    execute format('create or replace function pt_right_default(base text, k text) returns boolean language sql immutable as $f$%s$f$', src);
  end if;
end $$;
create or replace function pt_bcm(u uuid, pid text, k text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((pid is null or user_sees(u, pid)) and pt_right(u, 'money.view', false) and pt_right(u, k, k in ('bcm.review','bcm.master','bcm.approve','bcm.budget.approve') and pt_is_head(u)), false) $$;

-- ------------------------------------------------------------------ 2. tables
create table if not exists bcm_roles (
  file_id text not null references bcm_files(id) on delete cascade, run int not null, sheet text not null, project_id text not null, batch_id text not null,
  role text not null check (role in ('summary','breakdown','backup','alternative','previous','reference')), status text not null default 'Proposed' check (status in ('Proposed','Confirmed')),
  basis jsonb, by_user uuid, by_name text, at_time timestamptz not null default now(), primary key (file_id, run, sheet));
create table if not exists bcm_dups (
  id text primary key, batch_id text not null references bcm_batches(id) on delete cascade, project_id text not null,
  kind text not null check (kind in ('exact','figures','spec','backup','total')), lines jsonb not null, backup_lines jsonb, evidence jsonb, score numeric, blocking boolean not null default false,
  status text not null default 'Open' check (status in ('Open','Decided','Obsolete')),
  decision text check (decision is null or decision in ('valid','duplicate','backup','superseded','excluded')), keep jsonb, details boolean, targets jsonb, includes jsonb, reason text,
  decided_by uuid, decided_by_name text, decided_at timestamptz, updated_at timestamptz not null default now());
create index if not exists bcm_dups_batch on bcm_dups (batch_id);
alter table bcm_dups add column if not exists includes jsonb;
create table if not exists bcm_alloc (
  id text primary key, line_id text not null references bcm_lines(id) on delete cascade, project_id text not null, batch_id text not null,
  rows jsonb not null, by_pct boolean not null default false, method text not null check (method in ('Source breakdown','Approved allocation rule','Manual')), evidence text,
  status text not null default 'Proposed' check (status in ('Proposed','Approved','Rejected','Withdrawn')),
  proposed_by uuid, proposed_by_name text, proposed_at timestamptz not null default now(), decided_by uuid, decided_by_name text, decided_at timestamptz, reason text);
create unique index if not exists bcm_alloc_active on bcm_alloc (line_id) where status in ('Proposed','Approved');
create table if not exists bcm_recon_notes (
  id bigserial primary key, batch_id text not null references bcm_batches(id) on delete cascade, project_id text not null, check_key text not null, reason text not null,
  by_user uuid, by_name text, at_time timestamptz not null default now());
create table if not exists bcm_versions (
  id text primary key, project_id text not null references projects(id) on delete cascade,
  kind text not null check (kind in ('Tender estimate','Rev 0','Revised Rev 0','Approved revision')), rev_no int not null, title text, currency text not null check (currency ~ '^[A-Z]{3}$'),
  status text not null default 'Draft' check (status in ('Draft','Submitted','Under Review','Approved in ProTrackAI','Ready for SAP Loading','SAP Loading Confirmed','Rejected','Cancelled')),
  source text not null check (source in ('batch','import')), batch_id text, file jsonb, prev_id text, justification text, effective_date date, total numeric(24,6), n int,
  prepared_by uuid, prepared_by_name text, prepared_at timestamptz not null default now(), submitted_by uuid, submitted_by_name text, submitted_at timestamptz,
  reviewed_by uuid, reviewed_by_name text, reviewed_at timestamptz, approved_by uuid, approved_by_name text, approved_at timestamptz,
  closed_by uuid, closed_by_name text, closed_at timestamptz, close_reason text, sap_ref text, updated_at timestamptz not null default now(), unique (project_id, kind, rev_no));
create table if not exists bcm_version_lines (
  version_id text not null references bcm_versions(id) on delete cascade, n int not null, wbs_id text, wbs_code text, sap_wbs_id text, descr text, user_field text, cost_type text,
  amount numeric(24,6) not null, src jsonb, primary key (version_id, n));
create table if not exists bcm_version_hist (
  id bigserial primary key, version_id text not null references bcm_versions(id) on delete cascade, project_id text not null, action text not null, status text, reason text,
  by_user uuid, by_name text, at_time timestamptz not null default now());

-- a version's lines are written only while it is a draft (at its creation); history and notes never change
create or replace function pt_bcm_vl_frozen() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if (select status from bcm_versions where id = new.version_id) = 'Draft' then return new; end if;
    raise exception 'The lines of a submitted or approved budget version never change; make a new version';
  end if;
  if tg_op = 'DELETE' and not exists (select 1 from bcm_versions where id = old.version_id) then return old; end if;
  raise exception 'The lines of a budget version never change; make a new version';
end $$;
drop trigger if exists bcm_vl_frozen on bcm_version_lines;
create trigger bcm_vl_frozen before insert or update or delete on bcm_version_lines for each row execute function pt_bcm_vl_frozen();
drop trigger if exists bcm_vh_frozen on bcm_version_hist;
create trigger bcm_vh_frozen before update or delete on bcm_version_hist for each row execute function pt_bcm_frozen();
drop trigger if exists bcm_rn_frozen on bcm_recon_notes;
create trigger bcm_rn_frozen before update or delete on bcm_recon_notes for each row execute function pt_bcm_frozen();
-- pt_bcm_frozen allows a cascade from a deleted batch or version
create or replace function pt_bcm_frozen() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' and tg_table_name = 'bcm_lines' and not exists (select 1 from bcm_files where id = old.file_id) then return old; end if;
  if tg_op = 'DELETE' and tg_table_name = 'bcm_recon_notes' and not exists (select 1 from bcm_batches where id = old.batch_id) then return old; end if;
  if tg_op = 'DELETE' and tg_table_name = 'bcm_version_hist' and not exists (select 1 from bcm_versions where id = old.version_id) then return old; end if;
  if tg_op = 'DELETE' and tg_table_name in ('bcm_class_hist','bcm_audit','bcm_master_hist') and current_setting('protrack.bcm_purge', true) = 'on' then return old; end if;
  raise exception 'Source lines, classification history, master-data history and the audit log are never changed or deleted';
end $$;

do $$
declare t text;
begin
  foreach t in array array['bcm_roles','bcm_dups','bcm_alloc','bcm_recon_notes','bcm_versions','bcm_version_lines','bcm_version_hist'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists %I on %I', t || '_read', t);
    execute format('revoke all on %I from anon', t);
    execute format('revoke insert, update, delete, truncate on %I from authenticated', t);
    execute format('grant select on %I to authenticated', t);
  end loop;
end $$;
create policy bcm_roles_read on bcm_roles for select using (pt_bcm_reads(project_id));
create policy bcm_dups_read on bcm_dups for select using (pt_bcm_reads(project_id));
create policy bcm_alloc_read on bcm_alloc for select using (pt_bcm_reads(project_id));
create policy bcm_recon_notes_read on bcm_recon_notes for select using (pt_bcm_reads(project_id));
create policy bcm_versions_read on bcm_versions for select using (pt_bcm_reads(project_id));
create policy bcm_version_lines_read on bcm_version_lines for select using (pt_bcm_reads((select project_id from bcm_versions v where v.id = version_id)));
create policy bcm_version_hist_read on bcm_version_hist for select using (pt_bcm_reads(project_id));

-- ------------------------------------------------------------------ 3. helpers: tolerance, SAP WBS ID, which lines count
-- the larger of an absolute amount and a percentage of the expected value, by currency and project type (settings: tols)
create or replace function pt_bcm_tol(c text, pt text, base numeric) returns numeric language sql stable security definer set search_path = public as $$
  with t as (select coalesce((select v from jsonb_array_elements(coalesce(pt_bcm_cfg() -> 'tols', '[]'::jsonb)) v
                  where coalesce(v ->> 'cur', 'SAR') = coalesce(c, 'SAR') and (coalesce(v ->> 'ptype', '') = '' or v ->> 'ptype' = pt) order by (coalesce(v ->> 'ptype', '') <> '') desc limit 1),
               pt_bcm_cfg() -> 'tolerance', '{"abs":"1","pct":"0.01"}'::jsonb) as v)
  select greatest(coalesce((v ->> 'abs')::numeric, 1), abs(coalesce(base, 0)) * coalesce((v ->> 'pct')::numeric, 0) / 100) from t $$;
-- the SAP WBS ID of an element on a project: its PE number (else its id) and the approved segments down the tree
create or replace function pt_bcm_sap_id(wid text, pid text) returns text language plpgsql stable security definer set search_path = public as $$
declare s text[] := '{}'; cur_id text := wid; d jsonb; n int := 0; sep text := coalesce(pt_bcm_cfg() -> 'sap' ->> 'sep', '-');
begin
  while cur_id is not null and n < 20 loop
    select cur into d from bcm_master where id = cur_id and ent = 'wbs';
    if d is null or nullif(d ->> 'sap_seg', '') is null then return null; end if;
    s := (d ->> 'sap_seg') || s; cur_id := d ->> 'parent'; n := n + 1; end loop;
  return (select coalesce(pe_number, id) from projects where id = pid) || sep || array_to_string(s, sep);
end $$;
-- every cost line of the current readings of a batch: does it count, why not, is it resolved, where it goes
create or replace function pt_bcm_eval(bid text) returns table (line_id text, file_id text, sheet text, amount numeric, cur text, counts boolean, why text, resolved boolean,
  wbs_id text, cost_type text, alloc jsonb, role text, role_status text, cls_status text) language sql stable security definer set search_path = public as $$
  with b as (select * from bcm_batches where id = bid),
  l as (select x.*, coalesce(c.corr ->> 'kind', x.kind) as ek, c.status as cs, c.wbs_id as cw, c.cost_type as ct
         from bcm_lines x join bcm_files f on f.id = x.file_id and f.run = x.run and f.status <> 'Withdrawn' left join bcm_class c on c.line_id = x.id where x.batch_id = bid),
  t as (select e.lid, min(d.decision) as decision from bcm_dups d, jsonb_array_elements_text(coalesce(d.targets, '[]'::jsonb)) e(lid) where d.batch_id = bid and d.status = 'Decided' group by e.lid),
  i as (select distinct e.lid from bcm_dups d, jsonb_array_elements_text(coalesce(d.includes, '[]'::jsonb)) e(lid) where d.batch_id = bid and d.status = 'Decided'),
  a as (select al.line_id, al.rows from bcm_alloc al where al.batch_id = bid and al.status = 'Approved')
  select l.id, l.file_id, l.sheet, l.amount, coalesce(l.cur, (select currency from b)),
    (coalesce(r.role, 'summary') in ('summary','breakdown') or i.lid is not null) and t.lid is null and l.cs is distinct from 'Excluded with Reason',
    case when t.lid is not null then 'decision: ' || t.decision when coalesce(r.role, 'summary') not in ('summary','breakdown') and i.lid is null then 'sheet role: ' || r.role when l.cs = 'Excluded with Reason' then 'excluded with reason' end,
    a.rows is not null or (l.cs in ('Auto-Classified','Confirmed') and l.cw is not null),
    l.cw, l.ct, a.rows, r.role, r.status, l.cs
  from l left join bcm_roles r on r.file_id = l.file_id and r.run = l.run and r.sheet = l.sheet left join t on t.lid = l.id left join i on i.lid = l.id left join a on a.line_id = l.id
  where l.ek = 'item' $$;
-- the figures of a batch, worked out on the server: by WBS and cost type, the files' control totals, and what stops a budget version
create or replace function bcm_totals(bid text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare b bcm_batches; res jsonb; probs jsonb := '[]'::jsonb; x record; lim numeric; tol numeric;
begin
  select * into b from bcm_batches where id = bid;
  if b.id is null then raise exception 'Unknown batch'; end if;
  if not pt_bcm_reads(b.project_id) and auth.uid() is not null then raise exception 'You do not see this batch' using errcode = '42501'; end if;
  -- what stops a budget version
  select count(*), coalesce(sum(amount), 0) into x from pt_bcm_eval(bid) e where e.counts and not e.resolved;
  if x.count > 0 then probs := probs || jsonb_build_object('key', 'unresolved', 'n', x.count, 'msg', x.count || ' counting lines are not classified yet (unclassified, waiting for review, or a split not approved)'); end if;
  select count(*) into x from pt_bcm_eval(bid) e where e.counts and e.amount is null;
  if x.count > 0 then probs := probs || jsonb_build_object('key', 'no_amount', 'n', x.count, 'msg', x.count || ' counting lines have no amount'); end if;
  select count(*) into x from pt_bcm_eval(bid) e where e.counts and e.cur <> b.currency;
  if x.count > 0 then probs := probs || jsonb_build_object('key', 'currency', 'n', x.count, 'msg', x.count || ' counting lines are in another currency than ' || b.currency || ' (ProTrack does not convert)'); end if;
  select count(*) into x from pt_bcm_eval(bid) e where e.counts and e.resolved and e.alloc is null and not pt_bcm_wbs_ok(e.wbs_id);
  if x.count > 0 then probs := probs || jsonb_build_object('key', 'wbs', 'n', x.count, 'msg', x.count || ' lines are classified to an element that is no longer approved, active and postable'); end if;
  select count(*) into x from bcm_dups d where d.batch_id = bid and d.status = 'Open' and d.blocking;
  if x.count > 0 then probs := probs || jsonb_build_object('key', 'dups', 'n', x.count, 'msg', x.count || ' duplicate or backup candidates are not decided'); end if;
  select count(*) into x from (select distinct e.file_id, e.sheet from pt_bcm_eval(bid) e where e.role_status is distinct from 'Confirmed') s;
  if x.count > 0 then probs := probs || jsonb_build_object('key', 'roles', 'n', x.count, 'msg', x.count || ' sheets have no confirmed role'); end if;
  select count(*) into x from bcm_alloc a where a.batch_id = bid and a.status = 'Proposed';
  if x.count > 0 then probs := probs || jsonb_build_object('key', 'allocs', 'n', x.count, 'msg', x.count || ' split allocations wait for approval'); end if;
  -- the files' control totals against the lines counted
  for x in select f.id, f.name, (f.control ->> 'amount')::numeric as ctl, coalesce((select sum(e.amount) from pt_bcm_eval(bid) e where e.file_id = f.id and e.counts and e.cur = b.currency), 0) as counted
           from bcm_files f where f.batch_id = bid and f.status <> 'Withdrawn' and f.control ->> 'amount' is not null loop
    tol := pt_bcm_tol(b.currency, b.ptype, x.ctl);
    if abs(x.ctl - x.counted) > tol and not exists (select 1 from bcm_recon_notes n where n.batch_id = bid and n.check_key = 'src:' || x.id) then
      probs := probs || jsonb_build_object('key', 'src:' || x.id, 'n', 1, 'msg', x.name || ': the control total ' || x.ctl || ' differs from the lines counted ' || x.counted || ' by ' || (x.ctl - x.counted) || ' (tolerance ' || tol || '), not explained'); end if;
  end loop;
  select jsonb_build_object('batch_id', bid, 'currency', b.currency, 'ready', jsonb_array_length(probs) = 0, 'problems', probs,
    'wbs', coalesce((select jsonb_agg(jsonb_build_object('wbs_id', w.wbs_id, 'cost_type', w.cost_type, 'amount', w.amt::text) order by w.wbs_id, w.cost_type) from (
        select q.wbs_id, q.cost_type, sum(q.amount)::numeric(24,6) as amt from (
          select e.wbs_id, e.cost_type, e.amount from pt_bcm_eval(bid) e where e.counts and e.resolved and e.alloc is null and e.cur = b.currency
          union all select r ->> 'wbs_id', r ->> 'cost_type', (r ->> 'amount')::numeric from pt_bcm_eval(bid) e, jsonb_array_elements(e.alloc) r where e.counts and e.alloc is not null and e.cur = b.currency) q
        group by q.wbs_id, q.cost_type) w), '[]'::jsonb),
    'counted', (select coalesce(sum(amount), 0)::text from pt_bcm_eval(bid) e where e.counts and e.cur = b.currency),
    'not_counted', (select coalesce(sum(amount), 0)::text from pt_bcm_eval(bid) e where not e.counts and e.cur = b.currency),
    'unresolved', (select coalesce(sum(amount), 0)::text from pt_bcm_eval(bid) e where e.counts and not e.resolved and e.cur = b.currency)) into res;
  return res;
end $$;

-- ------------------------------------------------------------------ 4. sheet roles, candidates, allocations, explanations
create or replace function bcm_stage3(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; who text; rl text; act text := p ->> 'action'; b bcm_batches; f bcm_files; x jsonb; d bcm_dups; l bcm_lines; a bcm_alloc; n int := 0; tg jsonb; allids jsonb; k jsonb;
        sm numeric; amt numeric; tol numeric; rid text; inc jsonb; rs text := left(btrim(coalesce(p ->> 'reason', '')), 1000); ids text[];
begin
  select * into u, who, rl from pt_bcm_me();
  -- sheet roles: proposals from ProTrack (kept when a person confirmed), or a person's confirmation
  if act in ('roles_propose','roles_confirm') then
    select * into f from bcm_files where id = p ->> 'file_id';
    if f.id is null then raise exception 'Unknown file'; end if;
    if act = 'roles_propose' and not (pt_bcm(u, f.project_id, 'bcm.upload') or pt_bcm(u, f.project_id, 'bcm.review')) then raise exception 'You cannot propose sheet roles on this project' using errcode = '42501'; end if;
    if act = 'roles_confirm' and not pt_bcm(u, f.project_id, 'bcm.review') then raise exception 'Only a reviewer (bcm.review) confirms sheet roles' using errcode = '42501'; end if;
    if (p ->> 'run')::int is distinct from f.run then raise exception 'That reading is no longer the current one'; end if;
    for x in select * from jsonb_array_elements(coalesce(p -> 'roles', '[]'::jsonb)) loop
      if not (x ->> 'role' = any(array['summary','breakdown','backup','alternative','previous','reference'])) then raise exception 'Unknown sheet role %', x ->> 'role'; end if;
      if act = 'roles_propose' then
        insert into bcm_roles (file_id, run, sheet, project_id, batch_id, role, status, basis, by_user, by_name) values (f.id, f.run, x ->> 'sheet', f.project_id, f.batch_id, x ->> 'role', 'Proposed', x -> 'basis', u, who)
          on conflict (file_id, run, sheet) do update set role = excluded.role, basis = excluded.basis, by_user = u, by_name = who, at_time = now() where bcm_roles.status = 'Proposed';
      else
        insert into bcm_roles (file_id, run, sheet, project_id, batch_id, role, status, basis, by_user, by_name) values (f.id, f.run, x ->> 'sheet', f.project_id, f.batch_id, x ->> 'role', 'Confirmed', x -> 'basis', u, who)
          on conflict (file_id, run, sheet) do update set role = excluded.role, status = 'Confirmed', by_user = u, by_name = who, at_time = now();
      end if; n := n + 1; end loop;
    perform pt_bcm_log(u, who, rl, case when act = 'roles_confirm' then 'Sheet roles confirmed' else 'Sheet roles proposed' end, 'file', f.id, f.project_id, jsonb_build_object('n', n, 'roles', p -> 'roles'));
    return jsonb_build_object('ok', true, 'n', n);
  end if;
  -- candidates: ProTrack's proposals (decided ones kept; those no longer found become Obsolete)
  if act = 'dups_save' then
    select * into b from bcm_batches where id = p ->> 'batch_id';
    if b.id is null then raise exception 'Unknown batch'; end if;
    if not (pt_bcm(u, b.project_id, 'bcm.upload') or pt_bcm(u, b.project_id, 'bcm.review')) then raise exception 'You cannot run the analysis on this project' using errcode = '42501'; end if;
    if jsonb_array_length(coalesce(p -> 'cands', '[]'::jsonb)) > 5000 then raise exception 'Too many candidates at once'; end if;
    for x in select * from jsonb_array_elements(coalesce(p -> 'cands', '[]'::jsonb)) loop
      if not (x ->> 'kind' = any(array['exact','figures','spec','backup','total'])) then raise exception 'Unknown candidate kind %', x ->> 'kind'; end if;
      if exists (select 1 from jsonb_array_elements_text(coalesce(x -> 'lines', '[]'::jsonb) || coalesce(x -> 'backup_lines', '[]'::jsonb)) e(lid)
                 where not exists (select 1 from bcm_lines y join bcm_files z on z.id = y.file_id and z.run = y.run where y.id = e.lid and y.batch_id = b.id)) then
        raise exception 'Candidate % names a line that is not in the current reading of this batch', x ->> 'id'; end if;
      insert into bcm_dups (id, batch_id, project_id, kind, lines, backup_lines, evidence, score, blocking, status)
        values (x ->> 'id', b.id, b.project_id, x ->> 'kind', x -> 'lines', x -> 'backup_lines', x -> 'evidence', (x ->> 'score')::numeric, x ->> 'kind' in ('exact','figures','backup'), 'Open')
        on conflict (id) do update set evidence = excluded.evidence, score = excluded.score, status = case when bcm_dups.status = 'Obsolete' then 'Open' else bcm_dups.status end, updated_at = now()
        where bcm_dups.status <> 'Decided';
      n := n + 1; end loop;
    update bcm_dups set status = 'Obsolete', updated_at = now() where batch_id = b.id and status = 'Open' and not (id = any(array(select jsonb_array_elements(coalesce(p -> 'cands', '[]'::jsonb)) ->> 'id')));
    perform pt_bcm_log(u, who, rl, 'Duplicate and backup analysis run', 'batch', b.id, b.project_id, jsonb_build_object('candidates', n));
    return jsonb_build_object('ok', true, 'n', n);
  end if;
  -- a person's decision on a candidate; the server works out which lines stop counting
  if act in ('dup_decide','dup_reopen') then
    select * into d from bcm_dups where id = p ->> 'id' for update;
    if d.id is null then raise exception 'Unknown candidate'; end if;
    if not pt_bcm(u, d.project_id, 'bcm.review') then raise exception 'Only a reviewer (bcm.review) decides duplicates and backups' using errcode = '42501'; end if;
    if act = 'dup_reopen' then
      if d.status <> 'Decided' then raise exception 'The candidate is not decided'; end if;
      if length(rs) < 5 then raise exception 'Give the reason (at least 5 characters)'; end if;
      update bcm_dups set status = 'Open', decision = null, keep = null, details = null, targets = null, includes = null, reason = rs, decided_by = u, decided_by_name = who, decided_at = now(), updated_at = now() where id = d.id;
      perform pt_bcm_log(u, who, rl, 'Duplicate decision reopened', 'dup', d.id, d.project_id, jsonb_build_object('previous', d.decision, 'reason', rs));
      return jsonb_build_object('ok', true);
    end if;
    if d.status <> 'Open' then raise exception 'The candidate is % (reopen it first)', lower(d.status); end if;
    if not (p ->> 'decision' = any(array['valid','duplicate','backup','superseded','excluded'])) then raise exception 'Choose a decision'; end if;
    inc := null;
    if p ->> 'decision' <> 'valid' and length(rs) < 5 then raise exception 'Give the reason (at least 5 characters)'; end if;
    allids := d.lines || coalesce(d.backup_lines, '[]'::jsonb);
    if p ->> 'decision' = 'valid' then tg := '[]'::jsonb; if d.kind = 'backup' then inc := d.backup_lines; end if;
    elsif d.kind = 'backup' and p ->> 'decision' = 'backup' then tg := case when coalesce((p ->> 'details')::boolean, false) then d.lines else coalesce(d.backup_lines, '[]'::jsonb) end;
      if coalesce((p ->> 'details')::boolean, false) then inc := d.backup_lines; end if;   -- the backup lines count instead of the summary line, whatever their sheet's role
    else
      k := coalesce(p -> 'keep', '[]'::jsonb);
      if jsonb_array_length(k) = 0 or exists (select 1 from jsonb_array_elements_text(k) e(v) where not allids ? e.v) then raise exception 'Choose the line or lines that count'; end if;
      select coalesce(jsonb_agg(e.v), '[]'::jsonb) into tg from jsonb_array_elements_text(allids) e(v) where not k ? e.v;
      if jsonb_array_length(tg) = 0 then raise exception 'At least one line stops counting under this decision; else choose "valid independent cost"'; end if;
    end if;
    update bcm_dups set status = 'Decided', decision = p ->> 'decision', keep = p -> 'keep', details = (p ->> 'details')::boolean, targets = tg, includes = inc, reason = nullif(rs, ''), decided_by = u, decided_by_name = who, decided_at = now(), updated_at = now() where id = d.id;
    perform pt_bcm_log(u, who, rl, 'Duplicate decided: ' || (p ->> 'decision'), 'dup', d.id, d.project_id, jsonb_build_object('kind', d.kind, 'not_counted', tg, 'reason', nullif(rs, '')));
    return jsonb_build_object('ok', true, 'targets', tg);
  end if;
  -- split allocations of a line
  if act in ('alloc_propose','alloc_approve','alloc_reject','alloc_withdraw') then
    if act = 'alloc_propose' then
      select * into l from bcm_lines where id = p ->> 'line_id';
      if l.id is null then raise exception 'Unknown line'; end if;
      if not pt_bcm(u, l.project_id, 'bcm.review') then raise exception 'Only a reviewer (bcm.review) proposes a split' using errcode = '42501'; end if;
      if not exists (select 1 from bcm_files z where z.id = l.file_id and z.run = l.run) then raise exception 'The line is from an earlier reading'; end if;
      if l.amount is null then raise exception 'The line has no amount to allocate'; end if;
      if not (p ->> 'method' = any(array['Source breakdown','Approved allocation rule','Manual'])) then raise exception 'Choose the allocation method'; end if;
      if p ->> 'method' = 'Manual' and length(btrim(coalesce(p ->> 'evidence', ''))) < 5 then raise exception 'A manual allocation needs its basis written down'; end if;
      if jsonb_array_length(coalesce(p -> 'rows', '[]'::jsonb)) < 2 then raise exception 'A split has at least two allocations'; end if;
      sm := 0;
      for x in select * from jsonb_array_elements(p -> 'rows') loop
        if not pt_bcm_wbs_ok(x ->> 'wbs_id') then raise exception '% is not an approved, active, postable WBS element', coalesce(x ->> 'wbs_id', 'No element'); end if;
        if not (x ->> 'cost_type' = any(array['Material','Manpower','Equipment','Subcontract','Services','Overhead','Financing','Reserve','Other'])) then raise exception 'Each allocation needs its cost type'; end if;
        amt := (x ->> 'amount')::numeric; if amt is null then raise exception 'Each allocation needs an amount'; end if; sm := sm + amt; end loop;
      select * into b from bcm_batches where id = l.batch_id; tol := least(pt_bcm_tol(coalesce(l.cur, b.currency), b.ptype, l.amount), 1);
      if abs(sm - l.amount) > tol then raise exception 'The allocations add up to %, not the line amount % (difference %)', sm, l.amount, l.amount - sm; end if;
      rid := 'AL-' || substr(md5(random()::text || clock_timestamp()::text), 1, 10);
      update bcm_alloc set status = 'Withdrawn', decided_by = u, decided_by_name = who, decided_at = now(), reason = 'Replaced by ' || rid where line_id = l.id and status = 'Proposed';
      if exists (select 1 from bcm_alloc where line_id = l.id and status = 'Approved') then raise exception 'The line already has an approved split; reject it first'; end if;
      insert into bcm_alloc (id, line_id, project_id, batch_id, rows, by_pct, method, evidence, proposed_by, proposed_by_name) values (rid, l.id, l.project_id, l.batch_id, p -> 'rows', coalesce((p ->> 'by_pct')::boolean, false), p ->> 'method', left(p ->> 'evidence', 1000), u, who);
      perform pt_bcm_log(u, who, rl, 'Split proposed', 'alloc', rid, l.project_id, jsonb_build_object('line', l.id, 'rows', jsonb_array_length(p -> 'rows'), 'method', p ->> 'method'));
      return jsonb_build_object('ok', true, 'id', rid);
    end if;
    select * into a from bcm_alloc where id = p ->> 'id' for update;
    if a.id is null then raise exception 'Unknown split'; end if;
    if act = 'alloc_withdraw' then
      if a.proposed_by is distinct from u or a.status <> 'Proposed' then raise exception 'Only its proposer withdraws a waiting split'; end if;
      update bcm_alloc set status = 'Withdrawn', decided_by = u, decided_by_name = who, decided_at = now(), reason = nullif(rs, '') where id = a.id;
      return jsonb_build_object('ok', true);
    end if;
    if not pt_bcm(u, a.project_id, 'bcm.review') then raise exception 'Only a reviewer (bcm.review) approves or rejects a split' using errcode = '42501'; end if;
    if a.proposed_by = u then raise exception 'You proposed this split, so someone else approves or rejects it'; end if;
    if act = 'alloc_approve' then
      if a.status <> 'Proposed' then raise exception 'The split is %', lower(a.status); end if;
      for x in select * from jsonb_array_elements(a.rows) loop if not pt_bcm_wbs_ok(x ->> 'wbs_id') then raise exception '% is no longer an approved, active, postable element', x ->> 'wbs_id'; end if; end loop;
      update bcm_alloc set status = 'Approved', decided_by = u, decided_by_name = who, decided_at = now() where id = a.id;
      insert into bcm_class (line_id, project_id, batch_id, status) values (a.line_id, a.project_id, a.batch_id, 'Confirmed') on conflict (line_id) do nothing;
      update bcm_class set status = 'Confirmed', wbs_id = null, cost_type = null, layer = 'split', conf = null, explain = 'Split into ' || jsonb_array_length(a.rows) || ' allocations (' || a.method || '), approved by ' || who,
        reason = 'Split ' || a.id, decided_by = u, decided_by_name = who, decided_at = now(), seq = seq + 1, updated_at = now() where line_id = a.line_id;
      insert into bcm_class_hist (line_id, project_id, seq, action, status, reason, by_user, by_name) values (a.line_id, a.project_id, (select seq from bcm_class where line_id = a.line_id), 'Split approved', 'Confirmed', a.id, u, who);
      perform pt_bcm_log(u, who, rl, 'Split approved', 'alloc', a.id, a.project_id, jsonb_build_object('line', a.line_id));
      return jsonb_build_object('ok', true);
    end if;
    if length(rs) < 5 then raise exception 'Give the reason (at least 5 characters)'; end if;
    if a.status not in ('Proposed','Approved') then raise exception 'The split is %', lower(a.status); end if;
    if a.status = 'Approved' then
      update bcm_class set status = 'Split Required', layer = null, explain = 'The approved split ' || a.id || ' was rejected: ' || rs, decided_by = u, decided_by_name = who, decided_at = now(), seq = seq + 1, updated_at = now() where line_id = a.line_id;
      insert into bcm_class_hist (line_id, project_id, seq, action, status, reason, by_user, by_name) values (a.line_id, a.project_id, (select seq from bcm_class where line_id = a.line_id), 'Split rejected', 'Split Required', rs, u, who);
    end if;
    update bcm_alloc set status = 'Rejected', decided_by = u, decided_by_name = who, decided_at = now(), reason = rs where id = a.id;
    perform pt_bcm_log(u, who, rl, 'Split rejected', 'alloc', a.id, a.project_id, jsonb_build_object('reason', rs));
    return jsonb_build_object('ok', true);
  end if;
  -- a variance explained (never adjusted)
  if act = 'recon_note' then
    select * into b from bcm_batches where id = p ->> 'batch_id';
    if b.id is null then raise exception 'Unknown batch'; end if;
    if not pt_bcm(u, b.project_id, 'bcm.review') then raise exception 'Only a reviewer (bcm.review) explains a variance' using errcode = '42501'; end if;
    if length(rs) < 10 then raise exception 'Explain the variance (at least 10 characters)'; end if;
    if coalesce(p ->> 'check_key', '') = '' then raise exception 'Which check?'; end if;
    insert into bcm_recon_notes (batch_id, project_id, check_key, reason, by_user, by_name) values (b.id, b.project_id, left(p ->> 'check_key', 200), rs, u, who);
    perform pt_bcm_log(u, who, rl, 'Variance explained', 'batch', b.id, b.project_id, jsonb_build_object('check', p ->> 'check_key', 'reason', rs));
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'Unknown action %', act;
end $$;

-- ------------------------------------------------------------------ 5. budget versions
create or replace function bcm_version_act(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; who text; rl text; act text := p ->> 'action'; v bcm_versions; b bcm_batches; t jsonb; x jsonb; cnt int := 0; vid text; pid text; rv int; tot numeric := 0; w jsonb; rs text := left(btrim(coalesce(p ->> 'reason', '')), 1000);
        knd text := p ->> 'kind'; seen text[] := '{}'; key text; wid text; ns text;
begin
  select * into u, who, rl from pt_bcm_me();
  if act in ('from_batch','import') then
    if not (knd = any(array['Tender estimate','Rev 0','Revised Rev 0','Approved revision'])) then raise exception 'Choose the kind of version'; end if;
    if length(btrim(coalesce(p ->> 'justification', ''))) < 5 then raise exception 'Give the justification of the version'; end if;
    if act = 'from_batch' then
      select * into b from bcm_batches where id = p ->> 'batch_id';
      if b.id is null then raise exception 'Unknown batch'; end if;
      pid := b.project_id;
      if not pt_bcm(u, pid, 'bcm.budget') then raise exception 'You cannot prepare budget versions on this project (the bcm.budget right)' using errcode = '42501'; end if;
      t := bcm_totals(b.id);
      if not (t ->> 'ready')::boolean then raise exception 'The batch is not ready for a budget version: %', (select string_agg(e ->> 'msg', '; ') from jsonb_array_elements(t -> 'problems') e); end if;
    else
      pid := p ->> 'project_id';
      if not exists (select 1 from projects where id = pid) then raise exception 'Choose the project'; end if;
      if not pt_bcm(u, pid, 'bcm.budget') then raise exception 'You cannot prepare budget versions on this project (the bcm.budget right)' using errcode = '42501'; end if;
      if coalesce(p ->> 'currency', '') !~ '^[A-Z]{3}$' then raise exception 'Choose the currency'; end if;
      if jsonb_typeof(p -> 'lines') <> 'array' or jsonb_array_length(p -> 'lines') = 0 or jsonb_array_length(p -> 'lines') > 5000 then raise exception 'Send 1 to 5000 lines'; end if;
    end if;
    select coalesce(max(rev_no), -1) + 1 into rv from bcm_versions where project_id = pid and kind = knd;
    vid := 'BV-' || to_char(now(), 'YYMMDD') || '-' || substr(md5(random()::text || clock_timestamp()::text), 1, 6);
    insert into bcm_versions (id, project_id, kind, rev_no, title, currency, status, source, batch_id, file, justification, effective_date, prepared_by, prepared_by_name)
      values (vid, pid, knd, rv, nullif(left(p ->> 'title', 200), ''), case when act = 'from_batch' then b.currency else p ->> 'currency' end, 'Draft', case when act = 'from_batch' then 'batch' else 'import' end,
              b.id, p -> 'file', left(p ->> 'justification', 2000), nullif(p ->> 'effective_date', '')::date, u, who);
    if act = 'from_batch' then
      for w in select * from jsonb_array_elements(t -> 'wbs') loop
        cnt := cnt + 1;
        insert into bcm_version_lines (version_id, n, wbs_id, wbs_code, sap_wbs_id, descr, user_field, cost_type, amount, src)
        select vid, cnt, m.id, m.cur ->> 'code', pt_bcm_sap_id(m.id, pid), m.cur ->> 'desc', m.cur ->> 'user_field', w ->> 'cost_type', (w ->> 'amount')::numeric, jsonb_build_object('batch', b.id, 'wbs_ver', m.ver)
          from bcm_master m where m.id = w ->> 'wbs_id';
        tot := tot + (w ->> 'amount')::numeric; end loop;
    else
      for x in select * from jsonb_array_elements(p -> 'lines') loop
        cnt := cnt + 1;
        if (x ->> 'amount') is null or (x ->> 'amount') !~ '^-?[0-9]+(\.[0-9]+)?$' then raise exception 'Line %: the amount is not a number', cnt; end if;
        key := lower(coalesce(nullif(x ->> 'sap_wbs_id', ''), nullif(x ->> 'wbs_code', ''), ''));
        if key = '' then raise exception 'Line %: give the SAP WBS ID or the WBS code', cnt; end if;
        if key || '|' || coalesce(x ->> 'cost_type', '') = any(seen) then raise exception 'Line %: % (cost type %) is twice in the file', cnt, coalesce(x ->> 'sap_wbs_id', x ->> 'wbs_code'), coalesce(x ->> 'cost_type', 'none'); end if;
        seen := seen || (key || '|' || coalesce(x ->> 'cost_type', ''));
        if x ->> 'cost_type' is not null and not (x ->> 'cost_type' = any(array['Material','Manpower','Equipment','Subcontract','Services','Overhead','Financing','Reserve','Other'])) then raise exception 'Line %: unknown cost type %', cnt, x ->> 'cost_type'; end if;
        wid := nullif(x ->> 'wbs_id', '');
        if wid is not null and not exists (select 1 from bcm_master where id = wid and ent = 'wbs' and cur is not null) then raise exception 'Line %: % is not an approved WBS element', cnt, wid; end if;
        if nullif(x ->> 'user_field', '') is not null and to_regprocedure('public.pt_supp_lists()') is not null
           and not exists (select 1 from jsonb_array_elements(pt_supp_lists() -> 'uf') z where lower(z ->> 0) = lower(x ->> 'user_field')) then raise exception 'Line %: the user field % is not in the user field list', cnt, x ->> 'user_field'; end if;
        insert into bcm_version_lines (version_id, n, wbs_id, wbs_code, sap_wbs_id, descr, user_field, cost_type, amount, src)
          values (vid, cnt, wid, nullif(x ->> 'wbs_code', ''), nullif(x ->> 'sap_wbs_id', ''), left(x ->> 'descr', 400), nullif(x ->> 'user_field', ''), nullif(x ->> 'cost_type', ''), (x ->> 'amount')::numeric, jsonb_build_object('row', x -> 'row'));
        tot := tot + (x ->> 'amount')::numeric; end loop;
      if p ->> 'file_total' is not null and abs((p ->> 'file_total')::numeric - tot) > pt_bcm_tol(p ->> 'currency', null, tot) then
        raise exception 'The lines add up to %, not the total % stated in the file', tot, p ->> 'file_total'; end if;
    end if;
    if cnt = 0 then raise exception 'The version has no line'; end if;
    update bcm_versions set total = tot, n = cnt where id = vid;
    insert into bcm_version_hist (version_id, project_id, action, status, reason, by_user, by_name) values (vid, pid, case when act = 'from_batch' then 'Prepared from batch ' || b.id else 'Imported' end, 'Draft', left(p ->> 'justification', 500), u, who);
    perform pt_bcm_log(u, who, rl, 'Budget version prepared', 'version', vid, pid, jsonb_build_object('kind', knd, 'rev', rv, 'total', tot, 'lines', cnt, 'source', act));
    return jsonb_build_object('ok', true, 'id', vid, 'rev_no', rv, 'total', tot::numeric(24,6)::text, 'n', cnt);
  end if;
  select * into v from bcm_versions where id = p ->> 'id' for update;
  if v.id is null then raise exception 'Unknown version'; end if;
  if act = 'submit' then
    if v.status <> 'Draft' then raise exception 'Only a draft is submitted'; end if;
    if not pt_bcm(u, v.project_id, 'bcm.budget') then raise exception 'You cannot submit budget versions (the bcm.budget right)' using errcode = '42501'; end if;
    update bcm_versions set status = 'Submitted', submitted_by = u, submitted_by_name = who, submitted_at = now(), updated_at = now() where id = v.id; ns := 'Submitted';
  elsif act = 'review' then
    if v.status <> 'Submitted' then raise exception 'Only a submitted version is taken under review'; end if;
    if not pt_bcm(u, v.project_id, 'bcm.review') then raise exception 'Only a reviewer (bcm.review) reviews budget versions' using errcode = '42501'; end if;
    if u in (v.prepared_by, v.submitted_by) then raise exception 'You prepared or submitted this version, so someone else reviews it'; end if;
    update bcm_versions set status = 'Under Review', reviewed_by = u, reviewed_by_name = who, reviewed_at = now(), updated_at = now() where id = v.id; ns := 'Under Review';
  elsif act = 'approve' then
    if v.status <> 'Under Review' then raise exception 'Only a version under review is approved'; end if;
    if not pt_bcm(u, v.project_id, 'bcm.budget.approve') then raise exception 'Only a budget approver (bcm.budget.approve) approves budget versions' using errcode = '42501'; end if;
    if u in (v.prepared_by, v.submitted_by) then raise exception 'You prepared or submitted this version, so someone else approves it'; end if;
    update bcm_versions set status = 'Approved in ProTrackAI', approved_by = u, approved_by_name = who, approved_at = now(), updated_at = now(),
      prev_id = (select id from bcm_versions o where o.project_id = v.project_id and o.id <> v.id and o.status in ('Approved in ProTrackAI','Ready for SAP Loading','SAP Loading Confirmed') order by o.approved_at desc limit 1) where id = v.id;
    ns := 'Approved in ProTrackAI';
  elsif act in ('reject','cancel') then
    if length(rs) < 5 then raise exception 'Give the reason (at least 5 characters)'; end if;
    if act = 'reject' then
      if v.status not in ('Submitted','Under Review') then raise exception 'Only a submitted version or one under review is rejected'; end if;
      if not (pt_bcm(u, v.project_id, 'bcm.review') or pt_bcm(u, v.project_id, 'bcm.budget.approve')) then raise exception 'Only a reviewer or a budget approver rejects a version' using errcode = '42501'; end if;
      if u in (v.prepared_by, v.submitted_by) then raise exception 'You prepared or submitted this version; cancel it instead'; end if;
      ns := 'Rejected';
    else
      if v.status not in ('Draft','Submitted') then raise exception 'Only a draft or a submitted version is cancelled'; end if;
      if not (u in (v.prepared_by, v.submitted_by) or pt_bcm(u, v.project_id, 'bcm.budget.approve')) then raise exception 'Only its preparer or a budget approver cancels a version' using errcode = '42501'; end if;
      ns := 'Cancelled';
    end if;
    update bcm_versions set status = ns, closed_by = u, closed_by_name = who, closed_at = now(), close_reason = rs, updated_at = now() where id = v.id;
  else raise exception 'Unknown action %', act; end if;
  insert into bcm_version_hist (version_id, project_id, action, status, reason, by_user, by_name) values (v.id, v.project_id, initcap(act), ns, nullif(rs, ''), u, who);
  perform pt_bcm_log(u, who, rl, 'Budget version ' || lower(ns), 'version', v.id, v.project_id, jsonb_build_object('kind', v.kind, 'rev', v.rev_no, 'reason', nullif(rs, '')));
  return jsonb_build_object('ok', true, 'status', ns);
end $$;
create or replace function bcm_features() returns jsonb language sql stable as $$ select '{"version": 41, "stages": [1, 2, 3], "sap_wbs": true}'::jsonb $$;

revoke execute on function pt_bcm_tol(text, text, numeric), pt_bcm_sap_id(text, text), pt_bcm_eval(text), pt_bcm_vl_frozen() from public, anon, authenticated;
revoke execute on function bcm_stage3(jsonb), bcm_version_act(jsonb), bcm_totals(text) from public, anon;
grant execute on function bcm_stage3(jsonb), bcm_version_act(jsonb), bcm_totals(text), bcm_features() to authenticated;
