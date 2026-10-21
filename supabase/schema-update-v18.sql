-- ProTrack schema update v18 (ProTrackAI v3.9): material tracking in released reports, and executive report layouts.
-- 1. When an internal report (kind 'planning') is approved, release_act saves the project's material status with it in the
--    new column report_releases.mat_snapshot, like the open issues (issues_snapshot). Monitored materials only; worked
--    out from the latest updated schedule (else the baseline loaded into Material Tracking) with the same rules as the
--    Material tracking page. A released version keeps it: it cannot be changed afterwards.
-- 2. The layout of the released Executive report: one default for everyone, set by super admins only
--    (xr_layout_default), and one layout per person (xr_layouts) that only that person reads and writes.
-- Needs schema-update-v17.sql (Material Tracking). Additive: one new column, two small tables, new helpers; release_act
-- gains one line. Safe to run twice. Undo: schema-rollback-v18.sql.

do $$ begin
  if to_regclass('public.material_setup') is null then
    raise exception 'Run schema-update-v17.sql (Material Tracking) first, then this update'; end if;
end $$;

-- ------------------------------------------------------------------ 1. the material status saved with each released internal report
alter table report_releases add column if not exists mat_snapshot jsonb;

-- The material status of one project, as the app's mtSnap() works it out (index.html, v3.9):
--   null when Material Tracking is not set up for the project, else {dd, rows:[{m, st, del, dd, proc, sup, po, late, mfg, fat, ship}]}
--   dd    the data date of the latest updated schedule, else the data date of the baseline loaded, else yesterday
--         (null when no material is monitored)
--   rows  one per monitored material, by name. Its activities are the baseline's material activities, with % complete and
--         actual / forecast dates from the latest updated schedule when the activity is in it, plus the activities of that
--         schedule that carry a Material Name, are not in the baseline and sit in the chosen WBS branches.
--   An activity is done at 100 % or with an actual finish; started when done, above 0 % or with an actual start; delayed
--   when not done and its finish (actual, else forecast) or the data date is past the baseline finish.
--   st    Completed when every activity is done, else the status of the first activity not done
--         (in milestone order PR..CIV, unmapped last, then by baseline start)
--   del   Delivered / Delivery Started / Not Delivered from the activities mapped to DEL, or No delivery activity
--   dd    the latest finish (actual, else forecast, else baseline) of the DEL activities
--   proc  the milestone of that first activity not done, else its Unified Activity Name, else Not mapped; Completed when all done
--   late  any activity delayed;  mfg  MFG started and not finished;  fat  FAT not finished, MFG finished or absent;
--   ship  Release for Shipment not finished, FAT finished or absent
create or replace function pt_mat_snapshot(pid text) returns jsonb
language sql stable security definer set search_path = public as $$
  with s as (select * from material_setup where project_id = pid),
  u as (select id, data_date from schedule_updates where project_id = pid order by data_date desc, uploaded_at desc limit 1),
  d as (select coalesce((select data_date from u), (select data_date from s), current_date - 1) as dd),
  ur as (select x.* from schedule_update_rows x where x.update_id = (select id from u)),
  a0 as (   -- the baseline's material activities, with the latest updated schedule's progress when the activity is in it
    select b.act_id, true as in_base, b.material, coalesce(nullif(b.uact, ''), nullif(x.uact, ''), '') as uact, b.bs, b.bf,
           case when x.act_id is not null then coalesce(x.pct, 0) else coalesce(b.pct, 0) end as pct,
           case when x.act_id is not null then x.as_d else b.as_d end as as_d,
           case when x.act_id is not null then x.af else b.af end as af,
           case when x.act_id is not null then x.ef else b.ef end as ef
      from material_acts b left join ur x on x.act_id = b.act_id
     where b.project_id = pid
    union all  -- material activities that are only in the updated schedule, in the chosen WBS branches
    select x.act_id, false, x.mat, coalesce(nullif(x.uact, ''), ''), x.bs, x.bf, coalesce(x.pct, 0), x.as_d, x.af, x.ef
      from ur x
     where nullif(x.mat, '') is not null
       and not exists (select 1 from material_acts b where b.project_id = pid and b.act_id = x.act_id)
       and (jsonb_array_length((select wbs_filter from s)) = 0
            or coalesce(x.wbs, '') in (select jsonb_array_elements_text((select wbs_filter from s))))),
  a1 as (
    select a0.*, coalesce(s.stage_map ->> a0.uact, '') as stage, (a0.pct >= 100 or a0.af is not null) as done,
           coalesce(a0.af, a0.ef) as cf, coalesce(a0.af, a0.ef, a0.bf) as cfd
      from a0 cross join s),
  a2 as (
    select a1.*, (done or pct > 0 or as_d is not null) as started,
           coalesce(not done and bf is not null and (coalesce(cf > bf, false) or (select dd from d) > bf), false) as late,
           coalesce(array_position(pt_mat_stages(), nullif(stage, '')), 99) as ord
      from a1),
  a3 as (
    select a2.*, case when done then 'Completed' when late then 'Delayed' when started then 'In Progress' else 'Not Started' end as status,
           row_number() over (partition by material order by ord, bs nulls first, not in_base, act_id) as rn
      from a2),
  m as (
    select material, bool_and(done) as all_done, bool_or(late) as delayed,
           coalesce(min(rn) filter (where not done), max(rn)) as cur_rn,
           count(*) filter (where stage = 'DEL') as del_n, bool_and(done) filter (where stage = 'DEL') as del_done,
           bool_or(started) filter (where stage = 'DEL') as del_started, max(cfd) filter (where stage = 'DEL') as del_date,
           count(*) filter (where stage = 'MFG') as mfg_n, bool_and(done) filter (where stage = 'MFG') as mfg_done,
           bool_or(started) filter (where stage = 'MFG') as mfg_started,
           count(*) filter (where stage = 'FAT') as fat_n, bool_and(done) filter (where stage = 'FAT') as fat_done,
           count(*) filter (where stage = 'RFS') as rfs_n, bool_and(done) filter (where stage = 'RFS') as rfs_done
      from a3 group by material),
  r as (    -- monitored materials only; a material without a monitoring row counts as monitored, as in the app
    select m.*, c.status as cur_status, c.stage as cur_stage, c.uact as cur_uact, i.supplier, i.po_number
      from m join a3 c on c.material = m.material and c.rn = m.cur_rn
      left join material_items i on i.project_id = pid and i.material = m.material
     where coalesce(i.selected, true))
  select case when not exists (select 1 from s) then null else jsonb_build_object(
    'dd', case when exists (select 1 from r) then (select dd from d) end,
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'm', material,
        'st', case when all_done then 'Completed' else cur_status end,
        'del', case when del_n = 0 then 'No delivery activity' when del_done then 'Delivered' when del_started then 'Delivery Started' else 'Not Delivered' end,
        'dd', case when del_n > 0 then del_date end,
        'proc', case when all_done then 'Completed' else coalesce(case cur_stage when 'PR' then 'PR Creation' when 'PO' then 'PO Creation'
                  when 'BD' then 'Base Design' when 'GAFM' then 'GAFM Approval' when 'MFG' then 'Manufacturing' when 'FAT' then 'FAT'
                  when 'RFS' then 'Release for Shipment' when 'DEL' then 'Delivery at Site' when 'CIV' then 'Civil Readiness' end,
                  nullif(cur_uact, ''), 'Not mapped') end,
        'sup', nullif(supplier, ''), 'po', nullif(po_number, ''), 'late', delayed,
        'mfg', mfg_n > 0 and mfg_started and not mfg_done,
        'fat', fat_n > 0 and not fat_done and (mfg_n = 0 or mfg_done),
        'ship', rfs_n > 0 and not rfs_done and (fat_n = 0 or fat_done)) order by material) from r), '[]'::jsonb)) end $$;

-- pt_release_frozen: from schema-update-v15.sql; the material status of a released version cannot be changed either
create or replace function pt_release_frozen() returns trigger language plpgsql as $$
begin
  if old.status in ('Released','Superseded') and (new.figures is distinct from old.figures or new.overrides is distinct from old.overrides
     or new.narrative is distinct from old.narrative or new.period is distinct from old.period or new.project_id is distinct from old.project_id
     or new.rev is distinct from old.rev or new.issues_snapshot is distinct from old.issues_snapshot or new.data_date is distinct from old.data_date or new.approved_by is distinct from old.approved_by
     or new.reviewed_by is distinct from old.reviewed_by or new.reviewed_at is distinct from old.reviewed_at or new.review_note is distinct from old.review_note
     or new.sched_validated_by is distinct from old.sched_validated_by or new.sched_validated_at is distinct from old.sched_validated_at
     or new.sched_validation_note is distinct from old.sched_validation_note or new.mat_snapshot is distinct from old.mat_snapshot
     or (old.status = 'Superseded' and new.status <> 'Superseded') or (old.status = 'Released' and new.status not in ('Released','Superseded'))) then
    raise exception 'A released version cannot be changed; issue a new revision' using errcode = '42501';
  end if;
  return new;
end $$;

-- release_act: from schema-update-v16.sql; approving an internal report also saves its material status (mat_snapshot)
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
    elsif not pt_cost_approver(me) then raise exception 'Only the Head of Planning and Cost Control or a super admin can approve a release' using errcode = '42501'; end if;
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
           issues_snapshot = case when rel.kind = 'planning' then pt_issue_snapshot(rel.project_id) else issues_snapshot end,
           mat_snapshot = case when rel.kind = 'planning' then pt_mat_snapshot(rel.project_id) else mat_snapshot end
     where id = rel.id returning * into rel;
    perform pt_rel_log(rel.id, 'Approved and released', note, jsonb_build_object('rev', rel.rev));
  elsif a = 'return' then
    if rel.kind in ('planning','client') then
      if not (pt_rel_approver(me, rel.project_id) or (rel.kind = 'planning' and pmr and r = 'pm' and user_sees(me, rel.project_id) and rel.reviewed_by is null)) then
        raise exception 'Only the Head of Planning and Cost Control, the regional planning section manager or a super admin can return this report' using errcode = '42501'; end if;
    elsif not pt_cost_approver(me) then raise exception 'Only the Head of Planning and Cost Control or a super admin can return a release' using errcode = '42501'; end if;
    if rel.status <> 'Submitted' then raise exception 'Only a submitted version can be returned'; end if;
    if note is null then raise exception 'Add a comment saying what to fix'; end if;
    update report_releases set status = 'Draft', submitted_by = null, submitted_at = null, reviewed_by = null, reviewed_at = null, review_note = null, updated_at = now() where id = rel.id returning * into rel;
    perform pt_rel_log(rel.id, 'Returned', note, null);
  end if;
  return to_jsonb(rel);
end $$;

revoke execute on function release_act(jsonb) from public, anon;
grant execute on function release_act(jsonb) to authenticated;

-- ------------------------------------------------------------------ 2. executive report layouts
-- A layout is {secs:[{k, on}], tiles:[{k, on}]}: the sections and headline tiles in their order, shown or hidden.
-- The app fills in sections added later; cost sections still show only to people who see cost figures, whatever the layout.
create or replace function pt_xr_layout_ok(l jsonb) returns boolean language plpgsql immutable as $$
declare e jsonb;
begin
  if l is null then return true; end if;
  if jsonb_typeof(l) <> 'object' or length(l::text) > 4000 then return false; end if;
  if coalesce(jsonb_typeof(l -> 'secs'), '') <> 'array' or coalesce(jsonb_typeof(l -> 'tiles'), '') <> 'array' then return false; end if;
  if jsonb_array_length(l -> 'secs') > 40 or jsonb_array_length(l -> 'tiles') > 40 then return false; end if;
  for e in select * from jsonb_array_elements((l -> 'secs') || (l -> 'tiles')) loop
    if jsonb_typeof(e) <> 'object' or coalesce(jsonb_typeof(e -> 'k'), '') <> 'string' or (e ->> 'k') !~ '^[a-z0-9_]{1,20}$'
       or coalesce(jsonb_typeof(e -> 'on'), '') <> 'boolean' then return false; end if;
  end loop;
  return true;
end $$;

-- the default for everyone: one row; layout null = the standard layout
create table if not exists xr_layout_default (
  id boolean primary key default true check (id),
  layout jsonb,
  set_by uuid references profiles(id), set_by_name text, set_at timestamptz not null default now());
-- each person's own layout; no row = the default
create table if not exists xr_layouts (
  user_id uuid primary key default auth.uid() references profiles(id) on delete cascade,
  layout jsonb not null,
  updated_at timestamptz not null default now());

-- who changed the default and when is written by the server, and each change goes to the change log
create or replace function pt_xr_default_stamp() returns trigger
language plpgsql security definer set search_path = public as $
begin
  if not pt_xr_layout_ok(new.layout) then raise exception 'This report layout is not valid' using errcode = '22023'; end if;
  new.id := true; new.set_by := auth.uid(); new.set_by_name := name_of(auth.uid()); new.set_at := now();
  return new;
end $;
drop trigger if exists trg_xrd_stamp on xr_layout_default;
create trigger trg_xrd_stamp before insert or update on xr_layout_default for each row execute function pt_xr_default_stamp();
-- after the write, so an upsert that ends as an update is logged once
create or replace function pt_xr_default_log() returns trigger
language plpgsql security definer set search_path = public as $
begin
  if tg_op = 'INSERT' or new.layout is distinct from old.layout then
    insert into change_log (text, by_user)
    values (case when new.layout is null then 'Set the default layout of the executive report back to the standard layout'
                 else 'Changed the default layout of the executive report' end, new.set_by);
  end if;
  return null;
end $;
drop trigger if exists trg_xrd_log on xr_layout_default;
create trigger trg_xrd_log after insert or update on xr_layout_default for each row execute function pt_xr_default_log();

create or replace function pt_xr_mine_stamp() returns trigger language plpgsql as $$
begin
  if new.layout is null or not pt_xr_layout_ok(new.layout) then raise exception 'This report layout is not valid' using errcode = '22023'; end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists trg_xrl_stamp on xr_layouts;
create trigger trg_xrl_stamp before insert or update on xr_layouts for each row execute function pt_xr_mine_stamp();

alter table xr_layout_default enable row level security;
alter table xr_layouts enable row level security;
-- the default: everyone signed in reads it; only super admins write it (reset = layout null, so no delete)
drop policy if exists xrd_read on xr_layout_default;
create policy xrd_read on xr_layout_default for select using (auth.uid() is not null);
drop policy if exists xrd_insert on xr_layout_default;
create policy xrd_insert on xr_layout_default for insert with check (my_role() = 'sa');
drop policy if exists xrd_update on xr_layout_default;
create policy xrd_update on xr_layout_default for update using (my_role() = 'sa') with check (my_role() = 'sa');
-- a person's own layout: only that person reads and writes it
drop policy if exists xrl_read on xr_layouts;
create policy xrl_read on xr_layouts for select using (user_id = auth.uid());
drop policy if exists xrl_insert on xr_layouts;
create policy xrl_insert on xr_layouts for insert with check (user_id = auth.uid() and my_role() is not null);
drop policy if exists xrl_update on xr_layouts;
create policy xrl_update on xr_layouts for update using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists xrl_delete on xr_layouts;
create policy xrl_delete on xr_layouts for delete using (user_id = auth.uid());

-- ------------------------------------------------------------------ grants
revoke execute on function pt_mat_snapshot(text) from public, anon, authenticated;
revoke all on xr_layout_default, xr_layouts from anon;
grant select, insert, update on xr_layout_default to authenticated;
grant select, insert, update, delete on xr_layouts to authenticated;
