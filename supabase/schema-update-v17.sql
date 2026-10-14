-- ProTrack schema update v17 (ProTrackAI v3.8): Material Tracking.
-- 1. Per project, the planning engineer loads the approved baseline schedule into Material Tracking and says which
--    P6 activity code carries the Material Name and which the Unified Activity Name, which WBS branches hold the
--    material activities, and which of the nine procurement milestones each Unified Activity Name stands for.
--    One monitoring row per material; the planning engineer chooses which materials are monitored.
-- 2. Every updated schedule (schedule_update_commit, v15) now also keeps each activity's early start, Material Name,
--    Unified Activity Name and own WBS, so milestone statuses refresh from the latest update.
-- 3. PO Number, Supplier Name and Remarks are kept per material by the people with the new right
--    "materials.keep" (planning engineers and the Head of Planning and Cost Control by default). Schedule imports never
--    touch them, and every change is kept in material_audit, which cannot be changed.
-- 4. Room for later: quantity ordered, quantity delivered and unit per material (partial deliveries, GRN), unused yet.
-- Additive: new tables and functions, four new columns on schedule_update_rows. Safe to run twice.
-- Undo: schema-rollback-v17.sql.

-- ------------------------------------------------------------------ the nine milestones, the new right and screen
create or replace function pt_mat_stages() returns text[] language sql immutable as $$
  select array['PR','PO','BD','GAFM','MFG','FAT','RFS','DEL','CIV'] $$;
create or replace function pt_rights() returns text[] language sql immutable as $$
  select array['dpr.create','dpr.approve','planning.manage','report.internal.prepare','report.internal.approve',
               'costing.manage','money.view','report.cost.prepare','report.cost.approve','logs.upload',
               'issues.keep','issues.review','docs.contract','docs.planning','docs.cost','tender.register','lifecycle.approve',
               'materials.keep'] $$;
create or replace function pt_screens() returns text[] language sql immutable as $$
  select array['xr','exec','proj','tender','iss','docs','act','rel','logs','dash','dpr','new','pdash','upd','base','imp',
               'cdash','eva','rep','deck','perf','mat'] $$;
create or replace function pt_right_default(base text, k text) returns boolean language sql immutable as $$
  select coalesce(base = 'sa' or case k
    when 'dpr.create'              then base in ('eng','foreman')
    when 'dpr.approve'             then base = 'pm'
    when 'planning.manage'         then base = 'plan'
    when 'report.internal.prepare' then base = 'plan'
    when 'report.internal.approve' then false
    when 'costing.manage'          then base in ('costing','pm')
    when 'money.view'              then base not in ('foreman','eng','sm')
    when 'report.cost.prepare'     then base = 'costing'
    when 'report.cost.approve'     then false
    when 'logs.upload'             then base = 'costing'
    when 'issues.keep'             then base in ('plan','costing')
    when 'issues.review'           then false
    when 'docs.contract'           then base = 'costing'
    when 'docs.planning'           then base = 'plan'
    when 'docs.cost'               then base = 'costing'
    when 'tender.register'         then false
    when 'lifecycle.approve'       then base = 'pm'
    when 'materials.keep'          then base = 'plan'
    else false end, false) $$;
-- may keep the material tracking of a project: the right (planning engineers; the Head by position) and access
create or replace function pt_mat_keeper(u uuid, pid text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(user_sees(u, pid) and pt_right(u, 'materials.keep', pt_is_head(u)), false) $$;

-- ------------------------------------------------------------------ the updated schedule keeps what material tracking needs
alter table schedule_update_rows add column if not exists es date;
alter table schedule_update_rows add column if not exists mat text;
alter table schedule_update_rows add column if not exists uact text;
alter table schedule_update_rows add column if not exists wbs_leaf text;

-- ------------------------------------------------------------------ tables
create table if not exists material_setup (
  project_id text primary key references projects(id) on delete cascade,
  mat_code text not null,                          -- P6 activity code type holding the Material Name
  uact_code text not null,                         -- P6 activity code type holding the Unified Activity Name
  wbs_filter jsonb not null default '[]'::jsonb,   -- main WBS branches holding the material activities
  stage_map jsonb not null default '{}'::jsonb,    -- {"<Unified Activity Name>": "PR".."CIV" or ""}
  file_name text, file_hash text, data_date date,  -- the baseline schedule loaded
  updated_by uuid references profiles(id), updated_at timestamptz not null default now());
create table if not exists material_acts (         -- the material activities of the baseline, replaced at each baseline load
  project_id text not null references projects(id) on delete cascade,
  act_id text not null, name text, wbs text, wbs_leaf text, material text not null, uact text,
  bs date, bf date, es date, ef date, as_d date, af date, pct numeric not null default 0, ms boolean not null default false,
  primary key (project_id, act_id));
create index if not exists ma_mat on material_acts (project_id, material);
create table if not exists material_items (        -- one row per material: chosen for monitoring, and the manual fields
  project_id text not null references projects(id) on delete cascade,
  material text not null,
  selected boolean not null default true,
  po_number text, supplier text, remarks text,
  qty_ordered numeric, qty_delivered numeric, uom text,   -- for partial deliveries later; not used yet
  updated_by uuid references profiles(id), updated_at timestamptz not null default now(),
  primary key (project_id, material));
create table if not exists material_audit (
  id bigserial primary key, project_id text not null, material text, field text not null,
  before text, after text, note text, by_user uuid references profiles(id), by_name text, at_time timestamptz not null default now());
create index if not exists mau_proj on material_audit (project_id, material);

alter table material_setup enable row level security;
alter table material_acts enable row level security;
alter table material_items enable row level security;
alter table material_audit enable row level security;
-- read: everyone with access to the project; no write policies, every change goes through the functions below
drop policy if exists mset_read on material_setup;
create policy mset_read on material_setup for select using (can_see(project_id));
drop policy if exists mact_read on material_acts;
create policy mact_read on material_acts for select using (can_see(project_id));
drop policy if exists mitem_read on material_items;
create policy mitem_read on material_items for select using (can_see(project_id));
drop policy if exists maud_read on material_audit;
create policy maud_read on material_audit for select using (can_see(project_id));
drop trigger if exists trg_maud_append on material_audit;
create trigger trg_maud_append before update or delete on material_audit for each row execute function pt_append_only();
drop trigger if exists trg_maud_truncate on material_audit;
create trigger trg_maud_truncate before truncate on material_audit execute function pt_no_truncate();

-- ------------------------------------------------------------------ set-up and the baseline load
-- p: {project_id, action: 'baseline' | 'settings', mat_code, uact_code, wbs_filter:[..], stage_map:{..},
--     file_name, file_hash, data_date, rows:[{id,name,wbs,wbs_leaf,material,uact,bs,bf,es,ef,as,af,pct,ms}],
--     select:[materials to monitor] (optional), note}
create or replace function material_setup_save(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); pid text := p ->> 'project_id'; a text := coalesce(p ->> 'action', 'settings');
        mc text := nullif(btrim(coalesce(p ->> 'mat_code', '')), ''); uc text := nullif(btrim(coalesce(p ->> 'uact_code', '')), '');
        wf jsonb := coalesce(p -> 'wbs_filter', '[]'::jsonb); sm jsonb := coalesce(p -> 'stage_map', '{}'::jsonb);
        old material_setup; x jsonb; k text; v text; n int := 0; nm int := 0; bad text; id text; mat text;
begin
  if me is null or role_of(me) is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if pid is null or not user_sees(me, pid) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
  if not pt_mat_keeper(me, pid) then raise exception 'Only the people who keep material tracking (planning engineers of this project, the Head of Planning and Cost Control or a super admin) can change it' using errcode = '42501'; end if;
  if a not in ('baseline','settings') then raise exception 'Unknown action %', a; end if;
  select * into old from material_setup where project_id = pid for update;
  if a = 'settings' and old.project_id is null then raise exception 'Load the baseline schedule into Material Tracking first'; end if;
  mc := coalesce(mc, old.mat_code); uc := coalesce(uc, old.uact_code);
  if mc is null or uc is null then raise exception 'Choose the activity codes for the Material Name and the Unified Activity Name'; end if;
  if lower(mc) = lower(uc) then raise exception 'The Material Name and the Unified Activity Name must be two different activity codes'; end if;
  if length(mc) > 120 or length(uc) > 120 then raise exception 'Activity code names are 120 characters at most'; end if;
  if jsonb_typeof(wf) <> 'array' then raise exception 'The WBS branches must be a list'; end if;
  if a = 'settings' and not (p ? 'wbs_filter') then wf := old.wbs_filter; end if;
  if jsonb_array_length(wf) = 0 then raise exception 'Choose at least one WBS branch that holds the material activities'; end if;
  if jsonb_typeof(sm) <> 'object' then raise exception 'The milestone mapping must be a list of names'; end if;
  if a = 'settings' and not (p ? 'stage_map') then sm := old.stage_map; end if;
  for k, v in select * from jsonb_each_text(sm) loop
    if coalesce(v, '') <> '' and not (v = any(pt_mat_stages())) then raise exception 'Unknown milestone % for %', v, k; end if;
  end loop;

  if a = 'baseline' then
    if jsonb_typeof(p -> 'rows') <> 'array' then raise exception 'The baseline has no material activities'; end if;
    if jsonb_array_length(p -> 'rows') > 20000 then raise exception 'More than 20,000 material activities'; end if;
    select string_agg(coalesce(r ->> 'id', '?'), ', ') into bad from (select r from jsonb_array_elements(p -> 'rows') r limit 20000) q
     where coalesce(btrim(r ->> 'id'), '') = '' or length(r ->> 'id') > 60 or coalesce(btrim(r ->> 'material'), '') = '' or length(r ->> 'material') > 120
        or length(coalesce(r ->> 'uact', '')) > 120 or pt_bad_date(r ->> 'bs') or pt_bad_date(r ->> 'bf') or pt_bad_date(r ->> 'es') or pt_bad_date(r ->> 'ef')
        or pt_bad_date(r ->> 'as') or pt_bad_date(r ->> 'af') or pt_bad_num(r ->> 'pct') or coalesce(pt_num(r ->> 'pct'), 0) not between 0 and 100;
    if bad is not null then raise exception 'Activities refused (an ID, a Material Name, a date or a %% complete is missing or wrong): %', left(bad, 300); end if;
    if jsonb_array_length(p -> 'rows') = 0 then raise exception 'No activity in the chosen WBS branches carries a Material Name'; end if;
    delete from material_acts where project_id = pid;
    for x in select * from jsonb_array_elements(p -> 'rows') loop
      id := btrim(x ->> 'id'); mat := btrim(x ->> 'material');
      insert into material_acts (project_id, act_id, name, wbs, wbs_leaf, material, uact, bs, bf, es, ef, as_d, af, pct, ms)
      values (pid, id, left(x ->> 'name', 300), left(x ->> 'wbs', 200), left(x ->> 'wbs_leaf', 200), mat, nullif(btrim(coalesce(x ->> 'uact', '')), ''),
              pt_date(x ->> 'bs'), pt_date(x ->> 'bf'), pt_date(x ->> 'es'), pt_date(x ->> 'ef'), pt_date(x ->> 'as'), pt_date(x ->> 'af'),
              coalesce(pt_num(x ->> 'pct'), 0), coalesce((x ->> 'ms')::boolean, false))
      on conflict (project_id, act_id) do nothing;
      n := n + 1;
    end loop;
    -- a new material gets a monitoring row; an existing one keeps its PO number, supplier and remarks
    insert into material_items (project_id, material, selected, updated_by)
    select distinct pid, m.material, true, me from material_acts m where m.project_id = pid
    on conflict (project_id, material) do nothing;
    get diagnostics nm = row_count;
    insert into material_audit (project_id, field, after, note, by_user, by_name)
    values (pid, 'Baseline loaded', coalesce(p ->> 'file_name', 'schedule') || ': ' || n || ' activities, ' || nm || ' new materials', left(p ->> 'note', 500), me, name_of(me));
  end if;

  insert into material_setup (project_id, mat_code, uact_code, wbs_filter, stage_map, file_name, file_hash, data_date, updated_by, updated_at)
  values (pid, mc, uc, wf, sm, case when a = 'baseline' then left(p ->> 'file_name', 200) end, case when a = 'baseline' then left(p ->> 'file_hash', 128) end,
          case when a = 'baseline' then pt_date(p ->> 'data_date') end, me, now())
  on conflict (project_id) do update set mat_code = excluded.mat_code, uact_code = excluded.uact_code, wbs_filter = excluded.wbs_filter,
    stage_map = excluded.stage_map, updated_by = me, updated_at = now(),
    file_name = case when a = 'baseline' then excluded.file_name else material_setup.file_name end,
    file_hash = case when a = 'baseline' then excluded.file_hash else material_setup.file_hash end,
    data_date = case when a = 'baseline' then excluded.data_date else material_setup.data_date end;
  if old.project_id is not null and (old.stage_map is distinct from sm or old.wbs_filter is distinct from wf or old.mat_code is distinct from mc or old.uact_code is distinct from uc) then
    insert into material_audit (project_id, field, before, after, by_user, by_name)
    values (pid, 'Set-up', jsonb_build_object('mat_code', old.mat_code, 'uact_code', old.uact_code, 'wbs', old.wbs_filter, 'map', old.stage_map)::text,
            jsonb_build_object('mat_code', mc, 'uact_code', uc, 'wbs', wf, 'map', sm)::text, me, name_of(me));
  end if;
  -- which materials are monitored
  if jsonb_typeof(p -> 'select') = 'array' then
    insert into material_audit (project_id, material, field, before, after, by_user, by_name)
    select pid, i.material, 'Monitored', i.selected::text, (i.material in (select jsonb_array_elements_text(p -> 'select')))::text, me, name_of(me)
      from material_items i where i.project_id = pid and i.selected is distinct from (i.material in (select jsonb_array_elements_text(p -> 'select')));
    update material_items set selected = (material in (select jsonb_array_elements_text(p -> 'select'))), updated_by = me, updated_at = now()
     where project_id = pid and selected is distinct from (material in (select jsonb_array_elements_text(p -> 'select')));
  end if;
  return jsonb_build_object('project_id', pid, 'activities', n, 'new_materials', nm,
    'materials', (select count(*) from material_items where project_id = pid), 'monitored', (select count(*) from material_items where project_id = pid and selected));
end $$;

-- ------------------------------------------------------------------ the manual fields of one material
-- p: {project_id, material, po_number?, supplier?, remarks?, selected?}  (only the fields sent are changed)
create or replace function material_item_save(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); pid text := p ->> 'project_id'; m text := btrim(coalesce(p ->> 'material', '')); it material_items; f text; nv text; ov text; ch int := 0;
begin
  if me is null or role_of(me) is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if pid is null or not user_sees(me, pid) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
  if not pt_mat_keeper(me, pid) then raise exception 'Only the people who keep material tracking (planning engineers of this project, the Head of Planning and Cost Control or a super admin) can change it' using errcode = '42501'; end if;
  select * into it from material_items where project_id = pid and material = m for update;
  if it.material is null then raise exception 'Unknown material %', m; end if;
  if length(coalesce(p ->> 'po_number', '')) > 60 then raise exception 'The PO number is 60 characters at most'; end if;
  if length(coalesce(p ->> 'supplier', '')) > 120 then raise exception 'The supplier name is 120 characters at most'; end if;
  if length(coalesce(p ->> 'remarks', '')) > 4000 then raise exception 'Remarks are 4,000 characters at most'; end if;
  if p ? 'selected' and jsonb_typeof(p -> 'selected') <> 'boolean' then raise exception 'Monitored must be yes or no'; end if;
  foreach f in array array['po_number','supplier','remarks','selected'] loop
    if p ? f then
      nv := case when f = 'selected' then (p ->> f) else nullif(btrim(coalesce(p ->> f, '')), '') end;
      ov := case f when 'po_number' then it.po_number when 'supplier' then it.supplier when 'remarks' then it.remarks else it.selected::text end;
      if nv is distinct from ov then
        ch := ch + 1;
        insert into material_audit (project_id, material, field, before, after, by_user, by_name)
        values (pid, m, case f when 'po_number' then 'PO Number' when 'supplier' then 'Supplier Name' when 'remarks' then 'Remarks' else 'Monitored' end, ov, nv, me, name_of(me));
      end if;
    end if;
  end loop;
  if ch > 0 then
    update material_items set
      po_number = case when p ? 'po_number' then nullif(btrim(coalesce(p ->> 'po_number', '')), '') else po_number end,
      supplier  = case when p ? 'supplier'  then nullif(btrim(coalesce(p ->> 'supplier', '')), '') else supplier end,
      remarks   = case when p ? 'remarks'   then nullif(btrim(coalesce(p ->> 'remarks', '')), '') else remarks end,
      selected  = case when p ? 'selected'  then (p ->> 'selected')::boolean else selected end,
      updated_by = me, updated_at = now()
     where project_id = pid and material = m returning * into it;
  end if;
  return to_jsonb(it) || jsonb_build_object('changed', ch);
end $$;

-- ------------------------------------------------------------------ schedule_update_commit (from schema-update-v15.sql): also keeps early start, material codes and the own WBS
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

-- ------------------------------------------------------------------ grants
revoke execute on function pt_mat_keeper(uuid, text) from public, anon, authenticated;
revoke execute on function material_setup_save(jsonb), material_item_save(jsonb), pt_mat_stages() from public, anon;
grant execute on function material_setup_save(jsonb), material_item_save(jsonb), pt_mat_stages() to authenticated;
grant select on material_setup, material_acts, material_items, material_audit to authenticated;
