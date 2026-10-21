-- ProTrack schema update v22 (ProTrackAI v3.14 and v3.15): actual progress against the chosen baselines, the baseline
-- assigned in the updated schedule, invoices by phase with their actual dates, and the payment period.
-- 1. Internal and client reports keep the baselines ticked (figures.bl_sel) and the comparison (figures.bl_cmp).
--    release_act_bl(p) takes the same p as release_act. It takes bl_sel and bl_cmp out of the figures, lets release_act
--    do everything it does today, and on a save of an internal or client report writes them into the saved figures, in
--    the same transaction (a refused comparison saves nothing). The browser works out each ticked baseline's planned %
--    and finish (it holds the revised and recovery baselines and the schedule rows, as relActLocal() does); the server
--    sets the actual, the forecast finish, the variance, the SPI and the days late or early from the figures it has
--    just worked out itself, so they always agree with the report's headline. A released version cannot be changed
--    (pt_release_frozen, v10 and later), so the comparison is frozen at approval as in relActLocal(); Revise copies it
--    into the new draft. release_act itself is NOT replaced, so this works with the release_act of v15, v16, v18 and
--    any later update (v19 included) without taking anything away from them.
-- 2. schedule_update_commit keeps each activity's dates in the baseline assigned in the updated schedule (xbs, xbf: the
--    baseline project exported with the XER, else the schedule's planned dates) and where they come from (bl_src).
-- 3. The invoice register keeps each invoice's phase and its submission, approval and collection dates, with the row
--    rules of the app's handleInvFile(). A date column the file does not have is not sent by the app (v3.15 layout
--    check); a register in the earlier layout (amounts only) still loads.
-- 4. The payment terms keep the payment period (billing.pay.days, "Client pays within (days of submission)"), a whole
--    number of days from 0 to 365.
-- 5. bl_cash_features() tells the app this update is in, so live.html sends and reads these fields.
-- Needs schema-update-v17.sql (it replaces v17's schedule_update_commit). Does not need v18, v19, v20 or v21.
-- Additive: seven columns, new functions and one trigger; schedule_update_commit and import_invoices are replaced.
-- Safe to run twice. Undo: schema-rollback-v22.sql.

do $$ begin
  if to_regclass('public.material_items') is null or not exists (select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'schedule_update_rows' and column_name = 'wbs_leaf') then
    raise exception 'Run schema-update-v17.sql (STAGE-14-SETUP) first, then this update'; end if;
end $$;

-- ------------------------------------------------------------------ 1. releases: the baselines ticked and the comparison
create or replace function pt_bl_keys() returns text[] language sql immutable as $$
  select array['ORG','REV','REC','SCH'] $$;
create or replace function pt_bl_name(k text) returns text language sql immutable as $$
  select case k when 'ORG' then 'Original baseline' when 'REV' then 'Revised baseline' when 'REC' then 'Recovery baseline'
                when 'SCH' then 'Baseline assigned in the updated schedule' end $$;

-- The comparison as the app's blCompare() (index.html, v3.14), one row per ticked baseline in the order ORG, REV, REC,
-- SCH. From the browser: the planned % (plan), the baseline finish (bf), the activities missing from the baseline
-- (miss), the basis and the date it was worked out at (dd), and for SCH where the dates come from (src). From the
-- report: the actual (act) and the forecast finish (fc). Then var = act - plan, spi = act / plan, slip = fc - bf days.
create or replace function pt_bl_cmp(sel jsonb, cmp jsonb, act numeric, fc date) returns jsonb
language plpgsql immutable as $$
declare ks text[]; k text; x jsonb; n int; pl numeric; bf date; mi numeric; out jsonb := '[]'::jsonb;
begin
  if sel is null or jsonb_typeof(sel) <> 'array' then raise exception 'Choose at least one baseline to compare the actual progress with'; end if;
  select array_agg(distinct v) into ks from jsonb_array_elements_text(sel) v;
  if ks is null then raise exception 'Choose at least one baseline to compare the actual progress with'; end if;
  if not (ks <@ pt_bl_keys()) then raise exception 'Unknown baseline: %. Use ORG, REV, REC or SCH', array_to_string(ks, ', '); end if;
  if cmp is null or jsonb_typeof(cmp) <> 'array' then raise exception 'The comparison with the baselines is missing. Reload the page and save again'; end if;
  if jsonb_array_length(cmp) <> cardinality(ks) then raise exception 'The comparison does not match the baselines ticked. Reload the page and save again'; end if;
  foreach k in array pt_bl_keys() loop
    continue when not (k = any(ks));
    select count(*) into n from jsonb_array_elements(cmp) e where jsonb_typeof(e) = 'object' and e ->> 'k' = k;
    if n <> 1 then raise exception 'The comparison does not match the baselines ticked. Reload the page and save again'; end if;
    select e into x from jsonb_array_elements(cmp) e where jsonb_typeof(e) = 'object' and e ->> 'k' = k;
    if pt_bad_num(x ->> 'plan') then raise exception '%: the planned progress must be a number', pt_bl_name(k); end if;
    pl := pt_num(x ->> 'plan');
    if pl is not null and (pl < 0 or pl > 100) then raise exception '%: the planned progress must be between 0 and 100', pt_bl_name(k); end if;
    if pt_bad_date(x ->> 'bf') or pt_bad_date(x ->> 'dd') then raise exception '%: a date is not valid', pt_bl_name(k); end if;
    bf := pt_date(x ->> 'bf');
    mi := coalesce(pt_num(x ->> 'miss'), 0);
    if pt_bad_num(x ->> 'miss') or mi < 0 or mi <> trunc(mi) then raise exception '%: the number of activities missing must be a whole number', pt_bl_name(k); end if;
    if length(coalesce(x ->> 'basis', '')) > 200 or length(coalesce(x ->> 'src', '')) > 300 then raise exception '%: the description is too long', pt_bl_name(k); end if;
    out := out || jsonb_build_array(jsonb_build_object('k', k, 'name', pt_bl_name(k), 'plan', pl, 'act', act,
      'var', case when pl is not null and act is not null then round(act - pl, 2) end,
      'spi', case when pl > 0 and act is not null then round(act / pl, 3) end,
      'bf', bf, 'fc', fc, 'slip', case when bf is not null and fc is not null then fc - bf end,
      'miss', mi::int, 'basis', nullif(x ->> 'basis', ''), 'dd', pt_date(x ->> 'dd'),
      'src', case when k = 'SCH' then nullif(x ->> 'src', '') end));
  end loop;
  return out;
end $$;

-- p: as release_act. figures.bl_sel ["ORG", ...] and figures.bl_cmp [{k, plan, bf, miss, basis, dd, src}, ...] are
-- taken out before release_act sees them (it accepts numbers, dates and short texts only) and written back after a
-- save of an internal (planning) or client report. Without them, this is exactly release_act.
create or replace function release_act_bl(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a text := p ->> 'action'; f jsonb := p -> 'figures'; sel jsonb; cmp jsonb; res jsonb; rel report_releases;
        act numeric; fc date; cmpv jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if jsonb_typeof(f) = 'object' then
    sel := f -> 'bl_sel'; cmp := f -> 'bl_cmp';
    p := jsonb_set(p, '{figures}', f - 'bl_sel' - 'bl_cmp');
  end if;
  res := release_act(p);
  if a is distinct from 'save' or (sel is null and cmp is null) then return res; end if;
  select * into rel from report_releases where id = (res ->> 'id')::uuid for update;
  if rel.id is null or rel.kind not in ('planning','client') then return res; end if;   -- cost reports carry no comparison
  if rel.kind = 'planning' then act := pt_num(rel.figures ->> 'actual_pct'); fc := pt_date(rel.figures ->> 'forecast_finish');
  else act := pt_num(rel.figures ->> 'act_pct'); fc := pt_date(rel.figures ->> 'tcc_fc_date'); end if;
  cmpv := pt_bl_cmp(sel, cmp, act, fc);
  update report_releases
     set figures = figures || jsonb_build_object('bl_sel', (select jsonb_agg(e -> 'k') from jsonb_array_elements(cmpv) e), 'bl_cmp', cmpv)
   where id = rel.id returning * into rel;
  return to_jsonb(rel);
end $$;

-- ------------------------------------------------------------------ 2. updated schedules: the baseline assigned in the XER
alter table schedule_updates add column if not exists bl_src text;          -- where xbs / xbf come from, as the app says it
alter table schedule_update_rows add column if not exists xbs date;         -- start in the baseline assigned in the schedule
alter table schedule_update_rows add column if not exists xbf date;         -- finish in the baseline assigned in the schedule

-- schedule_update_commit: from schema-update-v17.sql; also keeps each row's dates in the baseline assigned in the schedule
-- (xbs, xbf: dates, may be empty) and the update's bl_src (up to 300 characters)
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
  if length(coalesce(p ->> 'bl_src', '')) > 300 then raise exception 'The description of the schedule''s baseline is too long'; end if;
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
    if pt_bad_date(x ->> 'bs') or pt_bad_date(x ->> 'bf') or pt_bad_date(x ->> 'as') or pt_bad_date(x ->> 'af') or pt_bad_date(x ->> 'ef')
       or pt_bad_date(x ->> 'xbs') or pt_bad_date(x ->> 'xbf') then
      raise exception 'Activity %: a date is not valid', x ->> 'id'; end if;
    ph := coalesce(nullif(st.code_map ->> nullif(x ->> 'code', ''), ''), nullif(st.wbs_map ->> nullif(x ->> 'wbs', ''), ''));
    -- planned dates: the ProTrackAI baseline when the activity is in it, otherwise the schedule's planned dates
    select a.bs, a.bf into bs, bf from activities a where a.project_id = pid and a.id = btrim(x ->> 'id');
    bs := coalesce(bs, pt_date(x ->> 'bs')); bf := coalesce(bf, pt_date(x ->> 'bf'));
    if coalesce(pt_num(x ->> 'w'), 0) > 0 and (bs is null or bf is null) then raise exception 'Activity %: planned start and finish are needed', x ->> 'id'; end if;
    insert into schedule_update_rows (update_id, project_id, act_id, name, wbs, code, phase, w, bs, bf, pct, ms, as_d, af, ef, es, mat, uact, wbs_leaf, xbs, xbf)
    values (uid, pid, btrim(x ->> 'id'), left(x ->> 'name', 300), left(x ->> 'wbs', 200), left(x ->> 'code', 200), ph, coalesce(pt_num(x ->> 'w'), 0), bs, bf, v,
            coalesce((x ->> 'ms')::boolean, false), pt_date(x ->> 'as'), pt_date(x ->> 'af'), pt_date(x ->> 'ef'),
            pt_date(x ->> 'es'), nullif(left(btrim(coalesce(x ->> 'mat', '')), 120), ''), nullif(left(btrim(coalesce(x ->> 'uact', '')), 120), ''), left(x ->> 'wbs_leaf', 200),
            pt_date(x ->> 'xbs'), pt_date(x ->> 'xbf'))
    on conflict (update_id, act_id) do nothing;
  end loop;
  select count(*) into nunm from schedule_update_rows where update_id = uid and phase is null and w > 0;
  if nunm > 0 and wt = 'client' and exists (select 1 from jsonb_each_text(coalesce(st.weights, '{}'::jsonb)) e where pt_num(e.value) > 0) then
    raise exception '% weighted activities have no phase. Map every main WBS branch (or activity code value) to a phase first', nunm; end if;
  if not exists (select 1 from schedule_update_rows where update_id = uid and w > 0) then raise exception 'No activity in the schedule carries a weight'; end if;
  s := pt_sched_summary(uid, dd, wt, coalesce(st.weights, '{}'::jsonb));
  insert into schedule_updates (id, project_id, data_date, weightage, file_name, file_hash, weight_basis, weights, summary, uploaded_by, uploaded_name, bl_src)
  values (uid, pid, dd, wt, left(p ->> 'file_name', 300), nullif(p ->> 'file_hash', ''), left(p ->> 'weight_basis', 200), coalesce(st.weights, '{}'::jsonb), s, me, name_of(me),
          nullif(left(btrim(coalesce(p ->> 'bl_src', '')), 300), ''));
  return (select to_jsonb(u) from schedule_updates u where u.id = uid);
end $$;

-- ------------------------------------------------------------------ 3. invoice register: phase and actual dates
alter table invoices add column if not exists phase text;          -- ENG, PRC, CON, TC (payment-terms phases), ADV, RET, VAR; empty = none given
alter table invoices add column if not exists sub_date date;       -- submission date
alter table invoices add column if not exists appr_date date;      -- approval date
alter table invoices add column if not exists coll_date date;      -- collection date
do $$ begin
  alter table invoices add constraint invoices_phase_ok check (phase is null or phase in ('ENG','PRC','CON','TC','ADV','RET','VAR'));
exception when duplicate_object then null;
end $$;

-- today in Saudi Arabia (as schema-update-v20.sql; the app's TODAY is the date on the person's computer)
create or replace function pt_today_sa() returns date language sql stable as $$
  select (now() at time zone 'Asia/Riyadh')::date $$;

-- the phase as the app's invPhaseKey(): the key or the name, or the name's first word ("Engineering"), in any case;
-- null when empty, '?' when it is not one of them
create or replace function pt_inv_phase(t text) returns text language sql immutable as $$
  select case when btrim(coalesce(t, '')) = '' then null else coalesce((
    select k.code from (values (1,'ENG','Engineering and design'),(2,'PRC','Procurement and supply'),(3,'CON','Construction and installation'),
                              (4,'TC','Testing and commissioning'),(5,'ADV','Advance'),(6,'RET','Retention release'),(7,'VAR','Variations')) k(o, code, nm)
     where lower(k.code) = lower(btrim(t)) or lower(k.nm) = lower(btrim(t))
        or split_part(translate(lower(k.nm), ',', ' '), ' ', 1) = split_part(translate(lower(btrim(t)), ',', ' '), ' ', 1)
     order by k.o limit 1), '?') end $$;

-- import_invoices: from schema-update-v5.sql; also the phase and the actual dates, with the rules of handleInvFile().
-- A date column is in the file when its key is in the row (the app leaves out the columns the file does not have).
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
                    count(*) over (partition by lower(btrim(coalesce(x ->> 'no', '')))) dup,
                    pt_inv_phase(x ->> 'phase') ph, pt_date(x ->> 'sub_date') sd, pt_date(x ->> 'appr_date') ad, pt_date(x ->> 'coll_date') cd
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
                            when appr > 0 and coll > appr * 1.001 then 'Collected is more than approved'
                            -- v22 (ProTrackAI v3.15): the phase and the actual dates
                            when ph = '?' then 'Phase "' || btrim(x ->> 'phase') || '" is not one of: Engineering and design, Procurement and supply, Construction and installation, Testing and commissioning, Advance, Retention release, Variations'
                            when pt_bad_date(x ->> 'sub_date') or pt_bad_date(x ->> 'appr_date') or pt_bad_date(x ->> 'coll_date') then 'An actual date is not a valid date'
                            when greatest(sd, ad, cd) > pt_today_sa() then 'An actual date is in the future'
                            when x ? 'sub_date' and greatest(sub, amount) > 0 and sd is null then 'Submission date missing'
                            when x ? 'appr_date' and appr > 0 and ad is null then 'Approval date missing for the approved amount'
                            when x ? 'coll_date' and coll > 0 and cd is null then 'Collection date missing for the collected amount'
                            when ad < sd then 'Approved before it was submitted'
                            when cd < coalesce(ad, sd) then 'Collected before it was approved' end err from r)
  select coalesce(jsonb_agg(x) filter (where err is null), '[]'::jsonb),
         coalesce(jsonb_agg(jsonb_build_object('no', no_, 'error', err)) filter (where err is not null), '[]'::jsonb)
    into acc, rej from c;
  if jsonb_array_length(acc) = 0 then
    raise exception 'No valid invoice in this file, so the current register is kept unchanged'; end if;
  delete from invoices where project_id = p_project;
  insert into invoices (project_id, invoice_no, invoice_date, inv_type, amount, submitted, approved, collected, remark, uploaded_by,
                        phase, sub_date, appr_date, coll_date)
  select p_project, btrim(x ->> 'no'), pt_date(x ->> 'date'), coalesce(nullif(x ->> 'type', ''), 'Progress'),
         coalesce(pt_num(x ->> 'amount'), pt_num(x ->> 'sub'), 0), coalesce(pt_num(x ->> 'sub'), pt_num(x ->> 'amount'), 0),
         coalesce(pt_num(x ->> 'appr'), 0), coalesce(pt_num(x ->> 'coll'), 0), x ->> 'note', me,
         pt_inv_phase(x ->> 'phase'), pt_date(x ->> 'sub_date'), pt_date(x ->> 'appr_date'), pt_date(x ->> 'coll_date')
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

-- ------------------------------------------------------------------ 4. payment terms: the payment period
-- billing.pay.days ("Client pays within (days of submission)", Settings -> Projects) is kept as a whole number of days
-- from 0 to 365; empty means the app's default of 60. Terms without "pay" (saved before v3.15) are left as they are; the
-- app reads them as 60 days.
create or replace function pt_proj_billing() returns trigger language plpgsql as $$
declare d text; n numeric;
begin
  if new.billing is null or jsonb_typeof(new.billing) <> 'object' or not (new.billing ? 'pay') then return new; end if;
  if jsonb_typeof(new.billing -> 'pay') <> 'object' then
    raise exception 'The payment terms are not valid: the payment period must be sent as pay.days' using errcode = '22023'; end if;
  d := new.billing -> 'pay' ->> 'days';
  if d is null or btrim(d) = '' then n := 60;
  elsif pt_bad_num(d) then raise exception 'The payment period (client pays within days of submission) must be a number of days' using errcode = '22023';
  else n := round(pt_num(d)); end if;
  if n < 0 or n > 365 then raise exception 'The payment period must be from 0 to 365 days' using errcode = '22023'; end if;
  new.billing := jsonb_set(new.billing, '{pay,days}', to_jsonb(n::int));
  return new;
end $$;
drop trigger if exists trg_proj_billing on projects;
create trigger trg_proj_billing before insert or update of billing on projects for each row execute function pt_proj_billing();

-- ------------------------------------------------------------------ 5. the app asks this to know v22 is in (schema-rollback-v22.sql removes it)
create or replace function bl_cash_features() returns jsonb language sql immutable as $$
  select '{"version":22,"bl_cmp":true,"sched_bl":true,"inv_dates":true,"pay_days":true}'::jsonb $$;

-- ------------------------------------------------------------------ grants
revoke execute on function pt_bl_cmp(jsonb, jsonb, numeric, date) from public, anon, authenticated;
revoke execute on function release_act_bl(jsonb), schedule_update_commit(jsonb), import_invoices(text, text, text, jsonb, text) from public, anon;
grant execute on function release_act_bl(jsonb), schedule_update_commit(jsonb), import_invoices(text, text, text, jsonb, text), bl_cash_features() to authenticated;
