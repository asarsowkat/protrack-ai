-- ProTrack schema rollback v35 (ProTrackAI v3.29): undo schema-update-v35.sql.
-- Uploads go back to the v3.0 layout of the budget supplement log (seven categories, an approval status), changes on the
-- screen and the lists stop, and the cost report adds the approved amounts of the latest log again. Everything is kept:
-- the columns user_field, unified_category, wbs_group, wbs_id and wbs_description with their values, the lists (supp_lists)
-- and the history (supp_audit). The check on the seven categories is not put back, because rows with the new categories
-- stay. Rows logged in the new layout then count as in v3.0: their amounts are added as they stand (a supplement is
-- negative), as an app before v3.29 also adds them. Run schema-update-v35.sql again to use them again.
-- Safe to run even if schema-update-v35.sql was never applied (the table supp_audit is not on the database): then it changes
-- nothing and its result says so. Otherwise it runs the rollback below. The result is one row.

do $pt_rollback$
declare applied boolean := to_regclass('public.supp_audit') is not null;
begin
  if not applied then
    perform set_config('protrack.rollback', 'schema-update-v35.sql is not on this database (never run, or already undone): nothing to undo, nothing was changed.', false);
    return;
  end if;
  execute $pt_rollback_body$
-- the screen changes stop: supp_update, supp_lists_set and supp_features go; the lists and the history stay, unread
drop function if exists supp_update(jsonb);
drop function if exists supp_lists_set(jsonb);
drop function if exists supp_features();
revoke select on supp_lists, supp_audit from authenticated;

-- budget_supplements append-only again
drop trigger if exists trg_bsu_guard on budget_supplements;
drop function if exists pt_bsu_guard();
drop trigger if exists trg_bsu_append on budget_supplements;
create trigger trg_bsu_append before update or delete on budget_supplements for each row execute function pt_append_only();

-- the cost report adds the approved amounts of the latest log again (schema-update-v9.sql)
create or replace function pt_supp_approved(pid text, per text) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(s.amount), 0) from budget_supplements s
   where s.batch_id = (select b.id from import_batches b where b.project_id = pid and b.kind = 'supplements' and b.status = 'committed'
                         and coalesce(b.source_period, '') <= per order by b.source_period desc, b.at_time desc limit 1)
     and lower(coalesce(s.approval_status, '')) = 'approved' $$;

-- log_import as in schema-update-v20.sql (the seven categories of v3.0; the new columns are no longer filled)
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
revoke execute on function log_import(jsonb) from public, anon;
grant execute on function log_import(jsonb) to authenticated;
$pt_rollback_body$;
  perform set_config('protrack.rollback', 'schema-update-v35.sql undone.', false);
end $pt_rollback$;
select current_setting('protrack.rollback', true) as result;
