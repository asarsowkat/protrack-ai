-- ProTrack schema update v35 (ProTrackAI v3.29): the budget supplement log by user field and category.
-- Each row of a budget supplement log is a supplement approved by its WF: one signed amount, its impact on the gross
-- margin, with its user field (a cost report head, or Cont. Value for the contract value), its category and the unified
-- category the category maps to, the WF date, and the WBS group, ID and description. The super admin keeps the user
-- fields and the categories (supp_lists_set); the costing engineers and the costing coordinator change the latest log of
-- a project on the screen (supp_update), each change kept in supp_audit, or upload a month's log (log_import).
-- The cost report's budget change from the log (pt_supp_approved) = −(the amounts of the rows that are not Cont. Value):
-- a supplement (negative) or a VO cost raises the budget, a saving (positive) lowers it, a VO price is contract value.
-- Logs uploaded before this update (no user field) keep their rule: their approved amounts are added to the budget.
-- Needs the v20 update (STAGE-16-SETUP). Additive: nothing is deleted. Safe to run twice. Undo: schema-rollback-v35.sql.

-- ------------------------------------------------------------------ 1. the new columns
alter table budget_supplements drop constraint if exists budget_supplements_category_check;
alter table budget_supplements add column if not exists user_field text;
alter table budget_supplements add column if not exists unified_category text;
alter table budget_supplements add column if not exists wbs_group text;
alter table budget_supplements add column if not exists wbs_id text;
alter table budget_supplements add column if not exists wbs_description text;

-- ------------------------------------------------------------------ 2. the lists (one row), kept by the super admin
create table if not exists supp_lists (
  id boolean primary key default true check (id),
  cfg jsonb not null,
  set_by uuid references profiles(id), set_by_name text, set_at timestamptz not null default now());
alter table supp_lists enable row level security;
drop policy if exists sl_read on supp_lists;
create policy sl_read on supp_lists for select using (auth.uid() is not null);
grant select on supp_lists to authenticated;
-- no write policies: only supp_lists_set writes

create or replace function pt_supp_default() returns jsonb language sql immutable as $$
  select '{"uf":[["SM","Site Management"],["DE","Design"],["TEC","Testing"],["MTRL.ELC","Electrical Material"],["MAN.ELC","Electrical Manpower"],["INSTL.ELC","Electrical inst"],["MTRL.MECH","Mechanical Material"],["MAN.MECH","Mechanical Manpower"],["INSTL.MECh","Mechanical inst"],["MTRL.CVL","Civil Material"],["MAN.CVL","Civil Manpower"],["INSTL.CVL","Civil Equip"],["CONT","Contingency"],["SAD","Saudization"],["FNE","Financing"],["PC ITEMS","Prime Cost"],["PROV. SUM","Provisional Sum"],["Cont. Value","Contract Value"],["MGT.RES","Management Reserve"]],
           "cats":[["Project Execution","Project Execution"],["Saudization","Project Execution"],["Under Estimation","Under Estimation"],["Change Order","Change Order"],["Client/External","External Factors"],["Savings","Savings"],["Cont-Under Est.","Under Estimation"],["Cont-Proj. Exe","Project Execution"],["Claim","Claim"],["Cont-Change Order","Change Order"],["CHANGE ORDER","Change Order"],["Cont-Savings","Savings"],["MGT.RES | Savings","Savings"],["Cont-Claim","Claim"],["Mgmt Res-Proj Exe","Project Execution"],["Finance","Finance"],["Contract Extension Cost","Contract Extension Cost"],["Cont-Cont. Ext.","Contract Extension Cost"],["Cont-Ext. Fac.","External Factors"],["External Factors","External Factors"],["Mgmt Res-Under Est.","Under Estimation"],["Tender Budet","Tender Budet"],["Cont-SZN","Saudization"],["Contract Value","Contract Value"]]}'::jsonb $$;
create or replace function pt_supp_lists() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select cfg from supp_lists where id), pt_supp_default()) $$;
-- a value of a list as the list writes it: exact first, else the first one that differs only in case
create or replace function pt_supp_pick(l text[], v text) returns text language sql immutable as $$
  with s as (select btrim(regexp_replace(coalesce(v, ''), '\s+', ' ', 'g')) as v)
  select coalesce((select x from unnest(l) with ordinality t(x, o), s where x = s.v order by o limit 1),
                  (select x from unnest(l) with ordinality t(x, o), s where s.v <> '' and lower(x) = lower(s.v) order by o limit 1)) $$;

-- p: {uf: [[code, description], …], cats: [[category, unified category], …]}; the app's suppListsSet()
create or replace function supp_lists_set(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); u jsonb := '[]'::jsonb; c jsonb := '[]'::jsonb; x jsonb; a text; b text; seen text[] := '{}'; seenc text[] := '{}';
begin
  if me is null or role_of(me) is distinct from 'sa' then raise exception 'Only a super admin changes the lists' using errcode = '42501'; end if;
  if jsonb_typeof(p -> 'uf') <> 'array' or jsonb_array_length(p -> 'uf') = 0 then raise exception 'The user field list needs at least one item'; end if;
  if jsonb_typeof(p -> 'cats') <> 'array' or jsonb_array_length(p -> 'cats') = 0 then raise exception 'The category list needs at least one item'; end if;
  if jsonb_array_length(p -> 'uf') > 100 or jsonb_array_length(p -> 'cats') > 100 then raise exception 'A list has at most 100 items'; end if;
  for x in select * from jsonb_array_elements(p -> 'uf') loop
    a := btrim(regexp_replace(coalesce(x ->> 0, ''), '\s+', ' ', 'g')); b := btrim(regexp_replace(coalesce(x ->> 1, ''), '\s+', ' ', 'g'));
    if a = '' or length(a) > 40 or length(b) > 200 then raise exception 'A user field needs a code of up to 40 characters and a description of up to 200'; end if;
    if lower(a) = any(seen) then raise exception 'The user field "%" is twice in the list', a; end if;
    seen := seen || lower(a); u := u || jsonb_build_array(jsonb_build_array(a, b));
  end loop;
  for x in select * from jsonb_array_elements(p -> 'cats') loop
    a := btrim(regexp_replace(coalesce(x ->> 0, ''), '\s+', ' ', 'g')); b := btrim(regexp_replace(coalesce(x ->> 1, ''), '\s+', ' ', 'g'));
    if a = '' or b = '' or length(a) > 100 or length(b) > 100 then raise exception 'A category and its unified category are each up to 100 characters'; end if;
    if a = any(seenc) then raise exception 'The category "%" is twice in the list', a; end if;
    seenc := seenc || a; c := c || jsonb_build_array(jsonb_build_array(a, b));
  end loop;
  if not ('cont. value' = any(seen)) then raise exception 'Cont. Value stays in the user field list: it marks the contract value rows (VO price, not budget)'; end if;
  insert into supp_lists (id, cfg, set_by, set_by_name, set_at) values (true, jsonb_build_object('uf', u, 'cats', c), me, name_of(me), now())
    on conflict (id) do update set cfg = excluded.cfg, set_by = excluded.set_by, set_by_name = excluded.set_by_name, set_at = now();
  insert into change_log (text, by_user) values ('Supplement lists: ' || jsonb_array_length(u) || ' user fields, ' || jsonb_array_length(c) || ' categories', me);
  return jsonb_build_object('uf', u, 'cats', c);
end $$;
revoke execute on function supp_lists_set(jsonb) from public, anon;
grant execute on function supp_lists_set(jsonb) to authenticated;

-- ------------------------------------------------------------------ 3. the checks on a row (the app's suppNormalize and suppCheck)
-- x: a row as the file or the screen gives it; returns {row: the stored row, error: text or null}
create or replace function pt_supp_row(x jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l jsonb := pt_supp_lists(); ufs text[]; cats text[]; uf text; cat text; uni text; t text; e text; n jsonb;
        tx text[] := array['description','wbs_group','wbs_id','wbs_description','linked_ref','remarks'];
begin
  select array_agg(v ->> 0 order by o) into ufs from jsonb_array_elements(l -> 'uf') with ordinality a(v, o);
  select array_agg(v ->> 0 order by o) into cats from jsonb_array_elements(l -> 'cats') with ordinality a(v, o);
  uf := pt_supp_pick(ufs, x ->> 'user_field'); cat := pt_supp_pick(cats, x ->> 'category');
  if cat is not null then select v ->> 1 into uni from jsonb_array_elements(l -> 'cats') v where v ->> 0 = cat limit 1; end if;
  n := jsonb_build_object('supp_no', upper(btrim(coalesce(x ->> 'supp_no', ''))), 'user_field', uf, 'category', cat, 'unified_category', uni, 'approval_status', 'Approved');
  foreach t in array tx loop n := n || jsonb_build_object(t, nullif(btrim(regexp_replace(coalesce(x ->> t, ''), '\s+', ' ', 'g')), '')); end loop;
  if btrim(coalesce(x ->> 'user_field', '')) <> '' and uf is null then e := format('user field "%s" is not in the list', btrim(x ->> 'user_field'));
  elsif btrim(coalesce(x ->> 'category', '')) <> '' and cat is null then e := format('category "%s" is not in the list', btrim(x ->> 'category'));
  elsif nullif(btrim(coalesce(x ->> 'supp_date', '')), '') is not null and pt_bad_date(x ->> 'supp_date') then e := 'the WF date is not a valid date';
  elsif n ->> 'supp_no' = '' then e := 'supplement number missing';
  elsif length(n ->> 'supp_no') > 40 then e := 'the supplement number is longer than 40 characters';
  elsif nullif(btrim(coalesce(x ->> 'supp_date', '')), '') is null then e := 'the WF date is missing';
  elsif pt_date(x ->> 'supp_date') > current_date then e := 'the WF date is in the future';
  elsif uf is null then e := 'the user field must be one of the list (Settings → Supplement lists)';
  elsif cat is null then e := 'the category must be one of the list (Settings → Supplement lists)';
  elsif pt_num(x ->> 'amount') is null then e := 'the amount is missing or not a number';
  elsif length(coalesce(n ->> 'wbs_group', '')) > 100 or length(coalesce(n ->> 'wbs_id', '')) > 100 then e := 'a WBS group or WBS ID is longer than 100 characters';
  elsif length(coalesce(n ->> 'description', '')) > 2000 or length(coalesce(n ->> 'wbs_description', '')) > 2000 or length(coalesce(n ->> 'remarks', '')) > 2000 then e := 'a text is longer than 2,000 characters';
  elsif length(coalesce(n ->> 'linked_ref', '')) > 60 then e := 'the linked VO or claim is longer than 60 characters';
  end if;
  n := n || jsonb_build_object('supp_date', case when e is null then pt_date(x ->> 'supp_date') end, 'amount', pt_num(x ->> 'amount'));
  return jsonb_build_object('row', n, 'error', e);
end $$;

-- ------------------------------------------------------------------ 4. the cost report's budget change from the log
create or replace function pt_supp_approved(pid text, per text) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(case when s.user_field is null then case when lower(coalesce(s.approval_status, '')) = 'approved' then s.amount else 0 end
                           when s.user_field = 'Cont. Value' then 0
                           else -s.amount end), 0)
    from budget_supplements s
   where s.batch_id = (select b.id from import_batches b where b.project_id = pid and b.kind = 'supplements' and b.status = 'committed'
                         and coalesce(b.source_period, '') <= per order by b.source_period desc, b.at_time desc limit 1) $$;

-- ------------------------------------------------------------------ 5. uploading a month's log: the supplements branch checks the new columns
create or replace function log_import(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r text := role_of(auth.uid()); k text := p ->> 'kind'; pid text := p ->> 'project_id'; per text := p ->> 'period';
        rows jsonb := coalesce(p -> 'rows', '[]'::jsonb); x jsonb; acc jsonb := '[]'::jsonb; rej jsonb := '[]'::jsonb; err text; ref text;
        seen text[] := '{}'; bid uuid; last uuid; tot numeric := 0; i int := 0; ipt text; sr jsonb;
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
      -- v35: every row is a supplement approved by its WF, with its user field, category, WBS and signed amount
      sr := pt_supp_row(x); err := sr ->> 'error';
      if err is null then x := sr -> 'row'; end if;
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
    insert into budget_supplements (batch_id, project_id, period, supp_no, supp_date, description, amount, category, linked_ref, approval_status, remarks,
                                    user_field, unified_category, wbs_group, wbs_id, wbs_description)
    select bid, pid, per, y ->> '_ref', pt_date(y ->> 'supp_date'), y ->> 'description', pt_num(y ->> 'amount'), y ->> 'category',
           y ->> 'linked_ref', 'Approved', y ->> 'remarks', y ->> 'user_field', y ->> 'unified_category', y ->> 'wbs_group', y ->> 'wbs_id', y ->> 'wbs_description'
      from jsonb_array_elements(acc) y;
  end if;
  return jsonb_build_object('duplicate', false, 'batch_id', bid, 'accepted', jsonb_array_length(acc), 'rejected', rej, 'total', tot);
end $$;
revoke execute on function log_import(jsonb) from public, anon;
grant execute on function log_import(jsonb) to authenticated;

-- ------------------------------------------------------------------ 6. changing the latest log on the screen, with its history
create table if not exists supp_audit (
  id bigserial primary key,
  row_id bigint, project_id text not null references projects(id) on delete cascade, supp_no text, period text,
  action text not null, changes jsonb not null default '[]'::jsonb, before jsonb, reason text,
  by_user uuid references profiles(id), by_name text, at timestamptz not null default now());
create index if not exists sua_proj on supp_audit (project_id, id desc);
drop trigger if exists trg_sua_append on supp_audit;
create trigger trg_sua_append before update or delete on supp_audit for each row execute function pt_append_only();
drop trigger if exists trg_sua_truncate on supp_audit;
create trigger trg_sua_truncate before truncate on supp_audit execute function pt_no_truncate();
alter table supp_audit enable row level security;
drop policy if exists sua_read on supp_audit;
create policy sua_read on supp_audit for select using (can_see(project_id) and pt_money_ok());
grant select on supp_audit to authenticated;

-- budget_supplements stays append-only, except the changes supp_update makes to the latest log
create or replace function pt_bsu_guard() returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('protrack.supp_update', true), '') = 'on' then return case when tg_op = 'DELETE' then old else new end; end if;
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end $$;
drop trigger if exists trg_bsu_append on budget_supplements;
drop trigger if exists trg_bsu_guard on budget_supplements;
create trigger trg_bsu_guard before update or delete on budget_supplements for each row execute function pt_bsu_guard();

-- p: {action: 'version' | 'add' | 'edit' | 'remove', project_id, period (version), id (edit, remove), values (add, edit), reason (remove)};
-- the app's suppActLocal()
create or replace function supp_update(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); a text := p ->> 'action'; pid text := p ->> 'project_id'; lb import_batches; r budget_supplements; sr jsonb; n jsonb;
        per text; nb uuid; ch jsonb := '[]'::jsonb; why text; fld text; ro jsonb; nid bigint; cnt int; tot numeric;
        f text[] := array['supp_no','supp_date','user_field','category','description','amount','wbs_group','wbs_id','wbs_description','linked_ref','remarks'];
begin
  if me is null or role_of(me) is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if pid is null or not exists (select 1 from projects where id = pid) then raise exception 'Unknown project'; end if;
  if not pt_right(me, 'logs.upload', pt_is_coord(me)) then raise exception 'Only the costing engineer or costing coordinator changes the log' using errcode = '42501'; end if;
  if not user_sees(me, pid) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtext('protrack:log:' || pid || ':supplements'));
  select * into lb from import_batches where project_id = pid and kind = 'supplements' and status = 'committed' order by source_period desc, at_time desc limit 1;
  if a = 'version' then
    per := p ->> 'period';
    if not pt_period_ok(per, 'month') then raise exception 'The version must be a month such as 2026-09'; end if;
    if per > to_char(current_date, 'YYYY-MM') then raise exception 'The version cannot be after the current month'; end if;
    if lb.id is not null and lb.source_period >= per then raise exception 'The latest log is already %', lb.source_period; end if;
    select count(*), coalesce(sum(amount), 0) into cnt, tot from budget_supplements where batch_id = lb.id;
    insert into import_batches (project_id, kind, file_name, file_hash, source_period, rows_total, rows_accepted, rows_rejected, total_source, total_accepted, recon_status, detail, by_user)
    values (pid, 'supplements', case when lb.id is null then 'Started on screen' else 'Copy of the ' || lb.source_period || ' log (on screen)' end,
            'screen-' || gen_random_uuid()::text, per, cnt, cnt, 0, tot, tot, 'Matched', jsonb_build_object('copied_from', lb.id), me)
    returning id into nb;
    insert into budget_supplements (batch_id, project_id, period, supp_no, supp_date, description, amount, category, linked_ref, approval_status, remarks,
                                    user_field, unified_category, wbs_group, wbs_id, wbs_description)
    select nb, pid, per, supp_no, supp_date, description, amount, category, linked_ref, approval_status, remarks, user_field, unified_category, wbs_group, wbs_id, wbs_description
      from budget_supplements where batch_id = lb.id;
    insert into change_log (text, by_user) values ((select short from projects where id = pid) || ': budget supplement log, version ' || per || ' started', me);
    return jsonb_build_object('batch_id', nb, 'period', per);
  end if;
  if lb.id is null then raise exception 'This project has no supplement log yet: upload one first'; end if;
  if a = 'remove' then
    select * into r from budget_supplements where id = pt_num(p ->> 'id')::bigint and batch_id = lb.id;
    if r.id is null then raise exception 'That row is not in the latest log'; end if;
    why := btrim(coalesce(p ->> 'reason', ''));
    if length(why) < 5 then raise exception 'Give the reason for removing it'; end if;
    perform set_config('protrack.supp_update', 'on', true);
    delete from budget_supplements where id = r.id;
    perform set_config('protrack.supp_update', '', true);
    insert into supp_audit (row_id, project_id, supp_no, period, action, before, reason, by_user, by_name) values (r.id, pid, r.supp_no, r.period, 'removed', to_jsonb(r), left(why, 300), me, name_of(me));
    insert into change_log (text, by_user) values ((select short from projects where id = pid) || ': budget supplement ' || r.supp_no || ' removed (' || left(why, 200) || ')', me);
    return jsonb_build_object('removed', r.id);
  end if;
  if a not in ('add', 'edit') then raise exception 'Unknown action'; end if;
  sr := pt_supp_row(coalesce(p -> 'values', '{}'::jsonb));
  if sr ->> 'error' is not null then raise exception '%', upper(left(sr ->> 'error', 1)) || substr(sr ->> 'error', 2); end if;
  n := sr -> 'row';
  if exists (select 1 from budget_supplements where batch_id = lb.id and supp_no = n ->> 'supp_no' and id is distinct from pt_num(p ->> 'id')::bigint) then
    raise exception '% is already in the log', n ->> 'supp_no'; end if;
  if a = 'add' then
    insert into budget_supplements (batch_id, project_id, period, supp_no, supp_date, description, amount, category, linked_ref, approval_status, remarks,
                                    user_field, unified_category, wbs_group, wbs_id, wbs_description)
    values (lb.id, pid, lb.source_period, n ->> 'supp_no', pt_date(n ->> 'supp_date'), n ->> 'description', pt_num(n ->> 'amount'), n ->> 'category', n ->> 'linked_ref', 'Approved',
            n ->> 'remarks', n ->> 'user_field', n ->> 'unified_category', n ->> 'wbs_group', n ->> 'wbs_id', n ->> 'wbs_description')
    returning id into nid;
    insert into supp_audit (row_id, project_id, supp_no, period, action, changes, by_user, by_name)
    values (nid, pid, n ->> 'supp_no', lb.source_period, 'added', jsonb_build_array(jsonb_build_array('amount', null, n -> 'amount')), me, name_of(me));
    insert into change_log (text, by_user) values ((select short from projects where id = pid) || ': budget supplement ' || (n ->> 'supp_no') || ' added', me);
    return jsonb_build_object('row', (select to_jsonb(s) from budget_supplements s where id = nid));
  end if;
  select * into r from budget_supplements where id = pt_num(p ->> 'id')::bigint and batch_id = lb.id;
  if r.id is null then raise exception 'That row is not in the latest log'; end if;
  if r.user_field is null then raise exception 'A row logged before v3.29 is changed by uploading the log again'; end if;
  ro := to_jsonb(r);
  foreach fld in array f loop
    if (ro ->> fld) is distinct from (n ->> fld) then ch := ch || jsonb_build_array(jsonb_build_array(fld, ro -> fld, n -> fld)); end if;
  end loop;
  if jsonb_array_length(ch) = 0 then return jsonb_build_object('changed', false, 'row', ro); end if;
  perform set_config('protrack.supp_update', 'on', true);
  update budget_supplements set supp_no = n ->> 'supp_no', supp_date = pt_date(n ->> 'supp_date'), description = n ->> 'description', amount = pt_num(n ->> 'amount'),
         category = n ->> 'category', unified_category = n ->> 'unified_category', user_field = n ->> 'user_field', linked_ref = n ->> 'linked_ref',
         remarks = n ->> 'remarks', wbs_group = n ->> 'wbs_group', wbs_id = n ->> 'wbs_id', wbs_description = n ->> 'wbs_description'
   where id = r.id;
  perform set_config('protrack.supp_update', '', true);
  insert into supp_audit (row_id, project_id, supp_no, period, action, changes, before, by_user, by_name) values (r.id, pid, n ->> 'supp_no', r.period, 'changed', ch, ro, me, name_of(me));
  insert into change_log (text, by_user) values ((select short from projects where id = pid) || ': budget supplement ' || (n ->> 'supp_no') || ' changed', me);
  return jsonb_build_object('changed', true, 'row', (select to_jsonb(s) from budget_supplements s where id = r.id));
end $$;
revoke execute on function supp_update(jsonb), pt_supp_row(jsonb), pt_supp_lists(), pt_supp_default(), pt_supp_pick(text[], text) from public, anon;
grant execute on function supp_update(jsonb), pt_supp_lists() to authenticated;

-- ------------------------------------------------------------------ 7. what the app checks for
create or replace function supp_features() returns jsonb language sql immutable as $$ select '{"version":35,"supplement_log":true}'::jsonb $$;
grant execute on function supp_features() to authenticated;
