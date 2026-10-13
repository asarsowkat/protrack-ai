-- ProTrack schema update v15 (ProTrackAI v3.6): internal weightage by phase, updated schedules, client reporting.
-- 1. Each project keeps an internal weightage for seven phases (general works, design, material, construction,
--    installation, testing and commissioning, project close out) and how the schedule's main WBS branches or a P6
--    activity code map to those phases. Only planning engineers and super admins change it; every change is kept.
-- 2. The planning engineer uploads an updated P6 schedule. The server works out, at the schedule's data date, planned
--    and actual % per phase and overall, by client weightage (the schedule's weighting) and by internal weightage
--    (the phase weights), and the milestone dates. Updates are kept for good: they cannot be changed or deleted.
-- 3. Progress releases are now "internal reports" (kind 'planning', unchanged). A new kind 'client' is the weekly or
--    monthly client report, by client weightage, approved the same way.
-- 4. When a report's progress or milestone dates differ from the latest updated schedule, the server records the
--    differences and the approver must validate them, with a note, before approving.
-- Additive: new tables and functions, three new columns on report_releases, the kind 'client'. Safe to run twice.
-- Undo: schema-rollback-v15.sql.

-- ------------------------------------------------------------------ the seven phases
create or replace function pt_phases() returns text[] language sql immutable as $$
  select array['GEN','DES','MAT','CON','INS','TC','CLO'] $$;

-- ------------------------------------------------------------------ phase weightage and mapping, per project
create table if not exists project_phase_setup (
  project_id text primary key references projects(id) on delete cascade,
  weights jsonb not null default '{}'::jsonb,     -- {"GEN":5,"DES":10,...} in %, adding up to 100
  wbs_map jsonb not null default '{}'::jsonb,     -- {"<main WBS name>":"DES",...}
  code_type text,                                 -- the P6 activity code type that carries the phase, if any
  code_map jsonb not null default '{}'::jsonb,    -- {"<activity code value>":"DES",...}
  updated_by uuid references profiles(id), updated_at timestamptz not null default now());
alter table project_phase_setup enable row level security;
drop policy if exists pps_read on project_phase_setup;
create policy pps_read on project_phase_setup for select using (can_see(project_id));

create table if not exists phase_setup_audit (
  id bigserial primary key,
  project_id text not null references projects(id) on delete cascade,
  before jsonb, after jsonb, note text,
  by_user uuid references profiles(id), by_name text, at_time timestamptz not null default now());
drop trigger if exists trg_psa_append on phase_setup_audit;
create trigger trg_psa_append before update or delete on phase_setup_audit for each row execute function pt_append_only();
drop trigger if exists trg_psa_truncate on phase_setup_audit;
create trigger trg_psa_truncate before truncate on phase_setup_audit execute function pt_no_truncate();
alter table phase_setup_audit enable row level security;
drop policy if exists psa_read on phase_setup_audit;
create policy psa_read on phase_setup_audit for select using (can_see(project_id));

-- ------------------------------------------------------------------ updated schedules (kept for good)
create table if not exists schedule_updates (
  id uuid primary key,
  project_id text not null references projects(id) on delete cascade,
  data_date date not null,
  weightage text not null check (weightage in ('client','internal')),
  file_name text, file_hash text, weight_basis text,
  weights jsonb not null default '{}'::jsonb,      -- the phase weights used
  summary jsonb not null,                          -- worked out by the server, see pt_sched_summary
  uploaded_by uuid references profiles(id), uploaded_name text, uploaded_at timestamptz not null default now());
create unique index if not exists su_one_file on schedule_updates (project_id, file_hash) where file_hash is not null;
create index if not exists su_proj_date on schedule_updates (project_id, data_date desc);
create table if not exists schedule_update_rows (
  update_id uuid not null references schedule_updates(id) on delete cascade deferrable initially deferred,
  project_id text not null,
  act_id text not null,
  name text, wbs text, code text, phase text,
  w numeric not null default 0,                   -- client weight (the schedule's weighting)
  bs date, bf date,                               -- planned start and finish (ProTrackAI baseline when the activity matches)
  pct numeric not null default 0,                 -- actual % complete at the data date
  ms boolean not null default false,
  as_d date, af date, ef date,                    -- actual start, actual finish, forecast (early) finish
  primary key (update_id, act_id));
create index if not exists sur_proj on schedule_update_rows (project_id);
drop trigger if exists trg_su_append on schedule_updates;
create trigger trg_su_append before update or delete on schedule_updates for each row execute function pt_append_only();
drop trigger if exists trg_su_truncate on schedule_updates;
create trigger trg_su_truncate before truncate on schedule_updates execute function pt_no_truncate();
drop trigger if exists trg_sur_append on schedule_update_rows;
create trigger trg_sur_append before update or delete on schedule_update_rows for each row execute function pt_append_only();
drop trigger if exists trg_sur_truncate on schedule_update_rows;
create trigger trg_sur_truncate before truncate on schedule_update_rows execute function pt_no_truncate();
alter table schedule_updates enable row level security;
alter table schedule_update_rows enable row level security;
drop policy if exists su_read on schedule_updates;
create policy su_read on schedule_updates for select using (can_see(project_id));
drop policy if exists sur_read on schedule_update_rows;
create policy sur_read on schedule_update_rows for select using (can_see(project_id));
-- no write policies: only phase_setup_save and schedule_update_commit write

-- ------------------------------------------------------------------ planned % of one activity at a date (linear over its days)
create or replace function pt_plan_frac(bs date, bf date, dd date) returns numeric language sql immutable as $$
  select case when bs is null or bf is null then 0 when dd >= bf then 1 when dd <= bs then 0
              when bf <= bs then case when dd >= bf then 1 else 0 end
              else round((dd - bs)::numeric / (bf - bs), 6) end $$;

-- the summary of an update: per phase and overall, client and internal, milestones, look-ahead
--   client % = sum(weight x %) / sum(weight) over all weighted activities
--   phase % = the same within the phase
--   internal % (schedule loaded with client weightage) = sum(phase weight x phase %) / sum(phase weights of the phases
--   present in the schedule); (schedule loaded with internal weightage) = the schedule's own weighted %
create or replace function pt_sched_summary(uid uuid, dd date, wt text, pw jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_ph jsonb := '[]'::jsonb; x record; tot numeric; cp numeric; ca numeric; ip numeric := 0; ia numeric := 0; iw numeric := 0;
        miss text[] := '{}'; v_ms jsonb; v_la jsonb; n int; nu int; wu numeric; tcc jsonb; pac jsonb; fac jsonb; hasw boolean := false;
begin
  select count(*), count(*) filter (where phase is null), coalesce(sum(w) filter (where phase is null), 0), coalesce(sum(w), 0)
    into n, nu, wu, tot from schedule_update_rows where update_id = uid;
  select case when tot > 0 then round(sum(w * pt_plan_frac(bs, bf, dd)) / tot * 100, 2) end,
         case when tot > 0 then round(sum(w * pct / 100) / tot * 100, 2) end into cp, ca
    from schedule_update_rows where update_id = uid;
  hasw := exists (select 1 from jsonb_each_text(coalesce(pw, '{}'::jsonb)) e where pt_num(e.value) > 0);
  for x in select p.ph, coalesce(sum(r.w), 0) as w, count(r.act_id) as n,
                  case when sum(r.w) > 0 then sum(r.w * pt_plan_frac(r.bs, r.bf, dd)) / sum(r.w) end as plan,
                  case when sum(r.w) > 0 then sum(r.w * r.pct / 100) / sum(r.w) end as act,
                  coalesce(pt_num(pw ->> p.ph), 0) as iw
             from unnest(pt_phases()) with ordinality p(ph, o) left join schedule_update_rows r on r.update_id = uid and r.phase = p.ph
            group by p.ph, p.o order by p.o loop
    v_ph := v_ph || jsonb_build_object('phase', x.ph, 'w', x.w, 'n', x.n, 'plan_pct', round(coalesce(x.plan, 0) * 100, 2), 'act_pct', round(coalesce(x.act, 0) * 100, 2),
                                   'iw', x.iw, 'present', x.w > 0);
    if x.iw > 0 and x.w > 0 then ip := ip + x.iw * x.plan; ia := ia + x.iw * x.act; iw := iw + x.iw;
    elsif x.iw > 0 then miss := miss || x.ph; end if;
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('id', act_id, 'name', name, 'phase', phase, 'plan_date', bf, 'date', coalesce(af, ef, bf), 'actual', af is not null) order by coalesce(af, ef, bf), act_id), '[]'::jsonb)
    into v_ms from (select * from schedule_update_rows where update_id = uid and schedule_update_rows.ms order by coalesce(af, ef, bf), act_id limit 80) m;
  select coalesce(jsonb_agg(jsonb_build_object('id', act_id, 'name', name, 'phase', phase, 'bs', bs, 'bf', bf, 'ef', ef, 'pct', pct) order by bs, act_id), '[]'::jsonb)
    into v_la from (select * from schedule_update_rows where update_id = uid and not schedule_update_rows.ms and pct < 100 and coalesce(bs, ef) <= dd + 30 and coalesce(ef, bf) >= dd
                   order by bs, act_id limit 25) l;
  select jsonb_build_object('date', coalesce(af, ef, bf), 'actual', af is not null) into tcc from schedule_update_rows
   where update_id = uid and schedule_update_rows.ms and (name ~* '(^|[^a-z])tcc([^a-z]|$)|taking[ -]?over|completion certificate') order by coalesce(af, ef, bf) limit 1;
  select jsonb_build_object('date', coalesce(af, ef, bf), 'actual', af is not null) into pac from schedule_update_rows
   where update_id = uid and schedule_update_rows.ms and (name ~* '(^|[^a-z])pac([^a-z]|$)|provisional acceptance') order by coalesce(af, ef, bf) limit 1;
  select jsonb_build_object('date', coalesce(af, ef, bf), 'actual', af is not null) into fac from schedule_update_rows
   where update_id = uid and schedule_update_rows.ms and (name ~* '(^|[^a-z])fac([^a-z]|$)|final acceptance') order by coalesce(af, ef, bf) limit 1;
  return jsonb_build_object('data_date', dd, 'weightage', wt, 'n', n, 'n_unmapped', nu, 'w_unmapped', wu, 'w_total', tot, 'phases', v_ph,
    'client_plan', case when wt = 'client' then cp end, 'client_act', case when wt = 'client' then ca end,
    'int_plan', case when wt = 'internal' then cp when hasw and iw > 0 then round(ip / iw * 100, 2) end,
    'int_act', case when wt = 'internal' then ca when hasw and iw > 0 then round(ia / iw * 100, 2) end,
    'int_basis', case when wt = 'internal' then 'schedule loaded with internal weightage' when hasw and iw > 0 then 'phase weights' else 'none' end,
    'missing_phases', to_jsonb(miss),
    'tcc_date', tcc ->> 'date', 'tcc_actual', coalesce((tcc ->> 'actual')::boolean, false),
    'pac_date', pac ->> 'date', 'pac_actual', coalesce((pac ->> 'actual')::boolean, false),
    'fac_date', fac ->> 'date', 'fac_actual', coalesce((fac ->> 'actual')::boolean, false),
    'milestones', v_ms, 'lookahead', v_la);
end $$;

-- ------------------------------------------------------------------ who keeps the weightage and uploads schedules
create or replace function pt_sched_keeper(u uuid, pid text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) = 'sa' or (role_of(u) = 'plan' and user_sees(u, pid)), false) $$;

-- p: {project_id, weights:{GEN..CLO: %}, wbs_map:{name: phase}, code_type, code_map:{value: phase}, note}
create or replace function phase_setup_save(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); pid text := p ->> 'project_id'; w jsonb := coalesce(p -> 'weights', '{}'::jsonb);
        wm jsonb := coalesce(p -> 'wbs_map', '{}'::jsonb); cm jsonb := coalesce(p -> 'code_map', '{}'::jsonb);
        e record; s numeric := 0; v numeric; old project_phase_setup; nw jsonb := '{}'::jsonb; note text := nullif(btrim(coalesce(p ->> 'note', '')), '');
begin
  if me is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if pid is null or not user_sees(me, pid) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
  if not pt_sched_keeper(me, pid) then raise exception 'Only a planning engineer of this project or a super admin sets the internal weightage' using errcode = '42501'; end if;
  if jsonb_typeof(w) <> 'object' or jsonb_typeof(wm) <> 'object' or jsonb_typeof(cm) <> 'object' then raise exception 'The weightage and the mapping must be lists of names and values'; end if;
  for e in select * from jsonb_each_text(w) loop
    if not (e.key = any(pt_phases())) then raise exception 'Unknown phase %', e.key; end if;
    if pt_bad_num(e.value) then raise exception 'The weightage of % must be a number', e.key; end if;
    v := coalesce(pt_num(e.value), 0); if v < 0 or v > 100 then raise exception 'The weightage of % must be between 0 and 100', e.key; end if;
    s := s + v; nw := nw || jsonb_build_object(e.key, v);
  end loop;
  if s > 0 and abs(s - 100) > 0.01 then raise exception 'The internal weightage must add up to 100%% (now %)', round(s, 2) || '%'; end if;
  for e in select * from jsonb_each_text(wm) loop
    if length(e.key) > 200 then raise exception 'A WBS name is too long'; end if;
    if nullif(e.value, '') is not null and not (e.value = any(pt_phases())) then raise exception 'Unknown phase % for %', e.value, e.key; end if;
  end loop;
  for e in select * from jsonb_each_text(cm) loop
    if length(e.key) > 200 then raise exception 'An activity code value is too long'; end if;
    if nullif(e.value, '') is not null and not (e.value = any(pt_phases())) then raise exception 'Unknown phase % for %', e.value, e.key; end if;
  end loop;
  if length(coalesce(p ->> 'code_type', '')) > 100 then raise exception 'The activity code name is too long'; end if;
  select * into old from project_phase_setup where project_id = pid for update;
  if old.project_id is not null and old.weights is distinct from nw and old.weights <> '{}'::jsonb
     and exists (select 1 from schedule_updates where project_id = pid) and note is null then
    raise exception 'Give a reason for changing the internal weightage: updated schedules were already reported with it'; end if;
  insert into project_phase_setup (project_id, weights, wbs_map, code_type, code_map, updated_by, updated_at)
  values (pid, nw, wm, nullif(btrim(coalesce(p ->> 'code_type', '')), ''), cm, me, now())
  on conflict (project_id) do update set weights = excluded.weights, wbs_map = excluded.wbs_map, code_type = excluded.code_type,
     code_map = excluded.code_map, updated_by = me, updated_at = now();
  insert into phase_setup_audit (project_id, before, after, note, by_user, by_name)
  values (pid, case when old.project_id is null then null else jsonb_build_object('weights', old.weights, 'wbs_map', old.wbs_map, 'code_type', old.code_type, 'code_map', old.code_map) end,
          jsonb_build_object('weights', nw, 'wbs_map', wm, 'code_type', nullif(btrim(coalesce(p ->> 'code_type', '')), ''), 'code_map', cm), note, me, name_of(me));
  return to_jsonb((select x from project_phase_setup x where x.project_id = pid));
end $$;

-- p: {project_id, data_date, weightage: client|internal, file_name, file_hash, weight_basis,
--     rows: [{id, name, wbs (main WBS), code (activity code value), w, bs, bf, pct, ms, as, af, ef}]}
-- the phase of each activity comes from the project's mapping: activity code first, then main WBS
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

-- the latest updated schedule of a project up to a date (for client reports: the latest one loaded with client weightage)
create or replace function pt_period_end(per text, typ text) returns date language sql immutable as $$
  select case when typ = 'month' and per ~ '^\d{4}-\d{2}$' then ((per || '-01')::date + interval '1 month' - interval '1 day')::date
              when typ = 'week' and per ~ '^\d{4}-W\d{2}$' then to_date(per, 'IYYY-"W"IW') + 6 end $$;

-- the figures of a report against the latest updated schedule: the server writes the sched_* figures and the differences
create or replace function pt_rel_sched(pid text, k text, pt text, per text, f jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare u schedule_updates; s jsonb; sp numeric; sa numeric; d text[] := '{}'; mine numeric; key text; m text; fk text;
begin
  select * into u from schedule_updates where project_id = pid and data_date <= pt_period_end(per, pt)
     and (k <> 'client' or weightage = 'client') order by data_date desc, uploaded_at desc limit 1;
  if u.id is null then return f; end if;
  s := u.summary;
  if k = 'client' then sp := pt_num(s ->> 'client_plan'); sa := pt_num(s ->> 'client_act');
  else sp := pt_num(s ->> 'int_plan'); sa := pt_num(s ->> 'int_act'); end if;
  if sp is not null then
    mine := pt_num(f ->> case when k = 'client' then 'plan_pct' else 'planned_pct' end);
    if mine is not null and abs(mine - sp) > 0.05 then d := d || format('planned %s%% (schedule %s%%)', round(mine, 1), round(sp, 1)); end if;
  end if;
  if sa is not null then
    mine := pt_num(f ->> case when k = 'client' then 'act_pct' else 'actual_pct' end);
    if mine is not null and abs(mine - sa) > 0.05 then d := d || format('actual %s%% (schedule %s%%)', round(mine, 1), round(sa, 1)); end if;
  end if;
  foreach m in array array['tcc','pac','fac'] loop
    fk := case when k = 'client' then m || '_fc_date' else m || '_ext_fc_date' end;
    if pt_date(s ->> (m || '_date')) is not null and pt_date(f ->> fk) is not null and pt_date(f ->> fk) <> pt_date(s ->> (m || '_date')) then
      d := d || format('%s forecast %s (schedule %s)', upper(m), f ->> fk, s ->> (m || '_date')); end if;
  end loop;
  return f || jsonb_build_object('sched_update_text', u.id::text, 'sched_data_date', u.data_date, 'sched_plan_pct', sp, 'sched_act_pct', sa,
    'sched_tcc_date', s ->> 'tcc_date', 'sched_pac_date', s ->> 'pac_date', 'sched_fac_date', s ->> 'fac_date',
    'sched_basis_text', case when k = 'client' then 'client weightage' else coalesce(s ->> 'int_basis', 'none') end,
    'sched_diff_n', coalesce(array_length(d, 1), 0), 'sched_diff_text', left(array_to_string(d, '; '), 300));
end $$;

-- the client report: client progress (checked), variance and SPI worked out, phases, milestones and look-ahead from the schedule
create or replace function pt_rel_client_calc(pid text, pt text, per text, f jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare k text; v numeric; u schedule_updates;
begin
  foreach k in array array['plan_pct','act_pct'] loop
    v := pt_num(f ->> k); if v is not null and (v < 0 or v > 100) then raise exception '% must be between 0 and 100', k; end if;
  end loop;
  if pt_num(f ->> 'act_pct') is null then raise exception 'Enter the actual progress'; end if;
  foreach k in array array['mp_plan','mp_act'] loop
    v := pt_num(f ->> k); if v is not null and v < 0 then raise exception '% cannot be negative', k; end if;
  end loop;
  f := f - 'phases' - 'milestones' - 'lookahead';
  select * into u from schedule_updates where project_id = pid and weightage = 'client' and data_date <= pt_period_end(per, pt) order by data_date desc, uploaded_at desc limit 1;
  return f || jsonb_build_object(
    'var_pct', case when pt_num(f ->> 'plan_pct') is not null then round(pt_num(f ->> 'act_pct') - pt_num(f ->> 'plan_pct'), 2) end,
    'spi', case when coalesce(pt_num(f ->> 'plan_pct'), 0) > 0 then round(pt_num(f ->> 'act_pct') / pt_num(f ->> 'plan_pct'), 3) end,
    'phases', coalesce((select jsonb_agg(jsonb_build_object('phase', x ->> 'phase', 'plan_pct', x -> 'plan_pct', 'act_pct', x -> 'act_pct'))
                          from jsonb_array_elements(u.summary -> 'phases') x where (x ->> 'present')::boolean), '[]'::jsonb),
    'milestones', coalesce(u.summary -> 'milestones', '[]'::jsonb), 'lookahead', coalesce(u.summary -> 'lookahead', '[]'::jsonb));
end $$;

-- ------------------------------------------------------------------ report_releases: the client report and validation
alter table report_releases drop constraint if exists report_releases_kind_check;
alter table report_releases add constraint report_releases_kind_check check (kind in ('planning','cost','client'));
alter table report_releases add column if not exists sched_validated_by uuid references profiles(id);
alter table report_releases add column if not exists sched_validated_at timestamptz;
alter table report_releases add column if not exists sched_validation_note text;

create or replace function pt_release_staff(u uuid, k text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) = 'sa' or pt_is_head(u) or (k in ('planning','client') and role_of(u) = 'plan')
                  or (k = 'cost' and (role_of(u) = 'costing' or pt_is_coord(u))), false) $$;
create or replace function pt_release_preparer(u uuid, k text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) = 'sa' or (k in ('planning','client') and role_of(u) = 'plan') or (k = 'cost' and (role_of(u) = 'costing' or pt_is_coord(u))), false) $$;

create or replace function pt_release_frozen() returns trigger language plpgsql as $$
begin
  if old.status in ('Released','Superseded') and (new.figures is distinct from old.figures or new.overrides is distinct from old.overrides
     or new.narrative is distinct from old.narrative or new.period is distinct from old.period or new.project_id is distinct from old.project_id
     or new.rev is distinct from old.rev or new.issues_snapshot is distinct from old.issues_snapshot or new.data_date is distinct from old.data_date or new.approved_by is distinct from old.approved_by
     or new.reviewed_by is distinct from old.reviewed_by or new.reviewed_at is distinct from old.reviewed_at or new.review_note is distinct from old.review_note
     or new.sched_validated_by is distinct from old.sched_validated_by or new.sched_validated_at is distinct from old.sched_validated_at
     or new.sched_validation_note is distinct from old.sched_validation_note
     or (old.status = 'Superseded' and new.status <> 'Superseded') or (old.status = 'Released' and new.status not in ('Released','Superseded'))) then
    raise exception 'A released version cannot be changed; issue a new revision' using errcode = '42501';
  end if;
  return new;
end $$;

drop policy if exists rr_read on report_releases;
create policy rr_read on report_releases for select using (
  can_see(project_id) and (kind <> 'cost' or pt_money_ok()) and (status in ('Released','Superseded') or pt_release_staff(auth.uid(), kind)
    or (kind in ('planning','client') and status = 'Submitted' and pt_rel_decider(auth.uid(), project_id))));

create or replace function release_act(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r text := role_of(auth.uid()); a text := p ->> 'action';
        note text := nullif(btrim(coalesce(p ->> 'note', '')), ''); rel report_releases; cur report_releases;
        pid text; k text; pt text; per text; f jsonb := coalesce(p -> 'figures', '{}'::jsonb); o jsonb := coalesce(p -> 'overrides', '[]'::jsonb);
        nar jsonb := coalesce(p -> 'narrative', '{}'::jsonb); x jsonb; key text; v numeric; budget numeric; supp numeric; nr int; pmr boolean := pt_rel_pm_review();
        vnote text := nullif(btrim(coalesce(p ->> 'validation_note', '')), '');
begin
  if me is null or r is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if a is null or a not in ('save','submit','review','approve','return','revise') then raise exception 'Unknown action %', a; end if;
  if nullif(p ->> 'id', '') is not null then
    select * into rel from report_releases where id = (p ->> 'id')::uuid for update;
    if rel.id is null then raise exception 'Unknown release'; end if;
    pid := rel.project_id; k := rel.kind; pt := rel.period_type; per := rel.period;
  else
    pid := p ->> 'project_id'; k := p ->> 'kind'; pt := coalesce(p ->> 'period_type', 'month'); per := p ->> 'period';
  end if;
  if pid is null or not user_sees(me, pid) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
  if (select status from projects where id = pid) = 'Cancelled' then raise exception 'This project was cancelled' using errcode = '42501'; end if;
  if k is null or k not in ('planning','cost','client') then raise exception 'Unknown release kind'; end if;
  if k = 'cost' and pt <> 'month' then raise exception 'Cost reports are monthly'; end if;
  if not pt_period_ok(per, pt) then raise exception 'The period must look like % ', case pt when 'week' then '2026-W38' else '2026-09' end; end if;
  perform pg_advisory_xact_lock(hashtext('protrack:rel:' || pid || ':' || k || ':' || pt || ':' || per));

  if a in ('save','revise') then
    if not pt_release_preparer(me, k) then
      raise exception '%', case k when 'planning' then 'Only a planning engineer or a super admin prepares internal reports'
                                  when 'client' then 'Only a planning engineer or a super admin prepares client reports'
                                  else 'Only a costing engineer, the costing coordinator or a super admin prepares cost reports' end using errcode = '42501'; end if;
  end if;

  if a = 'revise' then
    select * into cur from report_releases where project_id = pid and kind = k and period_type = pt and period = per and status = 'Released';
    if cur.id is null then raise exception 'There is no released version of this period to revise'; end if;
    if exists (select 1 from report_releases where project_id = pid and kind = k and period_type = pt and period = per and status in ('Draft','Submitted')) then
      raise exception 'A new revision of this period is already being prepared'; end if;
    if note is null then raise exception 'Add a comment saying why the released version is being revised'; end if;
    insert into report_releases (project_id, kind, period_type, period, rev, status, data_date, figures, overrides, narrative, revise_reason, prepared_by)
    values (pid, k, pt, per, cur.rev + 1, 'Draft', cur.data_date, cur.figures, cur.overrides, cur.narrative, note, me) returning * into rel;
    perform pt_rel_log(rel.id, 'Revision started', note, jsonb_build_object('from_rev', cur.rev));
    return to_jsonb(rel);
  end if;

  if a = 'save' then
    if rel.id is null then
      select * into rel from report_releases where project_id = pid and kind = k and period_type = pt and period = per and status in ('Draft','Submitted') for update;
    end if;
    if rel.id is not null and rel.status <> 'Draft' then raise exception 'This version is % and cannot be edited', lower(rel.status); end if;
    if rel.id is null and exists (select 1 from report_releases where project_id = pid and kind = k and period_type = pt and period = per and status = 'Released') then
      raise exception 'This period is already released; use Revise to issue a new revision'; end if;
    if pt_bad_date(p ->> 'data_date') then raise exception 'The data date is not a valid date'; end if;
    -- v15: the schedule figures are always written by the server, never taken from the app
    f := f - coalesce((select array_agg(kk) from jsonb_object_keys(f) kk where kk like 'sched\_%'), '{}'::text[]);
    if k = 'client' then f := f - 'phases' - 'milestones' - 'lookahead'; end if;
    -- figures: numbers only, in range
    for key in select jsonb_object_keys(f) loop
      if key = 'wbs' then continue; end if;   -- v12: the WBS lines are checked by pt_cost_wbs
      if key ~ '(_date|finish)$' then
        if pt_bad_date(f ->> key) then raise exception 'Figure % is not a valid date', key; end if;
      elsif key ~ '_text$' then
        if length(coalesce(f ->> key, '')) > 300 then raise exception 'Figure % is too long', key; end if;
      elsif jsonb_typeof(f -> key) not in ('number','null') and pt_bad_num(f ->> key) then raise exception 'Figure % must be a number', key;
      end if;
    end loop;
    if k = 'planning' then
      foreach key in array array['planned_pct','actual_pct','eng_pct','prc_pct','eng_plan_pct','prc_plan_pct'] loop
        v := pt_num(f ->> key); if v is not null and (v < 0 or v > 100) then raise exception '% must be between 0 and 100', key; end if;
      end loop;
      if pt_num(f ->> 'actual_pct') is null then raise exception 'Enter the actual progress'; end if;
      f := pt_rel_plan_calc(pid, f);
      f := pt_rel_sched(pid, k, pt, per, f);
    elsif k = 'client' then
      f := pt_rel_client_calc(pid, pt, per, f);
      f := pt_rel_sched(pid, k, pt, per, f);
    elsif f ? 'wbs' then
      if f ? 'wbs' and k = 'cost' then
        foreach key in array array['inv_invoiceable','inv_submitted','inv_approved','inv_collected'] loop
          v := pt_num(f ->> key); if v is not null and v < 0 then raise exception '% cannot be negative', key; end if;
        end loop;
        f := pt_cost_wbs(pid, per, f);
      end if;
    else
      foreach key in array array['budget_rev0','actual','commitment','ftc'] loop
        v := pt_num(f ->> key);
        if v is null then raise exception 'Enter %', case key when 'budget_rev0' then 'the Rev-0 budget' when 'actual' then 'the actual cost to date' when 'commitment' then 'the commitments' else 'the forecast cost to complete' end; end if;
        if v < 0 then raise exception '% cannot be negative', key; end if;
      end loop;
      foreach key in array array['inv_invoiceable','inv_submitted','inv_approved','inv_collected'] loop
        v := pt_num(f ->> key); if v is not null and v < 0 then raise exception '% cannot be negative', key; end if;
      end loop;
      supp := pt_supp_approved(pid, per);
      budget := pt_num(f ->> 'budget_rev0') + supp;
      f := f || jsonb_build_object('supplements_approved', supp, 'budget_current', budget,
                                   'eac', pt_num(f ->> 'actual') + pt_num(f ->> 'ftc'),
                                   'vac', budget - (pt_num(f ->> 'actual') + pt_num(f ->> 'ftc')));
    end if;
    if jsonb_typeof(o) <> 'array' then raise exception 'Overrides must be a list'; end if;
    for x in select * from jsonb_array_elements(o) loop
      if nullif(btrim(coalesce(x ->> 'reason', '')), '') is null then raise exception 'Give a reason for changing %', coalesce(x ->> 'label', x ->> 'field', 'a figure'); end if;
    end loop;
    if length(nar::text) > 12000 then raise exception 'The comments are too long'; end if;
    if rel.id is null then
      insert into report_releases (project_id, kind, period_type, period, rev, status, data_date, figures, overrides, narrative, prepared_by)
      values (pid, k, pt, per, coalesce((select max(rev) + 1 from report_releases where project_id = pid and kind = k and period_type = pt and period = per), 0),
              'Draft', pt_date(p ->> 'data_date'), f, o, nar, me) returning * into rel;
      perform pt_rel_log(rel.id, 'Prepared', null, jsonb_build_object('rev', rel.rev));
    else
      update report_releases set figures = f, overrides = o, narrative = nar, data_date = pt_date(p ->> 'data_date'), prepared_by = me, updated_at = now()
       where id = rel.id returning * into rel;
      perform pt_rel_log(rel.id, 'Updated', null, null);
    end if;
    return to_jsonb(rel);
  end if;

  if rel.id is null then
    select * into rel from report_releases where project_id = pid and kind = k and period_type = pt and period = per and status in ('Draft','Submitted') for update;
    if rel.id is null then raise exception 'Nothing is being prepared for this period'; end if;
  end if;

  if a = 'submit' then
    if not pt_release_preparer(me, k) then raise exception 'Only the people who prepare this report can submit it' using errcode = '42501'; end if;
    if rel.status <> 'Draft' then raise exception 'Only a draft can be submitted; this version is %', lower(rel.status); end if;
    if rel.kind = 'cost' and jsonb_typeof(rel.figures -> 'wbs') = 'array' then
      select string_agg(y ->> 'code', ', ') into key from jsonb_array_elements(rel.figures -> 'wbs') y
       where abs(coalesce(pt_num(y ->> 'var'), 0)) >= 1 and nullif(btrim(coalesce(y ->> 'justification', '')), '') is null;
      if key is not null then raise exception 'Give a justification for each WBS line with a supplement or saving before submitting: %', key; end if;
    end if;
    update report_releases set status = 'Submitted', submitted_by = me, submitted_at = now(), reviewed_by = null, reviewed_at = null, review_note = null,
           sched_validated_by = null, sched_validated_at = null, sched_validation_note = null, updated_at = now() where id = rel.id returning * into rel;
    perform pt_rel_log(rel.id, 'Submitted for approval', note,
      case when coalesce(pt_num(rel.figures ->> 'sched_diff_n'), 0) > 0 then jsonb_build_object('differs_from_schedule', rel.figures ->> 'sched_diff_text') end);
  elsif a = 'review' then
    if rel.kind <> 'planning' then raise exception 'Only internal reports have a review step'; end if;
    if not pmr then raise exception 'The project manager review step is not switched on'; end if;
    if not (r = 'sa' or (r = 'pm' and user_sees(me, rel.project_id))) then raise exception 'Only the project manager of this project reviews it' using errcode = '42501'; end if;
    if rel.status <> 'Submitted' then raise exception 'Only a submitted version can be reviewed'; end if;
    if rel.reviewed_by is not null then raise exception 'This version is already reviewed'; end if;
    if rel.submitted_by = me then raise exception 'You submitted this version, so someone else must review it' using errcode = '42501'; end if;
    update report_releases set reviewed_by = me, reviewed_at = now(), review_note = note, updated_at = now() where id = rel.id returning * into rel;
    perform pt_rel_log(rel.id, 'Reviewed by the project manager', note, null);
  elsif a = 'approve' then
    if rel.kind in ('planning','client') then
      if not pt_rel_approver(me, rel.project_id) then raise exception 'Only the Head of Planning and Cost Control, the regional planning section manager or a super admin can approve this report' using errcode = '42501'; end if;
    elsif not (r = 'sa' or pt_is_head(me)) then raise exception 'Only the Head of Planning and Cost Control or a super admin can approve a release' using errcode = '42501'; end if;
    if rel.status <> 'Submitted' then raise exception 'Only a submitted version can be approved'; end if;
    if rel.submitted_by = me then raise exception 'You submitted this version, so someone else must approve it' using errcode = '42501'; end if;
    if rel.kind = 'planning' and pmr and rel.reviewed_by is null then raise exception 'The project manager must review this report before it is approved'; end if;
    -- v15: differences from the updated schedule are validated by the approver, with a note
    if coalesce(pt_num(rel.figures ->> 'sched_diff_n'), 0) > 0 then
      if coalesce((p ->> 'validated')::boolean, false) is not true or vnote is null then
        raise exception 'This report differs from the updated schedule (%). Validate the differences with a note before approving', rel.figures ->> 'sched_diff_text'; end if;
      if length(vnote) > 1000 then raise exception 'The validation note is too long'; end if;
      update report_releases set sched_validated_by = me, sched_validated_at = now(), sched_validation_note = vnote where id = rel.id;
      perform pt_rel_log(rel.id, 'Differences from the updated schedule validated', vnote, jsonb_build_object('differences', rel.figures ->> 'sched_diff_text'));
    end if;
    if rel.kind = 'planning' and nullif(btrim(coalesce(p ->> 'mgmt', '')), '') is not null then
      if length(p ->> 'mgmt') > 2000 then raise exception 'The management remarks are too long'; end if;
      update report_releases set narrative = coalesce(narrative, '{}'::jsonb) || jsonb_build_object('mgmt', btrim(p ->> 'mgmt')) where id = rel.id;
    end if;
    update report_releases set status = 'Superseded', updated_at = now()
     where project_id = rel.project_id and kind = rel.kind and period_type = rel.period_type and period = rel.period and status = 'Released';
    update report_releases set status = 'Released', approved_by = me, approved_at = now(), updated_at = now(),
           reviewed_by = coalesce(reviewed_by, case when rel.kind = 'planning' then me end), reviewed_at = coalesce(reviewed_at, case when rel.kind = 'planning' then now() end),
           issues_snapshot = case when rel.kind = 'planning' then pt_issue_snapshot(rel.project_id) else issues_snapshot end
     where id = rel.id returning * into rel;
    perform pt_rel_log(rel.id, 'Approved and released', note, jsonb_build_object('rev', rel.rev));
  elsif a = 'return' then
    if rel.kind in ('planning','client') then
      if not (pt_rel_approver(me, rel.project_id) or (rel.kind = 'planning' and pmr and r = 'pm' and user_sees(me, rel.project_id) and rel.reviewed_by is null)) then
        raise exception 'Only the Head of Planning and Cost Control, the regional planning section manager or a super admin can return this report' using errcode = '42501'; end if;
    elsif not (r = 'sa' or pt_is_head(me)) then raise exception 'Only the Head of Planning and Cost Control or a super admin can return a release' using errcode = '42501'; end if;
    if rel.status <> 'Submitted' then raise exception 'Only a submitted version can be returned'; end if;
    if note is null then raise exception 'Add a comment saying what to fix'; end if;
    update report_releases set status = 'Draft', submitted_by = null, submitted_at = null, reviewed_by = null, reviewed_at = null, review_note = null, updated_at = now() where id = rel.id returning * into rel;
    perform pt_rel_log(rel.id, 'Returned', note, null);
  end if;
  return to_jsonb(rel);
end $$;

revoke execute on function pt_sched_summary(uuid, date, text, jsonb), pt_rel_sched(text, text, text, text, jsonb), pt_rel_client_calc(text, text, text, jsonb) from public, anon, authenticated;
revoke execute on function phase_setup_save(jsonb), schedule_update_commit(jsonb), release_act(jsonb), pt_sched_keeper(uuid, text) from public, anon;
grant execute on function phase_setup_save(jsonb), schedule_update_commit(jsonb), release_act(jsonb), pt_sched_keeper(uuid, text), pt_phases(), pt_plan_frac(date, date, date), pt_period_end(text, text) to authenticated;
grant select on project_phase_setup, phase_setup_audit, schedule_updates, schedule_update_rows to authenticated;
