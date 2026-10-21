-- ProTrack schema update v30 (ProTrackAI v3.23): intermediate milestones from the P6 schedule, and progress by phase.
-- 1. Energization is a phase of its own: pt_phases() lists GEN, DES, MAT, CON, INS, TC, EN, CLO. The internal weightage
--    (phase_setup_save) and the schedule summaries of new uploads (pt_sched_summary) take it from here; a summary saved
--    before keeps its seven phases.
-- 2. key_milestones: per project, the intermediate milestones the project manager or the client asked for (design
--    completion, civil start, ...). Each is an activity or milestone of the P6 schedule (src 'act', ref = activity ID)
--    or the first start or last finish of a WBS element (src 'wbs', ref = main WBS name, or "main|leaf"), shown in the
--    internal report, the client report or both. key_milestone_act(p) = {action: 'add' | 'remove', project_id, item, id},
--    as the app's kmsActLocal(): only a planning engineer of the project or a super admin (pt_sched_keeper); the activity
--    or WBS element must be in the latest updated schedule; names unique per project; up to 40. A removed milestone is
--    kept, marked inactive; every change is in key_milestone_audit.
-- 3. pt_key_ms(project, kind, period type, period): each milestone's baseline, forecast, actual and delay from the
--    updated schedule in force at the end of the period (client weightage for a client report), as kmsFor().
--    Baseline = the baseline dates of the schedule's activities (bs, bf); actual = as_d, af; forecast = es, ef.
--    A WBS start: first baseline start, first actual start, else the first forecast start. A WBS finish: last baseline
--    finish; actual once every activity has finished; else the last forecast finish. Delay = forecast (or actual) − baseline.
-- 4. pt_phase_tbl(project, kind, period type, period): progress by phase as phaseTbl(): each phase's weight (internal
--    weightage, or the share of the schedule's own weighting for a client report or when no internal weightage is set),
--    planned and actual %, variance and weighted contribution, the overall progress; for an internal report, the site
--    phases (CON, INS, TC, EN) compared with the daily reports (submitted, reviewed or approved, up to the schedule's data
--    date) on the activities the two share, weighted as in the schedule.
-- 5. release_act_km(p) takes the same p as release_act_bl (v22). It takes key_ms and phase_tbl out of the figures, lets
--    release_act_bl do everything it does today and, on a save of an internal or client report, writes the server's own
--    key_ms and phase_tbl into the saved figures. Approval freezes them (pt_release_frozen); Revise copies them.
-- Needs schema-update-v22.sql (release_act_bl) and v17 (es, wbs_leaf). Additive. Safe to run twice.
-- Undo: schema-rollback-v30.sql.

do $$ begin
  if to_regprocedure('public.release_act_bl(jsonb)') is null then raise exception 'Run schema-update-v22.sql (STAGE-18-SETUP) first, then this update'; end if;
end $$;

-- ------------------------------------------------------------------ 1. the eight phases
create or replace function pt_phases() returns text[] language sql immutable as $$
  select array['GEN','DES','MAT','CON','INS','TC','EN','CLO'] $$;

-- ------------------------------------------------------------------ 2. intermediate milestones, per project
create table if not exists key_milestones (
  id text primary key,                                   -- KM-<project>-001
  project_id text not null references projects(id) on delete cascade,
  name text not null check (length(name) between 1 and 80),
  req text not null check (req in ('pm','client','both')),               -- asked by
  show_in text not null check (show_in in ('both','internal','client')), -- the reports it shows in
  src text not null check (src in ('wbs','act')),
  ref text not null check (length(ref) between 1 and 400),
  ev text not null check (ev in ('start','finish')),
  ms boolean not null default false,                     -- a P6 milestone (its own date, start or finish)
  act_name text, note text,
  active boolean not null default true,
  by_user uuid references profiles(id), by_name text, at_time timestamptz not null default now(),
  removed_by uuid references profiles(id), removed_at timestamptz);
create unique index if not exists key_milestones_name on key_milestones (project_id, lower(name)) where active;
create table if not exists key_milestone_audit (id bigserial primary key, project_id text not null, km_id text not null, action text not null, name text,
  by_user uuid references profiles(id), by_name text, at_time timestamptz not null default now());
alter table key_milestones enable row level security;
alter table key_milestone_audit enable row level security;
drop policy if exists key_milestones_read on key_milestones;
create policy key_milestones_read on key_milestones for select using (can_see(project_id));
drop policy if exists key_milestone_audit_read on key_milestone_audit;
create policy key_milestone_audit_read on key_milestone_audit for select using (can_see(project_id));
revoke all on key_milestones, key_milestone_audit from anon;
revoke insert, update, delete, truncate on key_milestones, key_milestone_audit from authenticated;
grant select on key_milestones, key_milestone_audit to authenticated;

-- the updated schedule in force at a date (client weightage only, when wt = 'client')
create or replace function pt_km_update(pid text, wt text, d date) returns uuid language sql stable security definer set search_path = public as $$
  select id from schedule_updates where project_id = pid and data_date <= d and (wt is null or weightage = wt)
   order by data_date desc, uploaded_at desc limit 1 $$;

-- p: {action: 'add', project_id, item: {name, req, use, src, ref, ev, note}} or {action: 'remove', project_id, id}
create or replace function key_milestone_act(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); pid text := p ->> 'project_id'; a text := p ->> 'action'; it jsonb := coalesce(p -> 'item', '{}'::jsonb);
        nm text; rf text; src text; ev text; uid uuid; r schedule_update_rows; n int; k key_milestones; who text;
begin
  if me is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if pid is null or not user_sees(me, pid) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
  if not pt_sched_keeper(me, pid) then raise exception 'Only a planning engineer of this project or a super admin keeps the intermediate milestones' using errcode = '42501'; end if;
  select name into who from profiles where id = me;
  perform pg_advisory_xact_lock(hashtext('protrack:km:' || pid));
  if a = 'add' then
    nm := regexp_replace(btrim(coalesce(it ->> 'name', '')), '\s+', ' ', 'g'); rf := btrim(coalesce(it ->> 'ref', '')); src := it ->> 'src'; ev := it ->> 'ev';
    if nm = '' then raise exception 'Give the milestone a name, for example Design completion'; end if;
    if length(nm) > 80 then raise exception 'The name is longer than 80 characters'; end if;
    if coalesce(it ->> 'req', '') not in ('pm','client','both') then raise exception 'Say who asked for this milestone'; end if;
    if coalesce(it ->> 'use', '') not in ('both','internal','client') then raise exception 'Choose the reports it shows in'; end if;
    if coalesce(src, '') not in ('wbs','act') then raise exception 'Choose a WBS element or an activity of the schedule'; end if;
    if rf = '' then raise exception '%', case when src = 'wbs' then 'Choose a WBS element of the schedule' else 'Choose an activity or milestone of the schedule' end; end if;
    if length(rf) > 400 then raise exception 'The WBS element or activity is too long'; end if;
    if coalesce(ev, '') not in ('start','finish') then raise exception 'Choose the start or the finish'; end if;
    uid := pt_km_update(pid, null, current_date);
    if uid is null then raise exception 'Load an updated schedule first (Baselines and P6 import)'; end if;
    if src = 'act' then
      select * into r from schedule_update_rows where update_id = uid and act_id = rf;
      if r.act_id is null then raise exception 'Activity % is not in the latest updated schedule', rf; end if;
    elsif not exists (select 1 from schedule_update_rows x where x.update_id = uid and not x.ms
                       and (coalesce(x.wbs, '') = rf or (coalesce(x.wbs, '') || '|' || coalesce(x.wbs_leaf, '')) = rf)) then
      raise exception '% is not a WBS element of the updated schedule', replace(rf, '|', ' › ');
    end if;
    if exists (select 1 from key_milestones where project_id = pid and active and lower(name) = lower(nm)) then
      raise exception 'There is already a milestone named % on this project', nm; end if;
    if (select count(*) from key_milestones where project_id = pid and active) >= 40 then raise exception 'A project keeps up to 40 intermediate milestones'; end if;
    select count(*) + 1 into n from key_milestones where project_id = pid;
    insert into key_milestones (id, project_id, name, req, show_in, src, ref, ev, ms, act_name, note, by_user, by_name)
      values ('KM-' || pid || '-' || lpad(n::text, 3, '0'), pid, nm, it ->> 'req', it ->> 'use', src, rf,
              case when coalesce(r.ms, false) then 'finish' else ev end, coalesce(r.ms, false), left(r.name, 200),
              nullif(left(btrim(coalesce(it ->> 'note', '')), 300), ''), me, who)
      returning * into k;
    insert into key_milestone_audit (project_id, km_id, action, name, by_user, by_name) values (pid, k.id, 'Added', k.name, me, who);
    return to_jsonb(k) || jsonb_build_object('use', k.show_in);
  elsif a = 'remove' then
    update key_milestones set active = false, removed_by = me, removed_at = now() where id = p ->> 'id' and project_id = pid and active returning * into k;
    if k.id is null then raise exception 'This milestone is not on the project'; end if;
    insert into key_milestone_audit (project_id, km_id, action, name, by_user, by_name) values (pid, k.id, 'Removed', k.name, me, who);
    return to_jsonb(k) || jsonb_build_object('use', k.show_in);
  end if;
  raise exception 'Unknown action';
end $$;

-- ------------------------------------------------------------------ 3. the milestones of a report
create or replace function pt_key_ms(pid text, k text, pt text, per text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid; dd date; d key_milestones; acc jsonb := '[]'::jsonb; pl date; fc date; ac date; n int; isms boolean; m text; l text; i int; why text;
begin
  uid := pt_km_update(pid, case when k = 'client' then 'client' end, pt_period_end(per, pt));
  select data_date into dd from schedule_updates where id = uid;
  for d in select * from key_milestones where project_id = pid and active
             and (show_in = 'both' or show_in = case when k = 'client' then 'client' else 'internal' end) loop
    pl := null; fc := null; ac := null; n := 0; why := null; isms := false;
    if uid is null then why := 'No updated schedule for this period';
    elsif not exists (select 1 from schedule_update_rows where update_id = uid) then why := 'No activity rows of the updated schedule';
    elsif d.src = 'act' then
      select count(*), coalesce(bool_or(ms), false) into n, isms from schedule_update_rows where update_id = uid and act_id = d.ref;
      if n = 0 then why := 'Not in the updated schedule';
      elsif isms then select coalesce(bf, bs), coalesce(af, as_d), coalesce(af, as_d, ef, es, bf, bs) into pl, ac, fc from schedule_update_rows where update_id = uid and act_id = d.ref;
      elsif d.ev = 'start' then select bs, as_d, coalesce(as_d, es, bs) into pl, ac, fc from schedule_update_rows where update_id = uid and act_id = d.ref;
      else select bf, af, coalesce(af, ef, bf) into pl, ac, fc from schedule_update_rows where update_id = uid and act_id = d.ref; end if;
    else
      i := strpos(d.ref, '|'); m := case when i = 0 then d.ref else left(d.ref, i - 1) end; l := case when i = 0 then null else substr(d.ref, i + 1) end;
      if d.ev = 'start' then
        select count(*), min(bs), min(as_d), coalesce(min(as_d), min(coalesce(es, bs))) into n, pl, ac, fc
          from schedule_update_rows where update_id = uid and not ms and coalesce(wbs, '') = m and (l is null or coalesce(wbs_leaf, '') = l);
      else
        select count(*), max(bf), case when count(*) > 0 and bool_and(af is not null) then max(af) end, max(coalesce(af, ef, bf)) into n, pl, ac, fc
          from schedule_update_rows where update_id = uid and not ms and coalesce(wbs, '') = m and (l is null or coalesce(wbs_leaf, '') = l);
        if ac is not null then fc := ac; end if;
      end if;
      if n = 0 then why := 'Not in the updated schedule'; pl := null; fc := null; ac := null; end if;
    end if;
    acc := acc || jsonb_build_array(jsonb_build_object('id', d.id, 'name', d.name, 'req', d.req, 'src', d.src, 'ref', d.ref, 'ev', d.ev, 'ms', d.ms, 'act_name', d.act_name,
      'plan', pl, 'fc', fc, 'act', ac, 'delay', case when pl is not null and fc is not null then fc - pl end, 'n', n, 'why', why, 'dd', dd));
  end loop;
  return coalesce((select jsonb_agg(e order by coalesce(e ->> 'plan', '9999'), e ->> 'name') from jsonb_array_elements(acc) e), '[]'::jsonb);
end $$;

-- ------------------------------------------------------------------ 4. progress by phase of a report
create or replace function pt_phase_tbl(pid text, k text, pt text, per text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare u schedule_updates; s jsonb; own boolean; tot numeric; ws numeric := 0; x jsonb; wt numeric; pres boolean; acc jsonb := '[]'::jsonb;
        pl numeric; ac numeric; plan numeric; act numeric; dpr jsonb; nm int; nn int; sw numeric; v_w numeric; dp numeric; p6 numeric; basis text;
begin
  select * into u from schedule_updates where id = pt_km_update(pid, case when k = 'client' then 'client' end, pt_period_end(per, pt));
  if u.id is null then return null; end if;
  s := u.summary; tot := coalesce(pt_num(s ->> 'w_total'), 0);
  own := k = 'client' or u.weightage = 'internal' or coalesce((select sum(coalesce(pt_num(e.v), 0)) from jsonb_each_text(coalesce(u.weights, '{}'::jsonb)) e(kk, v)), 0) <= 0;
  -- the weights of the phases in the schedule
  for x in select * from jsonb_array_elements(coalesce(s -> 'phases', '[]'::jsonb)) loop
    wt := case when own then case when tot > 0 then round(coalesce(pt_num(x ->> 'w'), 0) / tot * 100, 2) else 0 end else coalesce(pt_num(x ->> 'iw'), 0) end;
    if coalesce((x ->> 'present')::boolean, false) and wt > 0 then ws := ws + wt; end if;
  end loop;
  for x in select * from jsonb_array_elements(coalesce(s -> 'phases', '[]'::jsonb)) loop
    pres := coalesce((x ->> 'present')::boolean, false);
    wt := case when own then case when tot > 0 then round(coalesce(pt_num(x ->> 'w'), 0) / tot * 100, 2) else 0 end else coalesce(pt_num(x ->> 'iw'), 0) end;
    pl := case when pres then pt_num(x ->> 'plan_pct') end; ac := case when pres then pt_num(x ->> 'act_pct') end; dpr := null;
    if k <> 'client' and (x ->> 'phase') in ('CON','INS','TC','EN') then
      select count(*) into nm from schedule_update_rows where update_id = u.id and phase = x ->> 'phase' and not ms;
      with z as (
        select r.w, r.pct, a.qty, coalesce(a.prior_qty, 0) pq,
               coalesce((select sum(coalesce(dl.qty, 0)) from dpr_lines dl join dprs dr on dr.id = dl.dpr_id
                          where dr.project_id = pid and dl.activity_id = r.act_id and dr.status in ('Submitted','Reviewed','Approved') and dr.report_date <= u.data_date), 0) q
          from schedule_update_rows r join activities a on a.project_id = pid and a.id = r.act_id
         where r.update_id = u.id and r.phase = x ->> 'phase' and not r.ms and a.cls = 'CON' and a.qty > 0)
      select count(*), coalesce(sum(coalesce(w, 0)), 0) into nn, sw from z;
      if nn > 0 then
        with z as (
          select case when sw > 0 then coalesce(r.w, 0) else 1 end ww, r.pct, a.qty, coalesce(a.prior_qty, 0) pq,
                 coalesce((select sum(coalesce(dl.qty, 0)) from dpr_lines dl join dprs dr on dr.id = dl.dpr_id
                            where dr.project_id = pid and dl.activity_id = r.act_id and dr.status in ('Submitted','Reviewed','Approved') and dr.report_date <= u.data_date), 0) q
            from schedule_update_rows r join activities a on a.project_id = pid and a.id = r.act_id
           where r.update_id = u.id and r.phase = x ->> 'phase' and not r.ms and a.cls = 'CON' and a.qty > 0)
        select sum(z.ww), sum(z.ww * least(1, (z.pq + z.q) / z.qty)), sum(z.ww * coalesce(z.pct, 0)) into v_w, dp, p6 from z;
        dp := round(dp / v_w * 100, 2); p6 := round(p6 / v_w, 2);
        dpr := jsonb_build_object('n', nn, 'm', nm, 'dpr', dp, 'p6', p6, 'diff', round(dp - p6, 2));
      else dpr := jsonb_build_object('n', 0, 'm', nm); end if;
    end if;
    acc := acc || jsonb_build_array(jsonb_build_object('phase', x ->> 'phase', 'present', pres, 'wt', wt, 'plan_pct', pl, 'act_pct', ac,
      'var_pct', case when pres then round(ac - pl, 2) end, 'site', (x ->> 'phase') in ('CON','INS','TC','EN'), 'dpr', dpr,
      'c_plan', case when pres and ws > 0 then round(wt * pl / ws, 2) end, 'c_act', case when pres and ws > 0 then round(wt * ac / ws, 2) end));
  end loop;
  plan := case when k = 'client' then pt_num(s ->> 'client_plan') else coalesce(pt_num(s ->> 'int_plan'), pt_num(s ->> 'client_plan')) end;
  act := case when k = 'client' then pt_num(s ->> 'client_act') else coalesce(pt_num(s ->> 'int_act'), pt_num(s ->> 'client_act')) end;
  basis := case when k = 'client' then 'client weightage (the schedule''s own weighting)' when u.weightage = 'internal' then 'internal weightage (schedule loaded with it)'
                when own then 'client weightage (no internal weightage set)' else 'internal weightage set at the start of the project' end;
  return jsonb_build_object('dd', u.data_date, 'update_id', u.id, 'own', own, 'basis', basis, 'plan', plan, 'act', act,
    'var_pct', case when plan is not null and act is not null then round(act - plan, 2) end, 'phases', acc,
    'missing', case when k = 'client' then '[]'::jsonb else coalesce(s -> 'missing_phases', '[]'::jsonb) end);
end $$;

-- ------------------------------------------------------------------ 5. saving a report with them
-- p: as release_act_bl. figures.key_ms and figures.phase_tbl are taken out before release_act_bl sees them and the server's
-- own are written after a save of an internal (planning) or client report. Without them, this is exactly release_act_bl.
create or replace function release_act_km(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a text := p ->> 'action'; f jsonb := p -> 'figures'; res jsonb; rel report_releases;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if jsonb_typeof(f) = 'object' then p := jsonb_set(p, '{figures}', f - 'key_ms' - 'phase_tbl'); end if;
  res := release_act_bl(p);
  if a is distinct from 'save' then return res; end if;
  select * into rel from report_releases where id = (res ->> 'id')::uuid for update;
  if rel.id is null or rel.kind not in ('planning','client') then return res; end if;
  update report_releases
     set figures = figures || jsonb_build_object('key_ms', pt_key_ms(rel.project_id, rel.kind, rel.period_type, rel.period),
                                                 'phase_tbl', coalesce(pt_phase_tbl(rel.project_id, rel.kind, rel.period_type, rel.period), 'null'::jsonb))
   where id = rel.id returning * into rel;
  return to_jsonb(rel);
end $$;

revoke execute on function pt_km_update(text, text, date), key_milestone_act(jsonb), pt_key_ms(text, text, text, text), pt_phase_tbl(text, text, text, text), release_act_km(jsonb) from public, anon;
grant execute on function key_milestone_act(jsonb), release_act_km(jsonb), pt_phases() to authenticated;
