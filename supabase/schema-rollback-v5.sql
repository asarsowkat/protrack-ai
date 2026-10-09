-- ProTrack: undo schema update v5 (go back to the v2.5 import behaviour).
-- Removes the v5 functions and puts back the v4 versions of the three import functions.
-- Deletes NO data: every import batch, invoice, activity and progress record stays, and the added
-- columns stay (v2.5 ignores them). Supabase -> SQL Editor -> New query -> paste -> Run. Safe to run twice.

drop function if exists import_commit(jsonb);
drop function if exists log_import_failure(jsonb);
drop function if exists import_progress(jsonb);
drop function if exists pt_ms_pct(text, text);
alter table import_batches drop constraint if exists import_batches_status_ok;
drop policy if exists ib_read on import_batches;
create policy ib_read on import_batches for select using (project_id is null or can_see(project_id));

create or replace function pt_batch_seen(p text, k text, h text) returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare b import_batches;
begin
  perform pg_advisory_xact_lock(hashtext('protrack:' || coalesce(p, '') || ':' || k));
  select * into b from import_batches where project_id = p and kind = k and status = 'committed'
   order by at_time desc, id desc limit 1;
  return case when b.file_hash = h then b.id end;
end $$;

create or replace function import_invoices(p_project text, p_file text, p_hash text, p_rows jsonb, p_period text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); seen uuid; acc jsonb; rej jsonb; bid uuid; n_all int;
begin
  if me is null or not can_cost(p_project) then raise exception 'Only costing engineers, project managers and super admins of this project can load invoices' using errcode = '42501'; end if;
  if p_hash is null or length(p_hash) < 16 then raise exception 'A file hash is required'; end if;
  seen := pt_batch_seen(p_project, 'invoices', p_hash);
  if seen is not null then return jsonb_build_object('duplicate', true, 'batch_id', seen); end if;
  n_all := jsonb_array_length(p_rows);
  with r as (select x, (x ->> 'no') no_, coalesce((x ->> 'sub')::numeric, 0) sub, coalesce((x ->> 'amount')::numeric, 0) amount,
                    coalesce((x ->> 'appr')::numeric, 0) appr, coalesce((x ->> 'coll')::numeric, 0) coll,
                    count(*) over (partition by x ->> 'no') dup
               from jsonb_array_elements(p_rows) x),
       c as (select *, case when coalesce(trim(no_), '') = '' then 'No invoice number'
                            when dup > 1 then 'Invoice number appears more than once'
                            when greatest(sub, amount) <= 0 then 'No invoice amount'
                            when sub > 0 and appr > sub * 1.001 then 'Approved is more than submitted'
                            when appr > 0 and coll > appr * 1.001 then 'Collected is more than approved' end err from r)
  select coalesce(jsonb_agg(x) filter (where err is null), '[]'::jsonb),
         coalesce(jsonb_agg(jsonb_build_object('no', no_, 'error', err)) filter (where err is not null), '[]'::jsonb)
    into acc, rej from c;
  delete from invoices where project_id = p_project;
  insert into invoices (project_id, invoice_no, invoice_date, inv_type, amount, submitted, approved, collected, remark, uploaded_by)
  select p_project, x ->> 'no', nullif(x ->> 'date', '')::date, coalesce(nullif(x ->> 'type', ''), 'Progress'),
         coalesce((x ->> 'amount')::numeric, (x ->> 'sub')::numeric, 0),
         coalesce((x ->> 'sub')::numeric, (x ->> 'amount')::numeric, 0),
         coalesce((x ->> 'appr')::numeric, 0), coalesce((x ->> 'coll')::numeric, 0), x ->> 'note', me
    from jsonb_array_elements(acc) x;
  insert into import_batches (project_id, kind, file_name, file_hash, source_period, rows_total, rows_accepted, rows_rejected,
                              total_source, total_accepted, detail, by_user)
  values (p_project, 'invoices', p_file, p_hash, p_period, n_all, jsonb_array_length(acc), jsonb_array_length(rej),
          (select coalesce(sum(coalesce((x ->> 'sub')::numeric, (x ->> 'amount')::numeric, 0)), 0) from jsonb_array_elements(p_rows) x),
          (select coalesce(sum(submitted), 0) from invoices where project_id = p_project),
          jsonb_build_object('rejected', rej), me)
  returning id into bid;
  insert into upload_history (project_id, kind, file_name, rows_total, rows_ok, rows_rejected, by_user)
  values (p_project, 'invoices', p_file, n_all, jsonb_array_length(acc), jsonb_array_length(rej), me);
  return jsonb_build_object('duplicate', false, 'batch_id', bid, 'accepted', jsonb_array_length(acc),
                            'rejected', rej, 'total_accepted', (select coalesce(sum(submitted), 0) from invoices where project_id = p_project));
end $$;

create or replace function apply_costing(p_project text, p_file text, p_hash text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); seen uuid; bid uuid; src text; n_ok int; rej jsonb;
begin
  if me is null or not can_cost(p_project) then raise exception 'Only costing engineers, project managers and super admins of this project can apply a costing file' using errcode = '42501'; end if;
  if p_hash is null or length(p_hash) < 16 then raise exception 'A file hash is required'; end if;
  seen := pt_batch_seen(p_project, 'costing', p_hash);
  if seen is not null then return jsonb_build_object('duplicate', true, 'batch_id', seen); end if;
  select coalesce(mh_source, 'Costing file') into src from projects where id = p_project;
  select coalesce(jsonb_agg(jsonb_build_object('id', x ->> 'id', 'error',
           case when not exists (select 1 from activities a where a.project_id = p_project and lower(a.id) = lower(x ->> 'id')) then 'Not in the baseline'
                else 'No budget quantity' end)), '[]'::jsonb)
    into rej from jsonb_array_elements(p_rows) x
   where not exists (select 1 from activities a where a.project_id = p_project and lower(a.id) = lower(x ->> 'id'))
      or coalesce((x ->> 'qty')::numeric, 0) <= 0;
  insert into baseline_history (project_id, taken_by, file_name, activities)
  select p_project, me, 'Costing: ' || coalesce(p_file, ''), coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) from activities a where a.project_id = p_project;
  with ok as (select x from jsonb_array_elements(p_rows) x
               where coalesce((x ->> 'qty')::numeric, 0) > 0
                 and exists (select 1 from activities a where a.project_id = p_project and lower(a.id) = lower(x ->> 'id')))
  update activities a set
    p6_mh = coalesce(a.p6_mh, a.budget_mh),
    qty = (x ->> 'qty')::numeric, uom = left(coalesce(x ->> 'uom', ''), 12),
    costing_mh = nullif((x ->> 'mh')::numeric, 0),
    budget_mh = case when coalesce((x ->> 'mh')::numeric, 0) > 0 and src = 'Costing file' then (x ->> 'mh')::numeric
                     when src = 'P6 resource loading' then coalesce(a.p6_mh, a.budget_mh) else a.budget_mh end,
    budget_rate = coalesce((x ->> 'rate')::numeric, 0), budget_cost = coalesce((x ->> 'cost')::numeric, 0),
    gang = coalesce(nullif(x ->> 'gang', ''), a.gang), costed = true
  from ok where a.project_id = p_project and lower(a.id) = lower(ok.x ->> 'id');
  get diagnostics n_ok = row_count;
  insert into import_batches (project_id, kind, file_name, file_hash, rows_total, rows_accepted, rows_rejected,
                              total_source, total_accepted, detail, by_user)
  values (p_project, 'costing', p_file, p_hash, jsonb_array_length(p_rows), n_ok, jsonb_array_length(rej),
          (select coalesce(sum((x ->> 'cost')::numeric), 0) from jsonb_array_elements(p_rows) x),
          (select coalesce(sum(budget_cost), 0) from activities where project_id = p_project and costed),
          jsonb_build_object('rejected', rej), me)
  returning id into bid;
  insert into upload_history (project_id, kind, file_name, rows_total, rows_ok, rows_rejected, by_user)
  values (p_project, 'costing', p_file, jsonb_array_length(p_rows), n_ok, jsonb_array_length(rej), me);
  return jsonb_build_object('duplicate', false, 'batch_id', bid, 'applied', n_ok, 'rejected', rej);
end $$;

create or replace function import_baseline(p_project text, p_file text, p_hash text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); seen uuid; bid uuid; n int;
begin
  if me is null or not can_plan(p_project) then raise exception 'Only planning engineers and super admins of this project can load a baseline' using errcode = '42501'; end if;
  if p_hash is null or length(p_hash) < 16 then raise exception 'A file hash is required'; end if;
  seen := pt_batch_seen(p_project, 'baseline', p_hash);
  if seen is not null then return jsonb_build_object('duplicate', true, 'batch_id', seen); end if;
  if exists (select 1 from jsonb_array_elements(p_rows) x where coalesce(x ->> 'id', '') = '' or coalesce(x ->> 'name', '') = '') then
    raise exception 'Every activity needs an ID and a name; nothing was imported'; end if;
  insert into baseline_history (project_id, taken_by, file_name, activities)
  select p_project, me, p_file, coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) from activities a where a.project_id = p_project;
  insert into activities (id, project_id, name, cls, disc, area, wbs, uom, qty, budget_mh, p6_mh, price_weight, trade_mix, bs, bf, prior_qty, cur)
  select x ->> 'id', p_project, x ->> 'name', coalesce(nullif(x ->> 'cls', ''), 'CON'), x ->> 'disc', x ->> 'area', x ->> 'wbs',
         x ->> 'uom', nullif(x ->> 'qty', '')::numeric, nullif(x ->> 'budget_mh', '')::numeric, nullif(x ->> 'budget_mh', '')::numeric,
         nullif(x ->> 'price_weight', '')::numeric, coalesce(x -> 'trade_mix', '{}'::jsonb),
         nullif(x ->> 'bs', '')::date, nullif(x ->> 'bf', '')::date, coalesce(nullif(x ->> 'prior_qty', '')::numeric, 0),
         coalesce(x -> 'cur', '{}'::jsonb)
    from jsonb_array_elements(p_rows) x
  on conflict (project_id, id) do update set name = excluded.name, cls = excluded.cls, disc = excluded.disc, area = excluded.area,
    wbs = excluded.wbs, uom = coalesce(excluded.uom, activities.uom), qty = coalesce(excluded.qty, activities.qty),
    budget_mh = coalesce(excluded.budget_mh, activities.budget_mh), p6_mh = excluded.p6_mh,
    price_weight = coalesce(excluded.price_weight, activities.price_weight), trade_mix = excluded.trade_mix,
    bs = excluded.bs, bf = excluded.bf, prior_qty = excluded.prior_qty,
    cur = case when excluded.cur = '{}'::jsonb then activities.cur else excluded.cur end;
  get diagnostics n = row_count;
  -- the project's start and finish follow the imported activities, as in the app
  update projects set start_date = coalesce((select min(nullif(x ->> 'bs', '')::date) from jsonb_array_elements(p_rows) x), start_date),
                      finish_date = coalesce((select max(nullif(x ->> 'bf', '')::date) from jsonb_array_elements(p_rows) x), finish_date)
   where id = p_project;
  insert into import_batches (project_id, kind, source_system, file_name, file_hash, rows_total, rows_accepted, rows_rejected, by_user)
  values (p_project, 'baseline', 'Primavera P6', p_file, p_hash, jsonb_array_length(p_rows), n, 0, me) returning id into bid;
  return jsonb_build_object('duplicate', false, 'batch_id', bid, 'upserted', n);
end $$;

-- pt_num, pt_date and their checks are left in place: harmless, and nothing in v4 uses them.
grant execute on function import_invoices(text, text, text, jsonb, text), apply_costing(text, text, text, jsonb),
  import_baseline(text, text, text, jsonb) to authenticated;
