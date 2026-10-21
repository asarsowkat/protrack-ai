-- ProTrack schema update v36 (ProTrackAI v3.31): a version on each row of the budget supplement log.
-- The version of a row is the month the supplement applies to (MMM-YY on the screen, 2026-09 here), whatever its WF date:
-- a WF approved in SAP on 5 October whose values management approved in September is in the September version. The log of a
-- project is the latest one; the cost report's budget change for a month counts its rows whose version is up to that month,
-- so a supplement entered late still counts in its own month. An upload is the whole log as of its month: each row keeps its
-- version (blank: the month of the upload), none after it, and no upload for a month before the latest log.
-- Existing rows get the first month their supplement number appears in the logs of their project.
-- Needs the v35 update (STAGE-29-SETUP). Additive: nothing is deleted. Safe to run twice. Undo: schema-rollback-v36.sql.

-- ------------------------------------------------------------------ 1. the column, and the version of the rows already logged
alter table budget_supplements add column if not exists version text;
do $v36$ begin
  perform set_config('protrack.supp_update', 'on', true);
  update budget_supplements s set version = f.first
    from (select project_id, supp_no, min(period) as first from budget_supplements group by project_id, supp_no) f
   where s.version is null and f.project_id = s.project_id and f.supp_no is not distinct from s.supp_no;
  perform set_config('protrack.supp_update', '', true);
end $v36$;

-- ------------------------------------------------------------------ 2. the checks on a row: its version
create or replace function pt_supp_row(x jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l jsonb := pt_supp_lists(); ufs text[]; cats text[]; uf text; cat text; uni text; t text; e text; n jsonb;
        ver text := nullif(btrim(coalesce(x ->> 'version', '')), '');
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
  elsif ver is not null and not pt_period_ok(ver, 'month') then e := 'the version is not a month (use MMM-YY, for example Aug-26)';
  elsif ver > to_char(current_date, 'YYYY-MM') then e := 'the version is after this month';
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
  n := n || jsonb_build_object('supp_date', case when e is null then pt_date(x ->> 'supp_date') end, 'amount', pt_num(x ->> 'amount'), 'version', ver);
  return jsonb_build_object('row', n, 'error', e);
end $$;

-- ------------------------------------------------------------------ 3. the cost report's budget change: the rows up to the month
create or replace function pt_supp_approved(pid text, per text) returns numeric language sql stable security definer set search_path = public as $$
  with lb as (select b.id from import_batches b where b.project_id = pid and b.kind = 'supplements' and b.status = 'committed'
               order by b.source_period desc, b.at_time desc limit 1)
  select case when exists (select 1 from budget_supplements s where s.batch_id = (select id from lb) and s.user_field is not null) then
    (select coalesce(sum(case when s.user_field is null then case when lower(coalesce(s.approval_status, '')) = 'approved' then s.amount else 0 end
                             when s.user_field = 'Cont. Value' then 0
                             else -s.amount end), 0)
       from budget_supplements s where s.batch_id = (select id from lb) and coalesce(s.version, s.period) <= per)
  else
    (select coalesce(sum(case when lower(coalesce(s.approval_status, '')) = 'approved' then s.amount else 0 end), 0)
       from budget_supplements s
      where s.batch_id = (select b.id from import_batches b where b.project_id = pid and b.kind = 'supplements' and b.status = 'committed'
                            and coalesce(b.source_period, '') <= per order by b.source_period desc, b.at_time desc limit 1))
  end $$;

-- ------------------------------------------------------------------ 4. uploading: each row keeps its version
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
  if k = 'supplements' and exists (select 1 from import_batches where project_id = pid and kind = 'supplements' and status = 'committed' and source_period > per) then
    raise exception 'The latest log of this project is after %: upload for that month or later, and give each row its version', per; end if;
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
      if err is null and (sr -> 'row' ->> 'version') > per then err := 'the version ' || (sr -> 'row' ->> 'version') || ' is after the month of this upload'; end if;
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
                                    user_field, unified_category, wbs_group, wbs_id, wbs_description, version)
    select bid, pid, per, y ->> '_ref', pt_date(y ->> 'supp_date'), y ->> 'description', pt_num(y ->> 'amount'), y ->> 'category',
           y ->> 'linked_ref', 'Approved', y ->> 'remarks', y ->> 'user_field', y ->> 'unified_category', y ->> 'wbs_group', y ->> 'wbs_id', y ->> 'wbs_description',
           coalesce(y ->> 'version', per)
      from jsonb_array_elements(acc) y;
  end if;
  return jsonb_build_object('duplicate', false, 'batch_id', bid, 'accepted', jsonb_array_length(acc), 'rejected', rej, 'total', tot);
end $$;
revoke execute on function log_import(jsonb) from public, anon;
grant execute on function log_import(jsonb) to authenticated;

-- ------------------------------------------------------------------ 5. changes on the screen: the version like the other fields
-- p: {action: 'version' | 'add' | 'edit' | 'remove', project_id, period (version), id (edit, remove), values (add, edit), reason (remove)};
-- the app's suppActLocal()
create or replace function supp_update(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); a text := p ->> 'action'; pid text := p ->> 'project_id'; lb import_batches; r budget_supplements; sr jsonb; n jsonb;
        per text; nb uuid; ch jsonb := '[]'::jsonb; why text; fld text; ro jsonb; nid bigint; cnt int; tot numeric;
        f text[] := array['version','supp_no','supp_date','user_field','category','description','amount','wbs_group','wbs_id','wbs_description','linked_ref','remarks'];
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
                                    user_field, unified_category, wbs_group, wbs_id, wbs_description, version)
    select nb, pid, per, supp_no, supp_date, description, amount, category, linked_ref, approval_status, remarks, user_field, unified_category, wbs_group, wbs_id, wbs_description,
           coalesce(version, period)
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
  if n ->> 'version' is null then n := n || jsonb_build_object('version', coalesce((select coalesce(version, period) from budget_supplements where id = pt_num(p ->> 'id')::bigint and batch_id = lb.id), lb.source_period)); end if;
  if exists (select 1 from budget_supplements where batch_id = lb.id and supp_no = n ->> 'supp_no' and id is distinct from pt_num(p ->> 'id')::bigint) then
    raise exception '% is already in the log', n ->> 'supp_no'; end if;
  if a = 'add' then
    insert into budget_supplements (batch_id, project_id, period, supp_no, supp_date, description, amount, category, linked_ref, approval_status, remarks,
                                    user_field, unified_category, wbs_group, wbs_id, wbs_description, version)
    values (lb.id, pid, lb.source_period, n ->> 'supp_no', pt_date(n ->> 'supp_date'), n ->> 'description', pt_num(n ->> 'amount'), n ->> 'category', n ->> 'linked_ref', 'Approved',
            n ->> 'remarks', n ->> 'user_field', n ->> 'unified_category', n ->> 'wbs_group', n ->> 'wbs_id', n ->> 'wbs_description', n ->> 'version')
    returning id into nid;
    insert into supp_audit (row_id, project_id, supp_no, period, action, changes, by_user, by_name)
    values (nid, pid, n ->> 'supp_no', lb.source_period, 'added', jsonb_build_array(jsonb_build_array('amount', null, n -> 'amount')), me, name_of(me));
    insert into change_log (text, by_user) values ((select short from projects where id = pid) || ': budget supplement ' || (n ->> 'supp_no') || ' added', me);
    return jsonb_build_object('row', (select to_jsonb(s) from budget_supplements s where id = nid));
  end if;
  select * into r from budget_supplements where id = pt_num(p ->> 'id')::bigint and batch_id = lb.id;
  if r.id is null then raise exception 'That row is not in the latest log'; end if;
  if r.user_field is null then raise exception 'A row logged before v3.29 is changed by uploading the log again'; end if;
  ro := to_jsonb(r) || jsonb_build_object('version', coalesce(r.version, r.period));
  foreach fld in array f loop
    if (ro ->> fld) is distinct from (n ->> fld) then ch := ch || jsonb_build_array(jsonb_build_array(fld, ro -> fld, n -> fld)); end if;
  end loop;
  if jsonb_array_length(ch) = 0 then return jsonb_build_object('changed', false, 'row', ro); end if;
  perform set_config('protrack.supp_update', 'on', true);
  update budget_supplements set supp_no = n ->> 'supp_no', supp_date = pt_date(n ->> 'supp_date'), description = n ->> 'description', amount = pt_num(n ->> 'amount'),
         category = n ->> 'category', unified_category = n ->> 'unified_category', user_field = n ->> 'user_field', linked_ref = n ->> 'linked_ref',
         remarks = n ->> 'remarks', wbs_group = n ->> 'wbs_group', wbs_id = n ->> 'wbs_id', wbs_description = n ->> 'wbs_description', version = n ->> 'version'
   where id = r.id;
  perform set_config('protrack.supp_update', '', true);
  insert into supp_audit (row_id, project_id, supp_no, period, action, changes, before, by_user, by_name) values (r.id, pid, n ->> 'supp_no', r.period, 'changed', ch, ro, me, name_of(me));
  insert into change_log (text, by_user) values ((select short from projects where id = pid) || ': budget supplement ' || (n ->> 'supp_no') || ' changed', me);
  return jsonb_build_object('changed', true, 'row', (select to_jsonb(s) from budget_supplements s where id = r.id));
end $$;
revoke execute on function supp_update(jsonb), pt_supp_row(jsonb), pt_supp_lists(), pt_supp_default(), pt_supp_pick(text[], text) from public, anon;
grant execute on function supp_update(jsonb), pt_supp_lists() to authenticated;

-- ------------------------------------------------------------------ 6. what the app checks for
create or replace function supp_features() returns jsonb language sql immutable as $$ select '{"version":36,"supplement_log":true,"row_version":true}'::jsonb $$;
grant execute on function supp_features() to authenticated;
