-- ProTrack schema update v20 (ProTrackAI v3.11): the internal and the client revised contract value.
-- 1. The change order and claim log keeps four new columns: the client approved price, the price considered internally
--    (the full or partial value management approved before the client) and its internal WF number and WF date.
--    log_import stores them and refuses a row that breaks the rules of the app's voCheck().
-- 2. vo_update(p): the costing engineer (right logs.upload) or the costing coordinator updates one row of the project's
--    latest log: client approval status, client approved price, price considered internally, WF number, WF date,
--    remarks. Same rules as the upload. Earlier months stay as they were uploaded. Every change is kept in the new
--    append-only table co_log_updates (who, when, field: old -> new) and in the change log.
-- 3. When an internal report, client report or cost report is approved, the server works out the contract breakdown
--    from the latest log up to the report's month, as the app's contractOf() does, and saves it with the release in the
--    new column report_releases.contract_snapshot. A client report keeps only the original, the approved by the client
--    and the client revised value. A cost report also gets figures.contract and figures.contract_value (the internal
--    revised value), as in the app. A released version keeps its breakdown: it cannot be changed afterwards.
--    This is done by a trigger on report_releases, so release_act is not replaced (v19, Project Visual, may replace it).
-- Needs schema-update-v18.sql. Does not need v19. Additive: four columns, one column, one table, new helpers; the
-- append-only rule of co_log lets vo_update change those six fields only. Safe to run twice. Undo: schema-rollback-v20.sql.

do $$ begin
  if to_regclass('public.xr_layouts') is null or to_regprocedure('public.pt_xr_default_log()') is null
     or not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'report_releases' and column_name = 'mat_snapshot') then
    raise exception 'Run schema-update-v18.sql (STAGE-15-SETUP) first, then this update'; end if;
end $$;

-- ------------------------------------------------------------------ 1. the four new columns of the change order and claim log
alter table co_log add column if not exists client_price numeric;
alter table co_log add column if not exists internal_price numeric;
alter table co_log add column if not exists wf_no text;
alter table co_log add column if not exists wf_date date;

-- today in Saudi Arabia (the app's TODAY is the date on the person's computer)
create or replace function pt_today_sa() returns date language sql stable as $$
  select (now() at time zone 'Asia/Riyadh')::date $$;

-- the rules of a row, as the app's voCheck() (index.html, v3.11); null when the row is fine, else what is wrong
create or replace function pt_vo_check(cst text, cp numeric, ip numeric, est numeric, wfno text, wfd date) returns text
language sql stable as $$
  select case
    when cp < 0 or ip < 0 then 'a price cannot be negative'
    when cp > 0 and coalesce(cst, '') ~* 'reject' then 'a rejected item cannot have a client approved price'
    when cp > 0 and coalesce(cst, '') !~* 'approv' then 'a client approved price needs the client approval status Approved or Partially approved'
    when ip > 0 and (coalesce(wfno, '') = '' or wfd is null) then 'a price considered internally needs the management approval WF number and WF date'
    when ip > 0 and est > 0 and ip > est then 'the price considered internally is more than the estimated price'
    when wfd > pt_today_sa() then 'the WF date is in the future'
    when length(wfno) > 40 then 'the WF number is longer than 40 characters'
  end $$;

-- Full or Partial, as the app's voBasis(): below the estimated price it is Partial, else Full; No without a price
create or replace function pt_vo_basis(ip numeric, est numeric) returns text language sql immutable as $$
  select case when coalesce(ip, 0) <= 0 then 'No' when est > 0 and ip < est then 'Partial' else 'Full' end $$;

-- log_import: from schema-update-v16.sql, with the four new columns stored and the rules above
create or replace function log_import(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r text := role_of(auth.uid()); k text := p ->> 'kind'; pid text := p ->> 'project_id'; per text := p ->> 'period';
        rows jsonb := coalesce(p -> 'rows', '[]'::jsonb); x jsonb; acc jsonb := '[]'::jsonb; rej jsonb := '[]'::jsonb; err text; ref text;
        seen text[] := '{}'; bid uuid; last uuid; tot numeric := 0; i int := 0; ipt text;
        cats text[] := array['Project execution','Under estimate','External factor','Saudization','Finance','Claims','Change order'];
begin
  if me is null or r is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if k is null or k not in ('volog','supplements') then raise exception 'Unknown log'; end if;
  if pid is null or not user_sees(me, pid) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
  if not pt_right(me, 'logs.upload', pt_is_coord(me)) then raise exception 'Only a costing engineer, the costing coordinator or a super admin uploads this log' using errcode = '42501'; end if;
  if not pt_period_ok(per, 'month') then raise exception 'The month must look like 2026-09'; end if;
  if jsonb_typeof(rows) <> 'array' or jsonb_array_length(rows) = 0 then raise exception 'The file has no rows'; end if;
  perform pg_advisory_xact_lock(hashtext('protrack:log:' || pid || ':' || k));
  select id into last from import_batches where project_id = pid and kind = k and status = 'committed' order by at_time desc limit 1;
  if last is not null and (select file_hash from import_batches where id = last) = p ->> 'hash' and (select source_period from import_batches where id = last) = per then
    return jsonb_build_object('duplicate', true, 'batch_id', last);
  end if;
  for x in select * from jsonb_array_elements(rows) loop
    i := i + 1; err := null;
    ref := upper(btrim(coalesce(x ->> case when k = 'volog' then 'ref_no' else 'supp_no' end, '')));
    if ref = '' then err := 'reference number missing';
    elsif ref = any(seen) then err := 'reference ' || ref || ' appears twice in the file';
    elsif k = 'volog' then
      -- a file of the earlier layout: Price considered internally is Yes / No / Partial / Full; its text is kept
      ipt := btrim(coalesce(x ->> 'internal_price', ''));
      if ipt ~* '^(yes|no|partial|full)$' then x := x || jsonb_build_object('internal_price', null, 'price_internal', coalesce(nullif(btrim(x ->> 'price_internal'), ''), ipt)); end if;
      x := x || jsonb_build_object('wf_no', nullif(btrim(coalesce(x ->> 'wf_no', '')), ''));
      if coalesce(x ->> 'kind', '') not in ('VO','Claim') then err := 'type must be VO or Claim';
      elsif pt_bad_num(x ->> 'est_price') or pt_bad_num(x ->> 'est_cost') or pt_bad_num(x ->> 'expected_price') or pt_bad_num(x ->> 'rev0_change')
            or pt_bad_num(x ->> 'client_price') then err := 'a price or cost is not a number';
      elsif pt_bad_num(x ->> 'internal_price') then err := 'the price considered internally is not a number';
      elsif pt_bad_date(x ->> 'wf_date') then err := 'the WF date is not a valid date';
      elsif pt_bad_date(x ->> 'submitted_on') then err := 'the submission date is not a valid date';
      else err := pt_vo_check(x ->> 'client_status', pt_num(x ->> 'client_price'), pt_num(x ->> 'internal_price'), pt_num(x ->> 'est_price'),
                              x ->> 'wf_no', pt_date(x ->> 'wf_date'));
      end if;
      if err is null and pt_num(x ->> 'internal_price') > 0 then
        x := x || jsonb_build_object('price_internal', pt_vo_basis(pt_num(x ->> 'internal_price'), pt_num(x ->> 'est_price'))); end if;
    else
      if pt_num(x ->> 'amount') is null then err := 'amount missing or not a number';
      elsif coalesce(x ->> 'category', '') <> all(cats) then err := 'category must be one of: ' || array_to_string(cats, ', ');
      elsif pt_bad_date(x ->> 'supp_date') then err := 'the date is not a valid date';
      end if;
    end if;
    if err is null then acc := acc || jsonb_build_array(x || jsonb_build_object('_ref', ref)); seen := seen || ref;
    else rej := rej || jsonb_build_array(jsonb_build_object('row', i, 'ref', ref, 'error', err)); end if;
  end loop;
  if jsonb_array_length(acc) = 0 then raise exception 'No valid rows, so nothing was saved and the previous log stays. First problem: row % %', rej -> 0 ->> 'row', rej -> 0 ->> 'error'; end if;
  if jsonb_array_length(rej) > 0 and not coalesce((p ->> 'ack')::boolean, false) then
    raise exception '% row(s) refused; acknowledge them to save the rest. First: row % %', jsonb_array_length(rej), rej -> 0 ->> 'row', rej -> 0 ->> 'error'; end if;
  select coalesce(sum(case when k = 'volog' then coalesce(pt_num(y ->> 'expected_price'), 0) else pt_num(y ->> 'amount') end), 0) into tot from jsonb_array_elements(acc) y;
  insert into import_batches (project_id, kind, file_name, file_hash, source_period, rows_total, rows_accepted, rows_rejected, total_source, total_accepted,
                              recon_status, recon_accepted_by, detail, by_user)
  values (pid, k, left(p ->> 'file_name', 200), p ->> 'hash', per, jsonb_array_length(rows), jsonb_array_length(acc), jsonb_array_length(rej), tot, tot,
          case when jsonb_array_length(rej) > 0 then 'Accepted with difference' end, case when jsonb_array_length(rej) > 0 then me end,
          jsonb_build_object('rejected', rej), me)
  returning id into bid;
  if k = 'volog' then
    insert into co_log (batch_id, project_id, period, ref_no, kind, description, submission_status, submitted_on, client_status, est_price, est_cost,
                        expected_price, price_internal, cost_internal, rev0_change, internal_wf, overall_status, remarks,
                        client_price, internal_price, wf_no, wf_date)
    select bid, pid, per, y ->> '_ref', y ->> 'kind', left(y ->> 'description', 2000), y ->> 'submission_status', pt_date(y ->> 'submitted_on'), y ->> 'client_status',
           pt_num(y ->> 'est_price'), pt_num(y ->> 'est_cost'), pt_num(y ->> 'expected_price'), y ->> 'price_internal', y ->> 'cost_internal',
           pt_num(y ->> 'rev0_change'), y ->> 'internal_wf', y ->> 'overall_status', left(y ->> 'remarks', 2000),
           pt_num(y ->> 'client_price'), pt_num(y ->> 'internal_price'), y ->> 'wf_no', pt_date(y ->> 'wf_date')
      from jsonb_array_elements(acc) y;
  else
    insert into budget_supplements (batch_id, project_id, period, supp_no, supp_date, description, amount, category, linked_ref, approval_status, remarks)
    select bid, pid, per, y ->> '_ref', pt_date(y ->> 'supp_date'), left(y ->> 'description', 2000), pt_num(y ->> 'amount'), y ->> 'category',
           y ->> 'linked_ref', y ->> 'approval_status', left(y ->> 'remarks', 2000)
      from jsonb_array_elements(acc) y;
  end if;
  return jsonb_build_object('duplicate', false, 'batch_id', bid, 'accepted', jsonb_array_length(acc), 'rejected', rej, 'total', tot);
end $$;

-- ------------------------------------------------------------------ 2. updating a row of the latest log, with its history
create table if not exists co_log_updates (
  id bigserial primary key,
  row_id bigint not null references co_log(id),
  batch_id uuid not null references import_batches(id),
  project_id text not null references projects(id) on delete cascade,
  ref_no text not null,
  period text not null,
  changes jsonb not null,           -- [[field, old, new], ...] as the app's coAudit
  by_user uuid references profiles(id), by_name text,
  at_time timestamptz not null default now());
create index if not exists clu_proj on co_log_updates (project_id, id desc);
drop trigger if exists trg_clu_append on co_log_updates;
create trigger trg_clu_append before update or delete on co_log_updates for each row execute function pt_append_only();
drop trigger if exists trg_clu_truncate on co_log_updates;
create trigger trg_clu_truncate before truncate on co_log_updates execute function pt_no_truncate();
alter table co_log_updates enable row level security;
drop policy if exists clu_read on co_log_updates;
create policy clu_read on co_log_updates for select using (can_see(project_id) and pt_money_ok());
-- no write policies: only vo_update writes

-- co_log stays append-only, except the six fields vo_update changes (and the Full / Partial text it keeps with them)
create or replace function pt_co_log_guard() returns trigger language plpgsql as $$
declare f text[] := array['client_status','client_price','internal_price','wf_no','wf_date','remarks','price_internal'];
begin
  if tg_op = 'UPDATE' and coalesce(current_setting('protrack.co_log_update', true), '') = 'on'
     and (to_jsonb(new) - f) = (to_jsonb(old) - f) then return new; end if;
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end $$;
drop trigger if exists trg_col_append on co_log;
drop trigger if exists trg_col_guard on co_log;
create trigger trg_col_guard before update or delete on co_log for each row execute function pt_co_log_guard();

-- p: {id, client_status, client_price, internal_price, wf_no, wf_date, remarks}; the app's voUpdate()
create or replace function vo_update(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r co_log; n co_log; lb uuid; e text; t text; fld text; ch jsonb := '[]'::jsonb; ro jsonb; rn jsonb; lbl text[] := '{}';
        f text[] := array['client_status','client_price','internal_price','wf_no','wf_date','remarks','price_internal'];
        nm jsonb := '{"client_status":"Client approval","client_price":"Client approved price","internal_price":"Price considered internally",
                     "wf_no":"WF no","wf_date":"WF date","remarks":"Remarks","price_internal":"Considered"}';
begin
  if me is null or role_of(me) is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if pt_num(p ->> 'id') is null then raise exception 'That row is not in the log'; end if;
  select * into r from co_log where id = pt_num(p ->> 'id')::bigint;
  if r.id is null then raise exception 'That row is not in the log'; end if;
  if not user_sees(me, r.project_id) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
  if not pt_right(me, 'logs.upload', pt_is_coord(me)) then raise exception 'Only the costing engineer or costing coordinator updates the log' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtext('protrack:log:' || r.project_id || ':volog'));
  select * into r from co_log where id = r.id;
  select id into lb from import_batches where project_id = r.project_id and kind = 'volog' and status = 'committed' order by source_period desc, at_time desc limit 1;
  if lb is distinct from r.batch_id then raise exception 'Only the latest log of the project can be updated'; end if;
  n := r;
  n.client_status := nullif(btrim(coalesce(p ->> 'client_status', '')), '');
  t := replace(replace(coalesce(p ->> 'client_price', ''), ',', ''), ' ', '');
  if t <> '' and pt_num(t) is null then raise exception 'A price must be a number'; end if;
  n.client_price := pt_num(t);
  t := replace(replace(coalesce(p ->> 'internal_price', ''), ',', ''), ' ', '');
  if t <> '' and pt_num(t) is null then raise exception 'A price must be a number'; end if;
  n.internal_price := pt_num(t);
  n.wf_no := nullif(btrim(coalesce(p ->> 'wf_no', '')), '');
  t := btrim(coalesce(p ->> 'wf_date', ''));
  if t <> '' and (t !~ '^\d{4}-\d{2}-\d{2}$' or pt_date(t) is null) then raise exception 'The WF date is not a valid date'; end if;
  n.wf_date := pt_date(t);
  n.remarks := nullif(left(btrim(coalesce(p ->> 'remarks', '')), 300), '');
  e := pt_vo_check(n.client_status, n.client_price, n.internal_price, r.est_price, n.wf_no, n.wf_date);
  if e is not null then raise exception '%', upper(left(e, 1)) || substr(e, 2); end if;
  n.price_internal := case when n.internal_price > 0 then pt_vo_basis(n.internal_price, r.est_price)
                           when r.price_internal is not null and r.internal_price is null then r.price_internal end;
  ro := to_jsonb(r); rn := to_jsonb(n);
  foreach fld in array f loop
    if (ro -> fld) is distinct from (rn -> fld) then
      ch := ch || jsonb_build_array(jsonb_build_array(fld, ro -> fld, rn -> fld)); lbl := lbl || (nm ->> fld); end if;
  end loop;
  if jsonb_array_length(ch) = 0 then return jsonb_build_object('changed', false, 'row', ro); end if;
  perform set_config('protrack.co_log_update', 'on', true);
  update co_log set client_status = n.client_status, client_price = n.client_price, internal_price = n.internal_price, wf_no = n.wf_no,
                    wf_date = n.wf_date, remarks = n.remarks, price_internal = n.price_internal
   where id = r.id returning * into n;
  perform set_config('protrack.co_log_update', '', true);
  insert into co_log_updates (row_id, batch_id, project_id, ref_no, period, changes, by_user, by_name)
  values (r.id, r.batch_id, r.project_id, r.ref_no, r.period, ch, me, name_of(me));
  insert into change_log (project_id, text, by_user)
  values (r.project_id, coalesce((select short from projects where id = r.project_id), r.project_id) || ': change order and claim log ' || r.ref_no
                        || ' updated (' || array_to_string(lbl, ', ') || ')', me);
  return jsonb_build_object('changed', true, 'row', to_jsonb(n));
end $$;

-- ------------------------------------------------------------------ 3. the contract breakdown frozen with each release
alter table report_releases add column if not exists contract_snapshot jsonb;

-- the contract breakdown of a project from its latest change order and claim log up to the month, as the app's contractOf():
--   orig        the project's contract value (value_m × 1,000,000), null without one
--   sub, nSub   Σ estimated price of the items submitted to the client (submission status says submitted, or a submission date)
--   appr, nAppr Σ client approved price of the items not rejected
--   int         Σ price considered internally, per item: nothing when rejected; the client approved price when there is one;
--               else the price considered internally when above 0 with its WF number and WF date
--   wf, nWf     the part of int that is considered with management approval (WF)
--   n           rows in the log;  log  {no: IMP-000123, period} of that log, null without one
--   rev_int     orig + int (internal revised contract value);  rev_client  orig + appr (client-approved revised value)
create or replace function pt_contract_of(pid text, mon text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare vm numeric; orig numeric; b import_batches; x co_log; v numeric;
        sub numeric := 0; appr numeric := 0; inn numeric := 0; wf numeric := 0; n int := 0; nsub int := 0; nappr int := 0; nwf int := 0;
begin
  select value_m into vm from projects where id = pid;
  orig := case when coalesce(vm, 0) <> 0 then round(vm * 1000000) end;
  select * into b from import_batches where project_id = pid and kind = 'volog' and status = 'committed' and coalesce(source_period, '') <= coalesce(mon, '9999-12')
   order by source_period desc, at_time desc limit 1;
  if b.id is not null then
    for x in select * from co_log where batch_id = b.id order by id loop
      n := n + 1;
      if coalesce(x.submission_status, '') ~* 'submit' or x.submitted_on is not null then sub := sub + coalesce(x.est_price, 0); nsub := nsub + 1; end if;
      if coalesce(x.client_status, '') !~* 'reject' and x.client_price is not null then appr := appr + x.client_price; nappr := nappr + 1; end if;
      if coalesce(x.client_status, '') ~* 'reject' then null;
      elsif x.client_price is not null then inn := inn + x.client_price;
      elsif x.internal_price > 0 and coalesce(x.wf_no, '') <> '' and x.wf_date is not null then
        inn := inn + x.internal_price; wf := wf + x.internal_price; nwf := nwf + 1;
      end if;
    end loop;
  end if;
  return jsonb_build_object('orig', orig, 'sub', sub, 'appr', appr, 'int', inn, 'wf', wf, 'n', n, 'nSub', nsub, 'nAppr', nappr, 'nWf', nwf,
    'log', case when b.id is not null then jsonb_build_object('no', 'IMP-' || lpad(coalesce(b.seq, 0)::text, 6, '0'), 'period', b.source_period) end,
    'rev_int', orig + inn, 'rev_client', orig + appr);
end $$;

-- what a client report may carry, as the app's contractClient(): never the internal consideration
create or replace function pt_contract_client(c jsonb) returns jsonb language sql immutable as $$
  select case when c is null then null else jsonb_build_object('orig', c -> 'orig', 'appr', c -> 'appr', 'nAppr', c -> 'nAppr',
                                                               'rev_client', c -> 'rev_client', 'log', c -> 'log') end $$;

-- the month of a release, as the app's perMonth(): a weekly report counts in the month its week ends (Sunday)
create or replace function pt_rel_month(pt text, per text) returns text language sql immutable as $$
  select case when pt = 'month' then per else to_char(pt_period_end(per, pt), 'YYYY-MM') end $$;

-- At approval (status moves to Released) the server saves the breakdown; a released or superseded version keeps it.
-- Fires before trg_rr_frozen (triggers run in name order), and never on a version that is already released.
create or replace function pt_release_contract() returns trigger
language plpgsql security definer set search_path = public as $$
declare c jsonb;
begin
  if old.status in ('Released','Superseded') then
    if new.contract_snapshot is distinct from old.contract_snapshot then
      raise exception 'A released version cannot be changed; issue a new revision' using errcode = '42501'; end if;
    return new;
  end if;
  if new.status = 'Released' then
    c := pt_contract_of(new.project_id, pt_rel_month(new.period_type, new.period));
    new.contract_snapshot := case when new.kind = 'client' then pt_contract_client(c) else c end;
    if new.kind = 'cost' and c ->> 'rev_int' is not null then
      new.figures := coalesce(new.figures, '{}'::jsonb) || jsonb_build_object('contract', c, 'contract_value', c -> 'rev_int'); end if;
  else
    new.contract_snapshot := null;   -- only a released version carries one
  end if;
  return new;
end $$;
drop trigger if exists trg_rr_contract on report_releases;
create trigger trg_rr_contract before update on report_releases for each row execute function pt_release_contract();

-- ------------------------------------------------------------------ grants
revoke execute on function pt_contract_of(text, text), pt_vo_check(text, numeric, numeric, numeric, text, date) from public, anon, authenticated;
revoke execute on function vo_update(jsonb), log_import(jsonb) from public, anon;
grant execute on function vo_update(jsonb), log_import(jsonb) to authenticated;
revoke all on co_log_updates from anon;
grant select on co_log_updates to authenticated;
