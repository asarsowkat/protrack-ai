-- ProTrack schema update v5 (Phase 3: controlled imports)
-- 1. Every import is a recorded batch with: number, source system, file name, file fingerprint (SHA-256 of the
--    file itself and of its content), size, period, currency, counts, source and accepted totals, warnings,
--    reconciliation result, who accepted a difference, failures and retries.
-- 2. A file with refused rows is saved only after the uploader confirms the difference; the server enforces it.
-- 3. Nothing is ever half-saved, and a file with no valid rows never empties the last good dataset.
-- 4. Weekly engineering and procurement progress is imported in one transaction, checked on the server.
-- 5. Non-numbers, bad dates, wrong project, wrong currency and duplicate IDs are refused row by row with a reason,
--    instead of stopping the whole load with a database error.
-- Run AFTER schema-update-v4.sql. Additive and safe to run more than once. Undo: schema-rollback-v5.sql.
-- Supabase -> SQL Editor -> New query -> paste -> Run.

-- ------------------------------------------------------------------ batch fields
alter table import_batches add column if not exists seq bigserial;
alter table import_batches add column if not exists file_sha256 text;
alter table import_batches add column if not exists file_size bigint;
alter table import_batches add column if not exists currency text;
alter table import_batches add column if not exists warnings int not null default 0;
alter table import_batches add column if not exists recon_status text;
alter table import_batches add column if not exists recon_diff numeric;
alter table import_batches add column if not exists recon_accepted_by uuid references profiles(id);
alter table import_batches add column if not exists recon_note text;
alter table import_batches add column if not exists retry_of uuid references import_batches(id);
alter table import_batches add column if not exists error_message text;
alter table import_batches drop constraint if exists import_batches_status_ok;
alter table import_batches add constraint import_batches_status_ok check (status in ('committed','failed'));

-- batches for several projects at once (weekly progress) are visible to planning, executives and super admin
drop policy if exists ib_read on import_batches;
create policy ib_read on import_batches for select using (
  (project_id is not null and can_see(project_id)) or (project_id is null and my_role_text() in ('sa','exec','plan')));

-- ------------------------------------------------------------------ helpers
create or replace function pt_num(t text) returns numeric language plpgsql immutable as $$
begin
  if t is null or btrim(t) = '' then return null; end if;
  return btrim(t)::numeric;
exception when others then return null;
end $$;
-- true when the text is present but not a number
create or replace function pt_bad_num(t text) returns boolean language sql immutable as
  $$ select coalesce(btrim(t), '') <> '' and pt_num(t) is null $$;

create or replace function pt_date(t text) returns date language plpgsql immutable as $$
begin
  if t is null or btrim(t) = '' then return null; end if;
  if btrim(t) !~ '^\d{4}-\d{2}-\d{2}' then return null; end if;
  return left(btrim(t), 10)::date;
exception when others then return null;
end $$;
create or replace function pt_bad_date(t text) returns boolean language sql immutable as
  $$ select coalesce(btrim(t), '') <> '' and pt_date(t) is null $$;

-- percent complete of an engineering or procurement milestone, as in the app; null = not a valid milestone
create or replace function pt_ms_pct(cls text, code text) returns numeric language sql immutable as $$
  select case
    when cls = 'ENG' then (array[0,0.10,0.40,0.70,1.00])[array_position(array['NS','ST','IDC','CMT','IFC'], upper(code))]
    when cls = 'PRC' then (array[0,0.05,0.15,0.30,0.65,0.80,0.90,1.00])[array_position(array['NS','PR','PO','VDA','MFG','FAT','SHP','DEL'], upper(code))]
  end $$;

-- A load is a repeat when it matches the last committed load of that kind (projects may be "several" = null).
create or replace function pt_batch_seen(p text, k text, h text) returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare b import_batches;
begin
  perform pg_advisory_xact_lock(hashtext('protrack:' || coalesce(p, '*') || ':' || k));
  select * into b from import_batches where project_id is not distinct from p and kind = k and status = 'committed'
   order by at_time desc, seq desc limit 1;
  return case when b.file_hash = h then b.id end;
end $$;

-- ------------------------------------------------------------------ invoice register (row checks hardened)
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

-- ------------------------------------------------------------------ costing file (row checks hardened)
create or replace function apply_costing(p_project text, p_file text, p_hash text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); seen uuid; bid uuid; src text; n_ok int; rej jsonb;
begin
  if me is null or not can_cost(p_project) then raise exception 'Only costing engineers, project managers and super admins of this project can apply a costing file' using errcode = '42501'; end if;
  if p_hash is null or length(p_hash) < 16 then raise exception 'A file hash is required'; end if;
  seen := pt_batch_seen(p_project, 'costing', p_hash);
  if seen is not null then return jsonb_build_object('duplicate', true, 'batch_id', seen); end if;
  select coalesce(mh_source, 'Costing file') into src from projects where id = p_project;
  create temporary table if not exists pt_cost_rows (x jsonb, err text) on commit drop;
  delete from pt_cost_rows;
  insert into pt_cost_rows
  select x, case when coalesce(x ->> 'client_error', '') <> '' then left(x ->> 'client_error', 200)
                 when coalesce(x ->> 'project', '') <> '' and x ->> 'project' <> p_project then 'Belongs to project ' || (x ->> 'project')
                 when not exists (select 1 from activities a where a.project_id = p_project and lower(a.id) = lower(x ->> 'id')) then 'Not in the baseline'
                 when count(*) over (partition by lower(x ->> 'id')) > 1 then 'Activity ID appears more than once'
                 when pt_bad_num(x ->> 'qty') or pt_bad_num(x ->> 'rate') or pt_bad_num(x ->> 'cost') or pt_bad_num(x ->> 'mh') then 'A number is not a number'
                 when coalesce(pt_num(x ->> 'qty'), 0) <= 0 then 'No budget quantity'
                 when coalesce(pt_num(x ->> 'cost'), 0) < 0 or coalesce(pt_num(x ->> 'mh'), 0) < 0 then 'Negative cost or manhours'
                 when coalesce(x ->> 'currency', '') <> '' and upper(x ->> 'currency') <> 'SAR' then 'Currency ' || (x ->> 'currency') || ' is not SAR' end
    from jsonb_array_elements(p_rows) x;
  select coalesce(jsonb_agg(jsonb_build_object('id', x ->> 'id', 'error', err)), '[]'::jsonb) into rej from pt_cost_rows where err is not null;
  if not exists (select 1 from pt_cost_rows where err is null) then
    raise exception 'No row in this file matches the baseline with a valid quantity, so nothing was changed'; end if;
  insert into baseline_history (project_id, taken_by, file_name, activities)
  select p_project, me, 'Costing: ' || coalesce(p_file, ''), coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) from activities a where a.project_id = p_project;
  update activities a set
    p6_mh = coalesce(a.p6_mh, a.budget_mh),
    qty = pt_num(ok.x ->> 'qty'), uom = left(coalesce(ok.x ->> 'uom', ''), 12),
    costing_mh = nullif(pt_num(ok.x ->> 'mh'), 0),
    budget_mh = case when coalesce(pt_num(ok.x ->> 'mh'), 0) > 0 and src = 'Costing file' then pt_num(ok.x ->> 'mh')
                     when src = 'P6 resource loading' then coalesce(a.p6_mh, a.budget_mh) else a.budget_mh end,
    budget_rate = coalesce(pt_num(ok.x ->> 'rate'), 0), budget_cost = coalesce(pt_num(ok.x ->> 'cost'), 0),
    gang = coalesce(nullif(ok.x ->> 'gang', ''), a.gang), costed = true
  from (select x from pt_cost_rows where err is null) ok
  where a.project_id = p_project and lower(a.id) = lower(ok.x ->> 'id');
  get diagnostics n_ok = row_count;
  insert into import_batches (project_id, kind, file_name, file_hash, rows_total, rows_accepted, rows_rejected,
                              total_source, total_accepted, detail, by_user)
  values (p_project, 'costing', p_file, p_hash, jsonb_array_length(p_rows), n_ok, jsonb_array_length(rej),
          (select coalesce(sum(coalesce(pt_num(x ->> 'cost'), 0)), 0) from pt_cost_rows),
          (select coalesce(sum(coalesce(pt_num(x ->> 'cost'), 0)), 0) from pt_cost_rows where err is null),
          jsonb_build_object('rejected', rej), me)
  returning id into bid;
  insert into upload_history (project_id, kind, file_name, rows_total, rows_ok, rows_rejected, by_user)
  values (p_project, 'costing', p_file, jsonb_array_length(p_rows), n_ok, jsonb_array_length(rej), me);
  return jsonb_build_object('duplicate', false, 'batch_id', bid, 'applied', n_ok, 'rejected', rej);
end $$;

-- ------------------------------------------------------------------ baseline (duplicate IDs and bad values refused as a whole)
create or replace function import_baseline(p_project text, p_file text, p_hash text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); seen uuid; bid uuid; n int; bad text;
begin
  if me is null or not can_plan(p_project) then raise exception 'Only planning engineers and super admins of this project can load a baseline' using errcode = '42501'; end if;
  if p_hash is null or length(p_hash) < 16 then raise exception 'A file hash is required'; end if;
  seen := pt_batch_seen(p_project, 'baseline', p_hash);
  if seen is not null then return jsonb_build_object('duplicate', true, 'batch_id', seen); end if;
  if exists (select 1 from jsonb_array_elements(p_rows) x where coalesce(x ->> 'id', '') = '' or coalesce(x ->> 'name', '') = '') then
    raise exception 'Every activity needs an ID and a name; nothing was imported'; end if;
  select string_agg(i, ', ') into bad from (select x ->> 'id' i from jsonb_array_elements(p_rows) x group by 1 having count(*) > 1 limit 5) d;
  if bad is not null then raise exception 'Activity IDs appear more than once (%); nothing was imported', bad; end if;
  select string_agg(x ->> 'id', ', ') into bad from (select x from jsonb_array_elements(p_rows) x
    where pt_bad_num(x ->> 'qty') or pt_bad_num(x ->> 'budget_mh') or pt_bad_num(x ->> 'price_weight') or pt_bad_num(x ->> 'prior_qty')
       or pt_bad_date(x ->> 'bs') or pt_bad_date(x ->> 'bf') or pt_date(x ->> 'bf') < pt_date(x ->> 'bs') limit 5) d;
  if bad is not null then raise exception 'Invalid numbers or dates on activities % (finish before start, text in a number column, or a bad date); nothing was imported', bad; end if;
  insert into baseline_history (project_id, taken_by, file_name, activities)
  select p_project, me, p_file, coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) from activities a where a.project_id = p_project;
  insert into activities (id, project_id, name, cls, disc, area, wbs, uom, qty, budget_mh, p6_mh, price_weight, trade_mix, bs, bf, prior_qty, cur)
  select x ->> 'id', p_project, x ->> 'name', coalesce(nullif(x ->> 'cls', ''), 'CON'), x ->> 'disc', x ->> 'area', x ->> 'wbs',
         x ->> 'uom', pt_num(x ->> 'qty'), pt_num(x ->> 'budget_mh'), pt_num(x ->> 'budget_mh'),
         pt_num(x ->> 'price_weight'), coalesce(x -> 'trade_mix', '{}'::jsonb),
         pt_date(x ->> 'bs'), pt_date(x ->> 'bf'), coalesce(pt_num(x ->> 'prior_qty'), 0), coalesce(x -> 'cur', '{}'::jsonb)
    from jsonb_array_elements(p_rows) x
  on conflict (project_id, id) do update set name = excluded.name, cls = excluded.cls, disc = excluded.disc, area = excluded.area,
    wbs = excluded.wbs, uom = coalesce(excluded.uom, activities.uom), qty = coalesce(excluded.qty, activities.qty),
    budget_mh = coalesce(excluded.budget_mh, activities.budget_mh), p6_mh = excluded.p6_mh,
    price_weight = coalesce(excluded.price_weight, activities.price_weight), trade_mix = excluded.trade_mix,
    bs = excluded.bs, bf = excluded.bf, prior_qty = excluded.prior_qty,
    cur = case when excluded.cur = '{}'::jsonb then activities.cur else excluded.cur end;
  get diagnostics n = row_count;
  update projects set start_date = coalesce((select min(pt_date(x ->> 'bs')) from jsonb_array_elements(p_rows) x), start_date),
                      finish_date = coalesce((select max(pt_date(x ->> 'bf')) from jsonb_array_elements(p_rows) x), finish_date)
   where id = p_project;
  insert into import_batches (project_id, kind, source_system, file_name, file_hash, rows_total, rows_accepted, rows_rejected, by_user)
  values (p_project, 'baseline', 'Primavera P6', p_file, p_hash, jsonb_array_length(p_rows), n, 0, me) returning id into bid;
  return jsonb_build_object('duplicate', false, 'batch_id', bid, 'upserted', n);
end $$;

-- ------------------------------------------------------------------ weekly engineering and procurement progress
-- p: {file, hash, data_date, rows:[{project_id, id, ms, as, af, ff, rem}]}. One transaction for every project in the file.
create or replace function import_progress(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); dd date := pt_date(p ->> 'data_date'); projs text[]; pid text; seen uuid; bid uuid;
        rej jsonb; n_ok int; v_pr text;
begin
  if me is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if dd is null then raise exception 'The data date is missing or not a valid date'; end if;
  if dd > current_date + 1 then raise exception 'The data date cannot be in the future'; end if;
  if jsonb_typeof(p -> 'rows') <> 'array' or jsonb_array_length(p -> 'rows') = 0 then raise exception 'The file has no progress rows'; end if;
  select array_agg(distinct coalesce(x ->> 'project_id', '')) into projs from jsonb_array_elements(p -> 'rows') x;
  if exists (select 1 from unnest(projs) q where q = '' or not can_plan(q)) then
    raise exception 'Only planning engineers and super admins of each project in the file can load progress' using errcode = '42501'; end if;
  pid := case when array_length(projs, 1) = 1 then projs[1] end;
  seen := pt_batch_seen(pid, 'update', p ->> 'hash');
  if seen is not null then return jsonb_build_object('duplicate', true, 'batch_id', seen); end if;

  create temporary table if not exists pt_prog (pr text, aid text, ms text, pct numeric, as_ text, af text, ff text, rem text,
    name text, cls text, cur jsonb, err text) on commit drop;
  delete from pt_prog;
  insert into pt_prog
  select r.pr, coalesce(a.id, r.aid), upper(r.ms), pt_ms_pct(a.cls, r.ms), r.as_, r.af, r.ff, r.rem, a.name, a.cls, coalesce(a.cur, '{}'::jsonb),
    case when coalesce(r.cerr, '') <> '' then left(r.cerr, 200)
         when a.id is null then 'Activity ID not found in project ' || r.pr
         when a.cls = 'CON' then 'Construction activity: update it through the daily report'
         when r.dup > 1 then 'Activity appears more than once'
         when pt_ms_pct(a.cls, r.ms) is null then 'Milestone "' || coalesce(r.ms, '') || '" is not valid for this activity'
         when pt_bad_date(r.as_) or pt_bad_date(r.af) or pt_bad_date(r.ff) then 'A date is not valid'
         when pt_ms_pct(a.cls, r.ms) < coalesce(pt_num(a.cur ->> 'pct'), 0) and coalesce(btrim(r.rem), '') = '' then 'Progress went backwards without a remark'
         when pt_date(r.as_) > dd then 'Actual start is after the data date'
         when pt_date(r.af) > dd then 'Actual finish is after the data date'
         when pt_date(r.af) is not null and pt_ms_pct(a.cls, r.ms) < 1 then 'Actual finish entered but the milestone is not the final one'
         when pt_date(r.af) < coalesce(pt_date(r.as_), pt_date(a.cur ->> 'as')) then 'Actual finish is before the actual start'
         when pt_date(r.ff) < coalesce(pt_date(r.as_), pt_date(a.cur ->> 'as')) then 'Forecast finish is before the actual start' end
  from (select x ->> 'project_id' pr, upper(btrim(coalesce(x ->> 'id', ''))) aid, btrim(coalesce(x ->> 'ms', '')) ms,
               x ->> 'as' as_, x ->> 'af' af, x ->> 'ff' ff, x ->> 'rem' rem, x ->> 'client_error' cerr,
               count(*) over (partition by x ->> 'project_id', upper(btrim(coalesce(x ->> 'id', '')))) dup
          from jsonb_array_elements(p -> 'rows') x) r
  left join activities a on a.project_id = r.pr and upper(a.id) = r.aid;

  select coalesce(jsonb_agg(jsonb_build_object('id', aid, 'project', pr, 'error', err)), '[]'::jsonb) into rej from pt_prog where err is not null;
  if not exists (select 1 from pt_prog where err is null) then
    raise exception 'No valid progress row in this file, so nothing was changed'; end if;

  -- history per project, in the app's own format
  for v_pr in select distinct t.pr from pt_prog t where t.err is null loop
    insert into weekly_updates (project_id, data_date, file_name, rows, applied_by)
    select v_pr, dd, p ->> 'file', jsonb_build_object('id', 'UPD-' || to_char(clock_timestamp(), 'YYMMDDHH24MISS'), 'p', v_pr, 'dataDate', dd,
             'by', name_of(me), 'at', to_char(now(), 'YYYY-MM-DD HH24:MI'), 'file', p ->> 'file',
             'rows', jsonb_agg(jsonb_build_object('act', t.aid, 'name', t.name, 'project', (select short from projects where id = v_pr),
                 'from', jsonb_build_object('ms', coalesce(t.cur ->> 'ms', 'NS'), 'pct', coalesce(pt_num(t.cur ->> 'pct'), 0), 'ff', coalesce(t.cur ->> 'ff', ''),
                                            'as', coalesce(t.cur ->> 'as', ''), 'af', coalesce(t.cur ->> 'af', '')),
                 'to', jsonb_build_object('ms', t.ms, 'pct', t.pct, 'ff', coalesce(nullif(t.ff, ''), t.cur ->> 'ff', ''),
                                          'as', coalesce(nullif(t.as_, ''), t.cur ->> 'as', ''), 'af', coalesce(nullif(t.af, ''), t.cur ->> 'af', '')),
                 'rem', coalesce(t.rem, '')))), me
      from pt_prog t where t.pr = v_pr and t.err is null;
  end loop;

  update activities a set cur = jsonb_build_object('ms', t.ms, 'pct', t.pct,
           'as', coalesce(nullif(left(t.as_, 10), ''), a.cur ->> 'as', ''), 'af', coalesce(nullif(left(t.af, 10), ''), a.cur ->> 'af', ''),
           'ff', coalesce(nullif(left(t.ff, 10), ''), a.cur ->> 'ff', ''), 'remarks', coalesce(t.rem, ''), 'dataDate', dd, 'by', name_of(me))
    from pt_prog t where t.err is null and a.project_id = t.pr and a.id = t.aid;
  get diagnostics n_ok = row_count;

  insert into import_batches (project_id, kind, source_system, file_name, file_hash, source_period, rows_total, rows_accepted, rows_rejected, detail, by_user)
  values (pid, 'update', 'Excel', p ->> 'file', p ->> 'hash', dd::text, jsonb_array_length(p -> 'rows'), n_ok, jsonb_array_length(rej),
          jsonb_build_object('rejected', rej, 'projects', to_jsonb(projs)), me)
  returning id into bid;
  return jsonb_build_object('duplicate', false, 'batch_id', bid, 'applied', n_ok, 'rejected', rej);
end $$;

-- ------------------------------------------------------------------ one entry point for the import centre
-- p: {kind, project_id, file_name, file_sha256, file_size, hash, period, currency, source_system, rows, warnings:[...],
--     accept_difference, note, data_date}
create or replace function import_commit(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); k text := p ->> 'kind'; pid text := nullif(p ->> 'project_id', ''); r jsonb; bid uuid;
        n int; rej int; tot int; failed uuid; src numeric; acc numeric; keys text[]; diff_txt text;
begin
  if me is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if k is null or k not in ('invoices','costing','baseline','update') then raise exception 'Unknown import type %', k; end if;
  n := coalesce(jsonb_array_length(p -> 'rows'), 0);
  if n = 0 then raise exception 'The file has no data rows'; end if;
  if n > 20000 then raise exception 'The file has % rows; the limit is 20,000. Split it and load each part.', n; end if;
  if coalesce(pt_num(p ->> 'file_size'), 0) > 10485760 then raise exception 'The file is larger than 10 MB'; end if;
  if lower(coalesce(p ->> 'file_name', '')) !~ '\.(xlsx|xls|csv|xer|xml)$' then
    raise exception 'Only Excel (.xlsx, .xls), CSV, Primavera XER or P6 XML files can be imported'; end if;
  if coalesce(p ->> 'hash', '') !~ '^[0-9a-fw]{24,}$' then raise exception 'A content fingerprint is required'; end if;

  r := case k when 'invoices' then import_invoices(pid, p ->> 'file_name', p ->> 'hash', p -> 'rows', p ->> 'period')
              when 'costing'  then apply_costing(pid, p ->> 'file_name', p ->> 'hash', p -> 'rows')
              when 'baseline' then import_baseline(pid, p ->> 'file_name', p ->> 'hash', p -> 'rows')
              else import_progress(jsonb_build_object('file', p ->> 'file_name', 'hash', p ->> 'hash', 'data_date', p ->> 'data_date', 'rows', p -> 'rows')) end;
  if coalesce((r ->> 'duplicate')::boolean, false) then
    return r || jsonb_build_object('batch_seq', (select seq from import_batches where id = (r ->> 'batch_id')::uuid)); end if;
  bid := (r ->> 'batch_id')::uuid;
  select rows_rejected, rows_total into rej, tot from import_batches where id = bid;

  -- reconciliation: what the file says against what was accepted
  if k in ('invoices','costing') then
    select array_agg(lower(btrim(coalesce(e ->> 'no', e ->> 'id', '')))) into keys from jsonb_array_elements(coalesce(r -> 'rejected', '[]'::jsonb)) e;
    select coalesce(sum(case when k = 'invoices' then coalesce(pt_num(x ->> 'sub'), pt_num(x ->> 'amount'), 0) else coalesce(pt_num(x ->> 'cost'), 0) end), 0),
           coalesce(sum(case when lower(btrim(coalesce(x ->> 'no', x ->> 'id', ''))) = any(coalesce(keys, '{}')) then 0
                             when k = 'invoices' then coalesce(pt_num(x ->> 'sub'), pt_num(x ->> 'amount'), 0) else coalesce(pt_num(x ->> 'cost'), 0) end), 0)
      into src, acc from jsonb_array_elements(p -> 'rows') x;
  end if;
  if coalesce(rej, 0) > 0 and not coalesce((p ->> 'accept_difference')::boolean, false) then
    diff_txt := case when src is not null then ' worth SAR ' || to_char(src - acc, 'FM999,999,999,990.00') else '' end;
    raise exception 'Reconciliation difference: % of % rows were refused%. Nothing was saved. Review the exception report, then confirm to load the accepted rows.', rej, tot, diff_txt
      using errcode = 'P0001', hint = 'confirm_difference';
  end if;
  select id into failed from import_batches
   where kind = k and project_id is not distinct from pid and status = 'failed' and file_hash = p ->> 'hash'
   order by at_time desc limit 1;
  update import_batches set
    file_sha256 = nullif(p ->> 'file_sha256', ''), file_size = pt_num(p ->> 'file_size'), currency = coalesce(nullif(p ->> 'currency', ''), 'SAR'),
    source_system = coalesce(nullif(p ->> 'source_system', ''), source_system), source_period = coalesce(source_period, nullif(p ->> 'period', '')),
    warnings = coalesce(jsonb_array_length(p -> 'warnings'), 0),
    detail = coalesce(detail, '{}'::jsonb) || jsonb_build_object('warnings', coalesce(p -> 'warnings', '[]'::jsonb)),
    total_source = coalesce(src, total_source), total_accepted = coalesce(acc, total_accepted),
    recon_status = case when coalesce(rej, 0) = 0 then 'Matched' else 'Accepted with difference' end,
    recon_diff = case when src is not null then src - acc end,
    recon_accepted_by = case when coalesce(rej, 0) > 0 then me end, recon_note = nullif(p ->> 'note', ''), retry_of = failed
   where id = bid;
  insert into change_log (project_id, text, by_user)
  values (pid, format('Import %s: %s, %s of %s rows accepted (batch %s)', k, p ->> 'file_name', tot - coalesce(rej, 0), tot,
                      (select seq from import_batches where id = bid)), me);
  return r || jsonb_build_object('batch_seq', (select seq from import_batches where id = bid),
                                 'recon_status', case when coalesce(rej, 0) = 0 then 'Matched' else 'Accepted with difference' end,
                                 'total_source', src, 'total_accepted', acc);
end $$;

-- A load that failed is recorded, so the import centre shows it and a later successful load shows as its retry.
create or replace function log_import_failure(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); k text := p ->> 'kind'; pid text := nullif(p ->> 'project_id', ''); bid uuid;
begin
  if me is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if k is null or k not in ('invoices','costing','baseline','update') then raise exception 'Unknown import type %', k; end if;
  if not (case when k in ('invoices','costing') then can_cost(pid)
               when pid is not null then can_plan(pid) else role_of(me) in ('sa','plan') end) then
    raise exception 'You cannot load this kind of file for this project' using errcode = '42501'; end if;
  insert into import_batches (project_id, kind, source_system, file_name, file_hash, file_sha256, file_size, source_period, rows_total,
                              rows_accepted, rows_rejected, status, error_message, detail, by_user)
  values (pid, k, coalesce(nullif(p ->> 'source_system', ''), 'Excel'), left(p ->> 'file_name', 200), p ->> 'hash', p ->> 'file_sha256',
          pt_num(p ->> 'file_size'), p ->> 'period', pt_num(p ->> 'rows_total'), 0, 0, 'failed', left(coalesce(p ->> 'error', 'Unknown error'), 500),
          jsonb_build_object('warnings', coalesce(p -> 'warnings', '[]'::jsonb)), me)
  returning id into bid;
  return jsonb_build_object('batch_id', bid, 'batch_seq', (select seq from import_batches where id = bid));
end $$;

revoke execute on function pt_num(text), pt_bad_num(text), pt_date(text), pt_bad_date(text), pt_ms_pct(text, text),
  pt_batch_seen(text, text, text), import_progress(jsonb), import_commit(jsonb), log_import_failure(jsonb),
  import_invoices(text, text, text, jsonb, text), apply_costing(text, text, text, jsonb), import_baseline(text, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function import_progress(jsonb), import_commit(jsonb), log_import_failure(jsonb),
  import_invoices(text, text, text, jsonb, text), apply_costing(text, text, text, jsonb), import_baseline(text, text, text, jsonb)
  to authenticated;
