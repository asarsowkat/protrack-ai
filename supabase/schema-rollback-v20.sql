-- ProTrack schema rollback v20: back to the v3.10 server rules (schema-update-v18.sql).
-- Uploads no longer store the four new columns or check their rules, a row of the change order and claim log can no
-- longer be updated (co_log is fully append-only again), and approving a report no longer saves its contract breakdown:
-- the app works it out from the log again and switches Update off. Everything is kept: the columns client_price,
-- internal_price, wf_no, wf_date and contract_snapshot with their values, and the table co_log_updates with its history.
-- Released reports keep the breakdown saved with them, and it still cannot be changed. Run schema-update-v20.sql again to
-- use them again. Safe to run twice.

-- co_log: append-only again
-- v3.28.2: safe to run even if schema-update-v20.sql was never applied (the table co_log_updates is not on the database): then it changes
-- nothing and its result says so. Otherwise it runs the rollback below, unchanged. The result is one row.

do $pt_rollback$
declare applied boolean := to_regclass('public.co_log_updates') is not null;
begin
  if not applied then
    perform set_config('protrack.rollback', 'schema-update-v20.sql is not on this database (never run, or already undone): nothing to undo, nothing was changed.', false);
    return;
  end if;
  execute $pt_rollback_body$
drop trigger if exists trg_col_guard on co_log;
drop trigger if exists trg_col_append on co_log;
create trigger trg_col_append before update or delete on co_log for each row execute function pt_append_only();
drop function if exists vo_update(jsonb);
revoke all on co_log_updates from authenticated, anon;

-- releases: the breakdown is no longer worked out, but a released version keeps the one it has
create or replace function pt_release_contract() returns trigger language plpgsql as $$
begin
  if old.status in ('Released','Superseded') and new.contract_snapshot is distinct from old.contract_snapshot then
    raise exception 'A released version cannot be changed; issue a new revision' using errcode = '42501'; end if;
  return new;
end $$;
drop trigger if exists trg_rr_contract on report_releases;
create trigger trg_rr_contract before update on report_releases for each row execute function pt_release_contract();

-- log_import: as in schema-update-v16.sql
create or replace function log_import(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r text := role_of(auth.uid()); k text := p ->> 'kind'; pid text := p ->> 'project_id'; per text := p ->> 'period';
        rows jsonb := coalesce(p -> 'rows', '[]'::jsonb); x jsonb; acc jsonb := '[]'::jsonb; rej jsonb := '[]'::jsonb; err text; ref text;
        seen text[] := '{}'; bid uuid; last uuid; tot numeric := 0; i int := 0;
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
      if coalesce(x ->> 'kind', '') not in ('VO','Claim') then err := 'type must be VO or Claim';
      elsif pt_bad_num(x ->> 'est_price') or pt_bad_num(x ->> 'est_cost') or pt_bad_num(x ->> 'expected_price') or pt_bad_num(x ->> 'rev0_change') then err := 'a price or cost is not a number';
      elsif pt_bad_date(x ->> 'submitted_on') then err := 'the submission date is not a valid date';
      end if;
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
                        expected_price, price_internal, cost_internal, rev0_change, internal_wf, overall_status, remarks)
    select bid, pid, per, y ->> '_ref', y ->> 'kind', left(y ->> 'description', 2000), y ->> 'submission_status', pt_date(y ->> 'submitted_on'), y ->> 'client_status',
           pt_num(y ->> 'est_price'), pt_num(y ->> 'est_cost'), pt_num(y ->> 'expected_price'), y ->> 'price_internal', y ->> 'cost_internal',
           pt_num(y ->> 'rev0_change'), y ->> 'internal_wf', y ->> 'overall_status', left(y ->> 'remarks', 2000)
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
  perform set_config('protrack.rollback', 'schema-update-v20.sql undone.', false);
end $pt_rollback$;
select current_setting('protrack.rollback', true) as result;
