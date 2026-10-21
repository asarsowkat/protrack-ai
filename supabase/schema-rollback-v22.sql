-- ProTrack schema rollback v22: back to the v3.13 server rules for reports, updated schedules, invoices and payment terms.
-- release_act_bl() and bl_cash_features() are removed, so live.html goes back to keeping the baseline choice and the
-- comparison, the schedule's own baseline, the invoice phase and actual dates in the browser only, as before v22.
-- schedule_update_commit is restored from schema-update-v17.sql and import_invoices from schema-update-v5.sql; the
-- payment-period check on the projects is removed.
-- Everything is kept: the columns bl_src, xbs, xbf, phase, sub_date, appr_date and coll_date with their values, every
-- saved comparison in the released reports, and pay.days in the payment terms. Run schema-update-v22.sql again to use
-- them again. Safe to run twice.
-- v3.28.2: safe to run even if schema-update-v22.sql was never applied (the column schedule_updates.bl_src is not on the database): then it changes
-- nothing and its result says so. Otherwise it runs the rollback below, unchanged. The result is one row.

do $pt_rollback$
declare applied boolean := exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'schedule_updates' and column_name = 'bl_src');
begin
  if not applied then
    perform set_config('protrack.rollback', 'schema-update-v22.sql is not on this database (never run, or already undone): nothing to undo, nothing was changed.', false);
    return;
  end if;
  execute $pt_rollback_body$
drop function if exists bl_cash_features();
drop function if exists release_act_bl(jsonb);
drop function if exists pt_bl_cmp(jsonb, jsonb, numeric, date);
drop function if exists pt_bl_name(text);
drop function if exists pt_bl_keys();
drop trigger if exists trg_proj_billing on projects;
drop function if exists pt_proj_billing();

-- schedule_update_commit: as in schema-update-v17.sql
create or replace function schedule_update_commit(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); pid text := p ->> 'project_id'; dd date; wt text := coalesce(p ->> 'weightage', 'client');
        rows jsonb := p -> 'rows'; st project_phase_setup; uid uuid := uuid_generate_v4(); x jsonb; nr int; ex schedule_updates;
        s jsonb; ph text; bs date; bf date; v numeric; nunm int;
begin
  if me is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if pid is null or not user_sees(me, pid) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
  if (select status from projects where id = pid) = 'Cancelled' then raise exception 'This project was cancelled' using errcode = '42501'; end if;
  if not pt_sched_keeper(me, pid) then raise exception 'Only a planning engineer of this project or a super admin uploads updated schedules' using errcode = '42501'; end if;
  if wt not in ('client','internal') then raise exception 'Say whether the schedule is loaded with client or internal weightage'; end if;
  if pt_bad_date(p ->> 'data_date') or pt_date(p ->> 'data_date') is null then raise exception 'The schedule needs a valid data date'; end if;
  dd := pt_date(p ->> 'data_date');
  if dd > current_date + 31 then raise exception 'The data date is more than a month in the future'; end if;
  if jsonb_typeof(rows) <> 'array' then raise exception 'No activities were sent'; end if;
  nr := jsonb_array_length(rows);
  if nr = 0 then raise exception 'The schedule has no activities'; end if;
  if nr > 30000 then raise exception 'The schedule has more than 30,000 activities'; end if;
  if length(coalesce(p ->> 'file_hash', '')) > 128 or length(coalesce(p ->> 'file_name', '')) > 300 then raise exception 'The file details are too long'; end if;
  perform pg_advisory_xact_lock(hashtext('protrack:sched:' || pid));
  if nullif(p ->> 'file_hash', '') is not null then
    select * into ex from schedule_updates where project_id = pid and file_hash = p ->> 'file_hash';
    if ex.id is not null then return to_jsonb(ex) || jsonb_build_object('duplicate', true); end if;
  end if;
  select * into st from project_phase_setup where project_id = pid;
  for x in select * from jsonb_array_elements(rows) loop
    if nullif(btrim(coalesce(x ->> 'id', '')), '') is null or length(x ->> 'id') > 60 then raise exception 'Every activity needs an ID of up to 60 characters'; end if;
    if pt_bad_num(x ->> 'w') or coalesce(pt_num(x ->> 'w'), 0) < 0 then raise exception 'Activity %: the weight must be a number, not negative', x ->> 'id'; end if;
    v := coalesce(pt_num(x ->> 'pct'), 0);
    if pt_bad_num(x ->> 'pct') or v < 0 or v > 100 then raise exception 'Activity %: %% complete must be between 0 and 100', x ->> 'id'; end if;
    if pt_bad_date(x ->> 'bs') or pt_bad_date(x ->> 'bf') or pt_bad_date(x ->> 'as') or pt_bad_date(x ->> 'af') or pt_bad_date(x ->> 'ef') then
      raise exception 'Activity %: a date is not valid', x ->> 'id'; end if;
    ph := coalesce(nullif(st.code_map ->> nullif(x ->> 'code', ''), ''), nullif(st.wbs_map ->> nullif(x ->> 'wbs', ''), ''));
    -- planned dates: the ProTrackAI baseline when the activity is in it, otherwise the schedule's planned dates
    select a.bs, a.bf into bs, bf from activities a where a.project_id = pid and a.id = btrim(x ->> 'id');
    bs := coalesce(bs, pt_date(x ->> 'bs')); bf := coalesce(bf, pt_date(x ->> 'bf'));
    if coalesce(pt_num(x ->> 'w'), 0) > 0 and (bs is null or bf is null) then raise exception 'Activity %: planned start and finish are needed', x ->> 'id'; end if;
    insert into schedule_update_rows (update_id, project_id, act_id, name, wbs, code, phase, w, bs, bf, pct, ms, as_d, af, ef, es, mat, uact, wbs_leaf)
    values (uid, pid, btrim(x ->> 'id'), left(x ->> 'name', 300), left(x ->> 'wbs', 200), left(x ->> 'code', 200), ph, coalesce(pt_num(x ->> 'w'), 0), bs, bf, v,
            coalesce((x ->> 'ms')::boolean, false), pt_date(x ->> 'as'), pt_date(x ->> 'af'), pt_date(x ->> 'ef'),
            pt_date(x ->> 'es'), nullif(left(btrim(coalesce(x ->> 'mat', '')), 120), ''), nullif(left(btrim(coalesce(x ->> 'uact', '')), 120), ''), left(x ->> 'wbs_leaf', 200))
    on conflict (update_id, act_id) do nothing;
  end loop;
  select count(*) into nunm from schedule_update_rows where update_id = uid and phase is null and w > 0;
  if nunm > 0 and wt = 'client' and exists (select 1 from jsonb_each_text(coalesce(st.weights, '{}'::jsonb)) e where pt_num(e.value) > 0) then
    raise exception '% weighted activities have no phase. Map every main WBS branch (or activity code value) to a phase first', nunm; end if;
  if not exists (select 1 from schedule_update_rows where update_id = uid and w > 0) then raise exception 'No activity in the schedule carries a weight'; end if;
  s := pt_sched_summary(uid, dd, wt, coalesce(st.weights, '{}'::jsonb));
  insert into schedule_updates (id, project_id, data_date, weightage, file_name, file_hash, weight_basis, weights, summary, uploaded_by, uploaded_name)
  values (uid, pid, dd, wt, left(p ->> 'file_name', 300), nullif(p ->> 'file_hash', ''), left(p ->> 'weight_basis', 200), coalesce(st.weights, '{}'::jsonb), s, me, name_of(me));
  return (select to_jsonb(u) from schedule_updates u where u.id = uid);
end $$;

-- import_invoices: as in schema-update-v5.sql
create or replace function import_invoices(p_project text, p_file text, p_hash text, p_rows jsonb, p_period text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); seen uuid; acc jsonb; rej jsonb; bid uuid; n_all int;
begin
  if me is null or not can_cost(p_project) then raise exception 'Only costing engineers, project managers and super admins of this project can load invoices' using errcode = '42501'; end if;
  if p_hash is null or length(p_hash) < 16 then raise exception 'A file hash is required'; end if;
  seen := pt_batch_seen(p_project, 'invoices', p_hash);
  if seen is not null then return jsonb_build_object('duplicate', true, 'batch_id', seen); end if;
  n_all := jsonb_array_length(p_rows);
  with r as (select x, btrim(coalesce(x ->> 'no', '')) no_, coalesce(pt_num(x ->> 'sub'), 0) sub, coalesce(pt_num(x ->> 'amount'), 0) amount,
                    coalesce(pt_num(x ->> 'appr'), 0) appr, coalesce(pt_num(x ->> 'coll'), 0) coll,
                    count(*) over (partition by lower(btrim(coalesce(x ->> 'no', '')))) dup
               from jsonb_array_elements(p_rows) x),
       c as (select *, case when coalesce(x ->> 'client_error', '') <> '' then left(x ->> 'client_error', 200)
                            when no_ = '' then 'No invoice number'
                            when coalesce(x ->> 'project', '') <> '' and x ->> 'project' <> p_project then 'Belongs to project ' || (x ->> 'project')
                            when dup > 1 then 'Invoice number appears more than once'
                            when pt_bad_num(x ->> 'sub') or pt_bad_num(x ->> 'amount') or pt_bad_num(x ->> 'appr') or pt_bad_num(x ->> 'coll') then 'An amount is not a number'
                            when pt_bad_date(x ->> 'date') then 'Invoice date is not a valid date'
                            when coalesce(x ->> 'currency', '') <> '' and upper(x ->> 'currency') <> 'SAR' then 'Currency ' || (x ->> 'currency') || ' is not SAR'
                            when sub < 0 or amount < 0 or appr < 0 or coll < 0 then 'Negative amount'
                            when greatest(sub, amount) <= 0 then 'No invoice amount'
                            when sub > 0 and appr > sub * 1.001 then 'Approved is more than submitted'
                            when appr > 0 and coll > appr * 1.001 then 'Collected is more than approved' end err from r)
  select coalesce(jsonb_agg(x) filter (where err is null), '[]'::jsonb),
         coalesce(jsonb_agg(jsonb_build_object('no', no_, 'error', err)) filter (where err is not null), '[]'::jsonb)
    into acc, rej from c;
  if jsonb_array_length(acc) = 0 then
    raise exception 'No valid invoice in this file, so the current register is kept unchanged'; end if;
  delete from invoices where project_id = p_project;
  insert into invoices (project_id, invoice_no, invoice_date, inv_type, amount, submitted, approved, collected, remark, uploaded_by)
  select p_project, btrim(x ->> 'no'), pt_date(x ->> 'date'), coalesce(nullif(x ->> 'type', ''), 'Progress'),
         coalesce(pt_num(x ->> 'amount'), pt_num(x ->> 'sub'), 0), coalesce(pt_num(x ->> 'sub'), pt_num(x ->> 'amount'), 0),
         coalesce(pt_num(x ->> 'appr'), 0), coalesce(pt_num(x ->> 'coll'), 0), x ->> 'note', me
    from jsonb_array_elements(acc) x;
  insert into import_batches (project_id, kind, file_name, file_hash, source_period, rows_total, rows_accepted, rows_rejected,
                              total_source, total_accepted, detail, by_user)
  values (p_project, 'invoices', p_file, p_hash, p_period, n_all, jsonb_array_length(acc), jsonb_array_length(rej),
          (select coalesce(sum(coalesce(pt_num(x ->> 'sub'), pt_num(x ->> 'amount'), 0)), 0) from jsonb_array_elements(p_rows) x),
          (select coalesce(sum(submitted), 0) from invoices where project_id = p_project),
          jsonb_build_object('rejected', rej), me)
  returning id into bid;
  insert into upload_history (project_id, kind, file_name, rows_total, rows_ok, rows_rejected, by_user)
  values (p_project, 'invoices', p_file, n_all, jsonb_array_length(acc), jsonb_array_length(rej), me);
  return jsonb_build_object('duplicate', false, 'batch_id', bid, 'accepted', jsonb_array_length(acc),
                            'rejected', rej, 'total_accepted', (select coalesce(sum(submitted), 0) from invoices where project_id = p_project));
end $$;

-- pt_inv_phase was used only by import_invoices above; pt_today_sa stays (schema-update-v20.sql uses it)
drop function if exists pt_inv_phase(text);

revoke execute on function schedule_update_commit(jsonb), import_invoices(text, text, text, jsonb, text) from public, anon;
grant execute on function schedule_update_commit(jsonb), import_invoices(text, text, text, jsonb, text) to authenticated;
$pt_rollback_body$;
  perform set_config('protrack.rollback', 'schema-update-v22.sql undone.', false);
end $pt_rollback$;
select current_setting('protrack.rollback', true) as result;
