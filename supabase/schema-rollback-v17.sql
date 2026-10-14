-- ProTrack schema rollback v17: back to the v3.7 rules (schema-update-v16.sql).
-- Material Tracking stops working: its functions are removed. The tables material_setup, material_acts,
-- material_items and material_audit, and the new columns of schedule_update_rows, are kept with everything in them.
-- The right "materials.keep" and the screen "mat" are no longer known; settings already saved for them are kept but
-- unused. Run schema-update-v17.sql again to use them again. Safe to run twice.
-- pt_rights: as in schema-update-v16.sql
create or replace function pt_rights() returns text[] language sql immutable as $$
  select array['dpr.create','dpr.approve','planning.manage','report.internal.prepare','report.internal.approve',
               'costing.manage','money.view','report.cost.prepare','report.cost.approve','logs.upload',
               'issues.keep','issues.review','docs.contract','docs.planning','docs.cost','tender.register','lifecycle.approve'] $$;
-- pt_screens: as in schema-update-v16.sql
create or replace function pt_screens() returns text[] language sql immutable as $$
  select array['xr','exec','proj','tender','iss','docs','act','rel','logs','dash','dpr','new','pdash','upd','base','imp',
               'cdash','eva','rep','deck','perf'] $$;
-- pt_right_default: as in schema-update-v16.sql
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
    else false end, false) $$;
-- schedule_update_commit: as in schema-update-v15.sql
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
    insert into schedule_update_rows (update_id, project_id, act_id, name, wbs, code, phase, w, bs, bf, pct, ms, as_d, af, ef)
    values (uid, pid, btrim(x ->> 'id'), left(x ->> 'name', 300), left(x ->> 'wbs', 200), left(x ->> 'code', 200), ph, coalesce(pt_num(x ->> 'w'), 0), bs, bf, v,
            coalesce((x ->> 'ms')::boolean, false), pt_date(x ->> 'as'), pt_date(x ->> 'af'), pt_date(x ->> 'ef'))
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

drop function if exists material_setup_save(jsonb);
drop function if exists material_item_save(jsonb);
drop function if exists pt_mat_keeper(uuid, text);
drop function if exists pt_mat_stages();
