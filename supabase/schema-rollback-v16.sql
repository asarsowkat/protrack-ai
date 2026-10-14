-- ProTrack schema rollback v16: back to the v3.6 rules (schema-update-v15.sql).
-- Every permission check goes back to the fixed rules of each role. The tables app_roles, role_rights, user_rights,
-- screen_rights and rights_audit, and the profiles columns custom_role and all_projects, are kept with everything in
-- them, but nothing reads them any more. Run schema-update-v16.sql again to use them again. Safe to run twice.
-- user_sees: as in schema-update-v4.sql
create or replace function user_sees(u uuid, p text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when (select role::text from profiles where id = u and active) in ('sa','exec') then true
    when exists (select 1 from project_access a where a.user_id = u and a.project_id = p) then true
    when exists (select 1 from region_access r join projects pr on pr.region = r.region_id
                 where r.user_id = u and pr.id = p) then true
    else false end $$;
-- can_see: as in schema.sql
create or replace function can_see(p text) returns boolean
language sql stable security definer as $$
  select case
    when (select role from profiles where id = auth.uid() and active) in ('sa','exec') then true
    when exists (select 1 from project_access a where a.user_id = auth.uid() and a.project_id = p) then true
    when exists (select 1 from region_access r join projects pr on pr.region = r.region_id
                 where r.user_id = auth.uid() and pr.id = p) then true
    else false end $$;
-- can_plan: as in schema.sql
create or replace function can_plan(p text) returns boolean
language sql stable security definer as $$
  select can_see(p) and (select role from profiles where id = auth.uid()) in ('sa','plan') $$;
-- can_cost: as in schema-update-v3.sql
create or replace function can_cost(p text) returns boolean
language sql stable security definer as $$
  select can_see(p) and my_role_text() in ('sa','costing','pm') $$;
-- can_edit_dpr: as in schema-update-v3.sql
create or replace function can_edit_dpr(p text) returns boolean
language sql stable security definer as $$
  select can_see(p) and my_role_text() in ('sa','pm','sm','eng','foreman') $$;
-- can_approve: as in schema-update-v3.sql
create or replace function can_approve(p text) returns boolean
language sql stable security definer as $$
  select can_see(p) and my_role_text() in ('sa','pm','sm') $$;
-- pt_money_ok: as in schema-update-v8.sql
create or replace function pt_money_ok() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(my_role_text() not in ('foreman','eng','sm'), false) $$;
-- pt_issue_editor: as in schema-update-v10.sql
create or replace function pt_issue_editor(u uuid, pid text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(user_sees(u, pid) and (role_of(u) in ('sa','plan','costing') or pt_is_head(u)), false) $$;
-- pt_doc_can: as in schema-update-v13.sql
create or replace function pt_doc_can(u uuid, pid text, k text, w boolean) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare rw text := pt_doc_row(pid, k); r text := role_of(u);
begin
  if u is null or r is null or rw is null or pid is null or not user_sees(u, pid) then return false; end if;
  if not w then
    return case when rw = 'planning' then r <> 'foreman' else r not in ('foreman','eng','sm') end;
  end if;
  return r = 'sa' or pt_is_head(u) or (rw = 'planning' and r = 'plan') or (rw in ('contract','cost') and r = 'costing');
end $$;
-- pt_can_register: as in schema-update-v7.sql
create or replace function pt_can_register(u uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) = 'sa' or pt_is_head(u) or pt_is_coord(u), false) $$;
-- pt_lc_approver: as in schema-update-v6.sql
create or replace function pt_lc_approver(u uuid, p text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) = 'sa' or (role_of(u) = 'pm' and user_sees(u, p)), false) $$;
-- pt_release_preparer: as in schema-update-v15.sql
create or replace function pt_release_preparer(u uuid, k text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) = 'sa' or (k in ('planning','client') and role_of(u) = 'plan') or (k = 'cost' and (role_of(u) = 'costing' or pt_is_coord(u))), false) $$;
-- pt_release_staff: as in schema-update-v15.sql
create or replace function pt_release_staff(u uuid, k text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) = 'sa' or pt_is_head(u) or (k in ('planning','client') and role_of(u) = 'plan')
                  or (k = 'cost' and (role_of(u) = 'costing' or pt_is_coord(u))), false) $$;
-- pt_rel_approver: as in schema-update-v14.sql
create or replace function pt_rel_approver(u uuid, pid text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) = 'sa' or pt_is_head(u)
    or (user_sees(u, pid) and exists (select 1 from release_approvers a join projects p on p.region = a.region_id where a.user_id = u and p.id = pid)), false) $$;
-- pt_sched_keeper: as in schema-update-v15.sql
create or replace function pt_sched_keeper(u uuid, pid text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) = 'sa' or (role_of(u) = 'plan' and user_sees(u, pid)), false) $$;
-- admin_save_person: as in schema-update-v4.sql
create or replace function admin_save_person(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; me uuid := auth.uid();
begin
  if role_of(me) is distinct from 'sa' then raise exception 'Only a super admin can manage people' using errcode = '42501'; end if;
  select id into uid from auth.users where lower(email) = lower(trim(p ->> 'email'));
  if uid is null then raise exception 'No sign-in account exists for % yet. Create it first in Supabase: Authentication, Users, Add user.', p ->> 'email'; end if;
  if coalesce(trim(p ->> 'name'), '') = '' then raise exception 'Enter the person''s full name'; end if;
  if (p ->> 'role') not in ('sa','exec','rm','pf','plan','costing','pm','sm','eng','foreman','ro') then raise exception 'Unknown role %', p ->> 'role'; end if;
  if uid = me and ((p ->> 'role') <> 'sa' or not coalesce((p ->> 'active')::boolean, true)) then
    raise exception 'You cannot remove your own super admin access'; end if;
  insert into profiles (id, name, title, role, active)
  values (uid, trim(p ->> 'name'), nullif(p ->> 'title', ''), (p ->> 'role')::user_role, coalesce((p ->> 'active')::boolean, true))
  on conflict (id) do update set name = excluded.name, title = excluded.title, role = excluded.role, active = excluded.active;
  delete from project_access where user_id = uid;
  insert into project_access (user_id, project_id)
  select distinct uid, x from jsonb_array_elements_text(coalesce(p -> 'projects', '[]'::jsonb)) x where exists (select 1 from projects where id = x);
  delete from region_access where user_id = uid;
  insert into region_access (user_id, region_id)
  select distinct uid, x from jsonb_array_elements_text(coalesce(p -> 'regions', '[]'::jsonb)) x where exists (select 1 from regions where id = x);
  insert into change_log (text, by_user) values ('Saved ' || trim(p ->> 'name') || ' as ' || (p ->> 'role'), me);
  return jsonb_build_object('id', uid);
end $$;
-- dpr_save: as in schema-update-v4.sql
create or replace function dpr_save(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); r text := role_of(auth.uid());
  pid text := p ->> 'project_id'; did text := nullif(p ->> 'id', '');
  d dprs; fid uuid; fname text; rev uuid; act text; ln jsonb; i int := 0; bad text; was_returned boolean;
begin
  if me is null or r is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if r not in ('foreman','eng','pm','sa') then raise exception 'Your role cannot write daily reports' using errcode = '42501'; end if;
  if pid is null or not user_sees(me, pid) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
  if (p ->> 'report_date') is null then raise exception 'Report date is required'; end if;
  if jsonb_typeof(p -> 'lines') <> 'array' or jsonb_array_length(p -> 'lines') = 0 then raise exception 'A report needs at least one activity line'; end if;
  -- one day of grace for time zones (Saudi Arabia is three hours ahead of the server clock)
  if (p ->> 'report_date')::date > current_date + 1 then raise exception 'The report date cannot be in the future'; end if;
  if (select count(*) <> count(distinct l ->> 'activity_id') from jsonb_array_elements(p -> 'lines') l) then
    raise exception 'The same activity is on the report twice. Combine them into one.'; end if;

  -- every line must be an activity of this project, with sane numbers
  select string_agg(coalesce(l ->> 'activity_id', '?'), ', ') into bad
    from jsonb_array_elements(p -> 'lines') l
   where not exists (select 1 from activities a where a.project_id = pid and a.id = l ->> 'activity_id')
      or coalesce((l ->> 'qty')::numeric, 0) < 0;
  if bad is not null then raise exception 'Lines refused (unknown activity or negative quantity): %', bad; end if;
  select string_agg(coalesce(x ->> 'cat', '?'), ', ') into bad
    from jsonb_array_elements(p -> 'lines') l, jsonb_array_elements(coalesce(l -> 'labour', '[]'::jsonb)) x
   where coalesce((x ->> 'count')::numeric, 0) < 0 or coalesce((x ->> 'reg')::numeric, 0) + coalesce((x ->> 'ot')::numeric, 0) > 24
      or coalesce((x ->> 'reg')::numeric, 0) < 0 or coalesce((x ->> 'ot')::numeric, 0) < 0;
  if bad is not null then raise exception 'Labour refused (negative count or more than 24 hours a day): %', bad; end if;

  fid := case when r = 'foreman' then me else nullif(p ->> 'foreman_id', '')::uuid end;
  -- a foreman always reports under their own name; others may name the foreman
  fname := case when r = 'foreman' then name_of(me) else coalesce(nullif(p ->> 'foreman', ''), name_of(fid)) end;
  if r <> 'foreman' and fid is not null and (role_of(fid) is distinct from 'foreman' or not user_sees(fid, pid)) then
    raise exception 'The chosen foreman is not on this project'; end if;
  perform pt_begin();

  if did is not null then select * into d from dprs where id = did for update; end if;
  select x.id into bad from dprs x
   where x.project_id = pid and x.report_date = (p ->> 'report_date')::date and x.id is distinct from did
     and x.foreman = coalesce(fname, d.foreman) limit 1;
  if bad is not null then raise exception 'This foreman already has a report for that date (%). Open and edit that one instead.', bad; end if;
  if d.id is null then
    did := coalesce(did, 'DPR-' || lpad(nextval('dpr_seq')::text, 5, '0'));
    insert into dprs (id, project_id, report_date, foreman, foreman_id, status, remarks, created_by, timing, photo_names)
    values (did, pid, (p ->> 'report_date')::date, fname, fid, 'Draft',
            p ->> 'remarks', me, pt_timing('{}'::jsonb, 'create', (p ->> 'secs')::int), coalesce(p -> 'photos', '[]'::jsonb))
    returning * into d;
    perform pt_audit(did, 'Draft created', null);
  else
    if d.project_id <> pid then raise exception 'A report cannot move to another project'; end if;
    rev := dpr_reviewer(d.project_id, d.foreman_id);
    if d.status = 'Draft' then
      if not coalesce(r in ('pm','sa') or r = 'eng'
              or (r = 'foreman' and (d.foreman_id = me or (d.foreman_id is null and d.foreman = name_of(me)))), false) then
        raise exception 'This draft belongs to another foreman' using errcode = '42501'; end if;
    elsif d.status in ('Submitted','Reviewed') then
      if not coalesce(r in ('pm','sa') or (r = 'eng' and rev = me), false) then
        raise exception 'Only the assigned site engineer or the project manager can edit a submitted report' using errcode = '42501'; end if;
    else
      raise exception 'A % report cannot be edited', lower(d.status::text) using errcode = '42501';
    end if;
    update dprs set report_date = (p ->> 'report_date')::date, remarks = p ->> 'remarks', updated_at = now(),
           foreman = case when r = 'foreman' then foreman else coalesce(fname, foreman) end,
           photo_names = coalesce(p -> 'photos', photo_names),
           foreman_id = case when r = 'foreman' then foreman_id else coalesce(fid, foreman_id) end,
           timing = pt_timing(timing, 'create', (p ->> 'secs')::int)
     where id = did returning * into d;
    if d.status <> 'Draft' then perform pt_audit(did, 'Edited', p ->> 'note'); end if;
  end if;

  delete from dpr_lines where dpr_id = did;
  for ln in select * from jsonb_array_elements(p -> 'lines') loop
    i := i + 1;
    insert into dpr_lines (dpr_id, activity_id, qty, labour, subs, equip, line_no)
    values (did, ln ->> 'activity_id', coalesce((ln ->> 'qty')::numeric, 0), coalesce(ln -> 'labour', '[]'::jsonb),
            coalesce(ln -> 'subs', '[]'::jsonb), coalesce(ln -> 'equip', '[]'::jsonb), i);
  end loop;

  if coalesce((p ->> 'submit')::boolean, false) and d.status = 'Draft' then
    was_returned := d.returned;
    update dprs set status = 'Submitted', returned = false, updated_at = now() where id = did returning * into d;
    perform pt_audit(did, case when was_returned then 'Resubmitted' else 'Submitted' end, null);
  end if;
  return jsonb_build_object('id', d.id, 'status', d.status, 'timing', d.timing);
end $$;
-- dpr_act: as in schema-update-v11.sql
create or replace function dpr_act(p_id text, p_action text, p_note text default null, p_secs int default 0, p_just jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); r text := role_of(auth.uid()); d dprs; rev uuid; reviewed_by uuid; apr uuid;
  boss boolean; can boolean := false; kind text; o record; jt text; miss text;
begin
  if me is null or r is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  select * into d from dprs where id = p_id for update;
  if d.id is null or not user_sees(me, d.project_id) then raise exception 'Report not found' using errcode = '42501'; end if;
  if p_action in ('return','reject') and coalesce(trim(p_note), '') = '' then
    raise exception 'A comment is required to % a report', p_action; end if;

  boss := r in ('pm','sa');
  rev := dpr_reviewer(d.project_id, d.foreman_id);
  select a.by_user into reviewed_by from dpr_audit a where a.dpr_id = d.id and a.action = 'Reviewed' order by a.seq desc limit 1;
  -- approver: the site manager assigned to the engineer who reviewed it, else to the assigned engineer
  apr := dpr_approver(d.project_id, coalesce(case when role_of(reviewed_by) = 'eng' then reviewed_by end, rev));

  if d.status = 'Submitted' then
    kind := 'review';
    can := case p_action
      when 'review' then boss or (r = 'eng' and rev = me) or (r = 'pm' and rev is null)
      when 'return' then boss or (r = 'eng' and rev = me)
      when 'reject' then boss
      else false end;
  elsif d.status = 'Reviewed' then
    kind := 'approve';
    can := case p_action
      when 'approve' then boss or (r = 'sm' and apr = me)
      when 'return'  then boss or (r = 'sm' and apr = me)
      when 'reject'  then boss or (r = 'sm' and apr = me)
      else false end;
  else
    raise exception 'This report is % and cannot be acted on', lower(d.status::text) using errcode = '42501';
  end if;
  -- an unassigned step compares with null; treat "unknown" as "no"
  if not coalesce(can, false) then raise exception 'You are not the reviewer or approver assigned to this report' using errcode = '42501'; end if;

  perform pt_begin();
  -- v11: a quantity beyond the activity's scope is accepted, but the reviewer must justify it, and the approver
  -- cannot approve a quantity that was not justified (for example one raised by an edit after review)
  if p_action = 'review' then
    if p_just is not null and jsonb_typeof(p_just) <> 'object' then raise exception 'Justifications must be given per activity'; end if;
    select string_agg(x.activity_id, ', ' order by x.activity_id) into miss from pt_dpr_over(d.id) x
     where length(btrim(coalesce(p_just ->> x.activity_id, ''))) < 10;
    if miss is not null then
      raise exception 'Justify the quantity variation (at least a few words) for the activities beyond their scope quantity: %', miss; end if;
    for o in select * from pt_dpr_over(d.id) loop
      jt := left(btrim(p_just ->> o.activity_id), 1000);
      insert into dpr_qty_just (dpr_id, activity_id, qty, cum_qty, scope_qty, note, by_user, by_name)
      values (d.id, o.activity_id, o.qty, o.cum_qty, o.scope_qty, jt, me, name_of(me));
      perform pt_audit(d.id, 'Quantity variation justified', o.activity_id || ': ' || jt);
    end loop;
  elsif p_action = 'approve' then
    select string_agg(x.activity_id, ', ' order by x.activity_id) into miss from pt_dpr_over(d.id) x
     where not exists (select 1 from dpr_qty_just j where j.dpr_id = d.id and j.activity_id = x.activity_id and j.qty = x.qty);
    if miss is not null then
      raise exception 'The quantity beyond the scope of % has not been justified by the reviewer; return the report so the site engineer can justify it', miss; end if;
  end if;
  update dprs set
    status = case p_action when 'review' then 'Reviewed' when 'approve' then 'Approved'
                           when 'return' then 'Draft' else 'Rejected' end::dpr_status,
    returned = (p_action = 'return'), updated_at = now(),
    timing = pt_timing(timing, kind, p_secs)
   where id = d.id returning * into d;
  perform pt_audit(d.id, case p_action when 'review' then 'Reviewed' when 'approve' then 'Approved'
                                       when 'return' then 'Returned' else 'Rejected' end, p_note);
  return jsonb_build_object('id', d.id, 'status', d.status, 'timing', d.timing);
end $$;
-- release_act: as in schema-update-v15.sql
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
-- issue_act: as in schema-update-v10.sql
create or replace function issue_act(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r text := role_of(auth.uid()); a text := p ->> 'action'; f jsonb := coalesce(p -> 'fields', '{}'::jsonb);
        note text := nullif(btrim(coalesce(p ->> 'note', '')), ''); i issues; pid text; ch text[];
begin
  if me is null or r is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if a is null or a not in ('save','close','reopen','review') then raise exception 'Unknown action %', a; end if;
  if nullif(p ->> 'id', '') is not null then
    select * into i from issues where id = (p ->> 'id')::uuid for update;
    if i.id is null then raise exception 'Unknown issue'; end if;
    pid := i.project_id;
  else pid := p ->> 'project_id'; end if;
  if pid is null or not user_sees(me, pid) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
  if a = 'review' then
    if not (r = 'sa' or pt_is_head(me)) then raise exception 'Only the Head of Planning and Cost Control or a super admin marks issues reviewed' using errcode = '42501'; end if;
    if i.id is null then raise exception 'Unknown issue'; end if;
    update issues set reviewed_by = me, reviewed_at = now(), review_note = left(note, 1000) where id = i.id returning * into i;
    perform pt_issue_log(i.id, 'Reviewed', note, null);
    return to_jsonb(i);
  end if;
  if not pt_issue_editor(me, pid) then raise exception 'Only the planning and costing engineers of this project, the Head of Planning and Cost Control or a super admin can change its issues' using errcode = '42501'; end if;
  if a = 'save' then
    if i.id is null then
      if nullif(btrim(coalesce(f ->> 'description', '')), '') is null then raise exception 'Describe the issue'; end if;
      i.id := pt_issue_new(pid, f ->> 'description');
      ch := pt_issue_apply(i.id, f);
      perform pt_issue_log(i.id, 'Created', null, jsonb_build_object('fields', to_jsonb(ch)));
    else
      if i.status = 'Closed' then raise exception 'This issue is closed; reopen it first'; end if;
      ch := pt_issue_apply(i.id, f);
      if array_length(ch, 1) > 0 then perform pt_issue_log(i.id, 'Updated', note, jsonb_build_object('changes', to_jsonb(ch))); end if;
    end if;
  elsif a = 'close' then
    if i.id is null then raise exception 'Unknown issue'; end if;
    if i.status = 'Closed' then raise exception 'This issue is already closed'; end if;
    if pt_bad_date(p ->> 'closed_on') then raise exception 'The closure date is not a valid date'; end if;
    update issues set status = 'Closed', closed_on = coalesce(pt_date(p ->> 'closed_on'), current_date), updated_by = me, updated_at = now() where id = i.id;
    perform pt_issue_log(i.id, 'Closed', note, null);
  else
    if i.id is null then raise exception 'Unknown issue'; end if;
    if i.status <> 'Closed' then raise exception 'Only a closed issue can be reopened'; end if;
    if note is null then raise exception 'Add a comment saying why the issue is reopened'; end if;
    update issues set status = 'Open', closed_on = null, updated_by = me, updated_at = now() where id = i.id;
    perform pt_issue_log(i.id, 'Reopened', note, null);
  end if;
  select * into i from issues where id = i.id;
  return to_jsonb(i);
end $$;
-- issue_import: as in schema-update-v10.sql
create or replace function issue_import(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r text := role_of(auth.uid()); rows jsonb := coalesce(p -> 'rows', '[]'::jsonb); x jsonb; err text; n int := 0;
        acc jsonb := '[]'::jsonb; rej jsonb := '[]'::jsonb; iid uuid; ch text[]; st text; created int := 0; updated int := 0; same int := 0; bid uuid; projs text[];
begin
  if me is null or r is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if not (r in ('sa','plan','costing') or pt_is_head(me)) then raise exception 'Only planning and costing engineers, the Head of Planning and Cost Control or a super admin upload the issue log' using errcode = '42501'; end if;
  if jsonb_typeof(rows) <> 'array' or jsonb_array_length(rows) = 0 then raise exception 'The file has no rows'; end if;
  if jsonb_array_length(rows) > 5000 then raise exception 'At most 5000 rows per upload'; end if;
  if exists (select 1 from import_batches where kind = 'issues' and by_user = me and status = 'committed' and file_hash = p ->> 'hash'
             and at_time = (select max(at_time) from import_batches where kind = 'issues' and by_user = me and status = 'committed')) then
    return jsonb_build_object('duplicate', true); end if;
  for x in select * from jsonb_array_elements(rows) loop
    n := n + 1; err := null;
    if nullif(btrim(coalesce(x ->> 'project_id', '')), '') is null and nullif(btrim(coalesce(x ->> 'description', '')), '') is null then err := 'no project or description (a continuation row?)';
    elsif nullif(x ->> 'project_id', '') is null or not exists (select 1 from projects where id = x ->> 'project_id') then err := 'unknown project';
    elsif not pt_issue_editor(me, x ->> 'project_id') then err := 'not one of your projects';
    elsif nullif(btrim(coalesce(x ->> 'description', '')), '') is null then err := 'description missing';
    elsif nullif(btrim(coalesce(x ->> 'impact', '')), '') is not null and pt_impact(x ->> 'impact') is null then err := 'impact must be Extremely High, High, Medium or Low';
    elsif coalesce(lower(btrim(x ->> 'status')), 'open') not in ('open','closed','') then err := 'status must be Open or Closed';
    elsif (nullif(btrim(coalesce(x ->> 'priority_client', '')), '') is not null and pt_prio(x ->> 'priority_client') is null)
       or (nullif(btrim(coalesce(x ->> 'priority_internal', '')), '') is not null and pt_prio(x ->> 'priority_internal') is null) then err := 'priority must be A, B or C';
    elsif pt_bad_date(x ->> 'data_date') or pt_bad_date(x ->> 'started_on') or pt_bad_date(x ->> 'planned_target') or pt_bad_date(x ->> 'forecast_target') or pt_bad_date(x ->> 'closed_on') then err := 'a date is not valid';
    end if;
    if err is null then acc := acc || jsonb_build_array(x); else rej := rej || jsonb_build_array(jsonb_build_object('row', case when x ->> 'row' ~ '^[0-9]{1,7}$' then (x ->> 'row')::int else n end, 'project', left(x ->> 'project_id', 40), 'error', err)); end if;
  end loop;
  if jsonb_array_length(acc) = 0 then raise exception 'No valid rows, so nothing was saved. First problem: row % %', rej -> 0 ->> 'row', rej -> 0 ->> 'error'; end if;
  if jsonb_array_length(rej) > 0 and not coalesce((p ->> 'ack')::boolean, false) then
    raise exception '% row(s) refused; acknowledge them to save the rest. First: row % %', jsonb_array_length(rej), rej -> 0 ->> 'row', rej -> 0 ->> 'error'; end if;
  select array_agg(distinct y ->> 'project_id') into projs from jsonb_array_elements(acc) y;
  insert into import_batches (project_id, kind, file_name, file_hash, rows_total, rows_accepted, rows_rejected, recon_status, recon_accepted_by, detail, by_user)
  values (case when array_length(projs, 1) = 1 then projs[1] end, 'issues', left(p ->> 'file_name', 200), p ->> 'hash', jsonb_array_length(rows), jsonb_array_length(acc), jsonb_array_length(rej),
          case when jsonb_array_length(rej) > 0 then 'Accepted with difference' end, case when jsonb_array_length(rej) > 0 then me end,
          jsonb_build_object('rejected', rej, 'projects', to_jsonb(projs)), me) returning id into bid;
  for x in select * from jsonb_array_elements(acc) loop
    select id into iid from issues where project_id = x ->> 'project_id' and lower(regexp_replace(btrim(description), '\s+', ' ', 'g')) = lower(regexp_replace(btrim(x ->> 'description'), '\s+', ' ', 'g')) order by created_at limit 1;
    st := case when lower(btrim(coalesce(x ->> 'status', ''))) = 'closed' then 'Closed' else 'Open' end;
    if iid is null then
      iid := pt_issue_new(x ->> 'project_id', x ->> 'description'); ch := pt_issue_apply(iid, x - 'project_id' - 'status' - 'closed_on');
      update issues set status = st, closed_on = case when st = 'Closed' then coalesce(pt_date(x ->> 'closed_on'), pt_date(x ->> 'data_date'), current_date) end where id = iid;
      perform pt_issue_log(iid, 'Imported', p ->> 'file_name', jsonb_build_object('batch', bid)); created := created + 1;
    else
      ch := pt_issue_apply(iid, x - 'project_id' - 'status' - 'closed_on' - 'description');
      if st is distinct from (select status from issues where id = iid) then
        update issues set status = st, closed_on = case when st = 'Closed' then coalesce(pt_date(x ->> 'closed_on'), current_date) end where id = iid; ch := ch || 'status'::text; end if;
      if array_length(ch, 1) > 0 then perform pt_issue_log(iid, 'Updated from upload', p ->> 'file_name', jsonb_build_object('batch', bid, 'changes', to_jsonb(ch))); updated := updated + 1;
      else same := same + 1; end if;
    end if;
  end loop;
  return jsonb_build_object('duplicate', false, 'batch_id', bid, 'created', created, 'updated', updated, 'unchanged', same, 'rejected', rej);
end $$;
-- doc_act: as in schema-update-v13.sql
create or replace function doc_act(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); a text := p ->> 'action'; pid text; k text; d documents; o record; n text := p ->> 'note';
        f jsonb := coalesce(p -> 'fields', '{}'::jsonb); ch text[] := '{}'; x text; rw text; i int; sz bigint; mt text; st text;
begin
  if me is null or role_of(me) is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if a is null or a not in ('add','edit','status','box_save','box_order') then raise exception 'Unknown action %', a; end if;

  if a in ('edit','status') then
    select * into d from documents where id = nullif(p ->> 'id', '')::uuid for update;
    if d.id is null or not pt_doc_can(me, d.project_id, d.box_key, false) then raise exception 'Unknown document'; end if;
    if not pt_doc_can(me, d.project_id, d.box_key, true) then raise exception 'You can see this document but not change it' using errcode = '42501'; end if;
    if a = 'status' then
      st := p ->> 'status';
      if st is null or st not in ('Draft','Submitted','Issued','Approved','Certified','Rejected','Paid','Superseded','For information') then raise exception 'Unknown status %', st; end if;
      if st = d.status then return to_jsonb(d); end if;
      x := d.status;
      if st in ('Rejected','Superseded') and nullif(btrim(coalesce(n, '')), '') is null then raise exception 'Add a comment saying why the document is %', lower(st); end if;
      update documents set status = st, updated_by = me, updated_at = now() where id = d.id returning * into d;
      perform pt_doc_log(d.id, d.project_id, d.box_key, 'Status ' || st, n, jsonb_build_object('from', x, 'to', st));
      return to_jsonb(d);
    end if;
    -- edit: details only, never the file
    if f ? 'title' and length(btrim(coalesce(f ->> 'title', ''))) not between 1 and 200 then raise exception 'The title is needed (200 characters at most)'; end if;
    if f ? 'period' and nullif(f ->> 'period', '') is not null and not ((f ->> 'period') ~ '^\d{4}-(0[1-9]|1[0-2])$' or (f ->> 'period') ~ '^\d{4}-W(0[1-9]|[1-4]\d|5[0-3])$') then raise exception 'The period must look like 2026-09 or 2026-W41'; end if;
    if f ? 'doc_date' and pt_bad_date(f ->> 'doc_date') then raise exception 'The document date is not a valid date'; end if;
    foreach x in array array['title','category','ref_no','revision','period','doc_date','description'] loop
      if f ? x and (to_jsonb(d) ->> x) is distinct from nullif(btrim(coalesce(f ->> x, '')), '') then ch := ch || x; end if;
    end loop;
    if array_length(ch, 1) is null then return to_jsonb(d); end if;
    update documents set
      title = case when f ? 'title' then btrim(f ->> 'title') else title end,
      category = case when f ? 'category' then nullif(btrim(coalesce(f ->> 'category', '')), '') else category end,
      ref_no = case when f ? 'ref_no' then nullif(btrim(coalesce(f ->> 'ref_no', '')), '') else ref_no end,
      revision = case when f ? 'revision' then nullif(btrim(coalesce(f ->> 'revision', '')), '') else revision end,
      period = case when f ? 'period' then nullif(btrim(coalesce(f ->> 'period', '')), '') else period end,
      doc_date = case when f ? 'doc_date' then pt_date(f ->> 'doc_date') else doc_date end,
      description = case when f ? 'description' then nullif(btrim(coalesce(f ->> 'description', '')), '') else description end,
      updated_by = me, updated_at = now()
     where id = d.id returning * into d;
    perform pt_doc_log(d.id, d.project_id, d.box_key, 'Details changed', n, jsonb_build_object('changes', to_jsonb(ch)));
    return to_jsonb(d);
  end if;

  pid := p ->> 'project_id';
  if pid is null or not user_sees(me, pid) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;

  if a = 'add' then
    k := upper(btrim(coalesce(p ->> 'box_key', '')));
    if not pt_doc_can(me, pid, k, true) then raise exception 'Only the people who keep this row can add documents to it' using errcode = '42501'; end if;
    x := p ->> 'storage_path';
    if x is null or split_part(x, '/', 1) <> pid or split_part(x, '/', 2) <> k or array_length(string_to_array(x, '/'), 1) <> 4 then
      raise exception 'The file is not in this box''s folder'; end if;
    select (metadata ->> 'size')::bigint, metadata ->> 'mimetype' into sz, mt from storage.objects where bucket_id = 'project-docs' and name = x;
    if not found then raise exception 'The file was not found in storage; upload it again'; end if;
    if exists (select 1 from documents where storage_path = x) then raise exception 'This file is already registered'; end if;
    if length(btrim(coalesce(p ->> 'title', ''))) not between 1 and 200 then raise exception 'The title is needed (200 characters at most)'; end if;
    st := coalesce(nullif(p ->> 'status', ''), 'For information');
    if st not in ('Draft','Submitted','Issued','Approved','Certified','Rejected','Paid','Superseded','For information') then raise exception 'Unknown status %', st; end if;
    if nullif(p ->> 'period', '') is not null and not ((p ->> 'period') ~ '^\d{4}-(0[1-9]|1[0-2])$' or (p ->> 'period') ~ '^\d{4}-W(0[1-9]|[1-4]\d|5[0-3])$') then
      raise exception 'The period must look like 2026-09 or 2026-W41'; end if;
    if pt_bad_date(p ->> 'doc_date') then raise exception 'The document date is not a valid date'; end if;
    if nullif(p ->> 'supersedes', '') is not null and not exists (select 1 from documents where id = (p ->> 'supersedes')::uuid and project_id = pid and box_key = k) then
      raise exception 'A new revision must be in the same box as the document it replaces'; end if;
    insert into documents (project_id, box_key, title, category, ref_no, revision, period, doc_date, status, description, storage_path, file_name, file_size, mime, sha256, supersedes, created_by, updated_by)
    values (pid, k, btrim(p ->> 'title'), nullif(btrim(coalesce(p ->> 'category', '')), ''), nullif(btrim(coalesce(p ->> 'ref_no', '')), ''),
            nullif(btrim(coalesce(p ->> 'revision', '')), ''), nullif(p ->> 'period', ''), pt_date(p ->> 'doc_date'), st,
            nullif(btrim(coalesce(p ->> 'description', '')), ''), x, coalesce(nullif(btrim(p ->> 'file_name'), ''), split_part(x, '/', 4)), sz, mt,
            nullif(lower(p ->> 'sha256'), ''), nullif(p ->> 'supersedes', '')::uuid, me, me)
    returning * into d;
    perform pt_doc_log(d.id, pid, k, case when d.supersedes is null then 'Uploaded' else 'New revision uploaded' end, n,
                       jsonb_build_object('file', d.file_name, 'size', d.file_size, 'revision', d.revision, 'supersedes', d.supersedes));
    return to_jsonb(d);
  end if;

  if a = 'box_save' then
    k := upper(btrim(coalesce(p ->> 'box_key', '')));
    if k = '' then   -- a new box
      rw := p ->> 'row_key';
      if rw is null or rw not in ('contract','planning','cost') then raise exception 'Choose the row for the new box'; end if;
      if length(btrim(coalesce(p ->> 'title', ''))) not between 1 and 80 then raise exception 'The box needs a name (80 characters at most)'; end if;
      if not (role_of(me) = 'sa' or pt_is_head(me) or (rw = 'planning' and role_of(me) = 'plan') or (rw <> 'planning' and role_of(me) = 'costing')) then
        raise exception 'Only the people who keep this row can add boxes to it' using errcode = '42501'; end if;
      if (select count(*) from doc_boxes where project_id = pid and box_key like 'X%') >= 60 then raise exception 'At most 60 added boxes per project'; end if;
      loop k := 'X' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6)); exit when not exists (select 1 from doc_boxes where project_id = pid and box_key = k); end loop;
      insert into doc_boxes (project_id, box_key, row_key, title, sort, note, created_by, updated_by)
      values (pid, k, rw, btrim(p ->> 'title'), coalesce((p ->> 'sort')::int, 1000), nullif(btrim(coalesce(p ->> 'note', '')), ''), me, me);
      perform pt_doc_log(null, pid, k, 'Box added', p ->> 'title', jsonb_build_object('row', rw));
      return jsonb_build_object('box_key', k);
    end if;
    rw := pt_doc_row(pid, k);
    if rw is null then raise exception 'Unknown box %', k; end if;
    if not pt_doc_can(me, pid, k, true) then raise exception 'Only the people who keep this row can change its boxes' using errcode = '42501'; end if;
    if p ? 'title' and nullif(btrim(coalesce(p ->> 'title', '')), '') is not null and length(btrim(p ->> 'title')) > 80 then raise exception 'The box name is too long (80 characters at most)'; end if;
    insert into doc_boxes (project_id, box_key, row_key, title, sort, hidden, note, created_by, updated_by)
    values (pid, k, rw, case when p ? 'title' then nullif(btrim(coalesce(p ->> 'title', '')), '') end, (p ->> 'sort')::int, coalesce((p ->> 'hidden')::boolean, false),
            case when p ? 'note' then nullif(btrim(coalesce(p ->> 'note', '')), '') end, me, me)
    on conflict (project_id, box_key) do update set
      title = case when p ? 'title' then nullif(btrim(coalesce(p ->> 'title', '')), '') else doc_boxes.title end,
      sort = case when p ? 'sort' then (p ->> 'sort')::int else doc_boxes.sort end,
      hidden = case when p ? 'hidden' then (p ->> 'hidden')::boolean else doc_boxes.hidden end,
      note = case when p ? 'note' then nullif(btrim(coalesce(p ->> 'note', '')), '') else doc_boxes.note end,
      updated_by = me, updated_at = now();
    perform pt_doc_log(null, pid, k, 'Box changed', null, p - 'action' - 'project_id' - 'box_key');
    return jsonb_build_object('box_key', k);
  end if;

  -- box_order: the boxes of one row, in the order given
  rw := p ->> 'row_key';
  if rw is null or rw not in ('contract','planning','cost') then raise exception 'Choose the row to reorder'; end if;
  if jsonb_typeof(p -> 'keys') <> 'array' then raise exception 'Give the boxes in their new order'; end if;
  i := 0;
  for x in select jsonb_array_elements_text(p -> 'keys') loop
    i := i + 1; k := upper(x);
    if pt_doc_row(pid, k) is distinct from rw then raise exception 'Box % is not in this row', k; end if;
    if not pt_doc_can(me, pid, k, true) then raise exception 'Only the people who keep this row can reorder it' using errcode = '42501'; end if;
    insert into doc_boxes (project_id, box_key, row_key, sort, created_by, updated_by) values (pid, k, rw, i * 10, me, me)
    on conflict (project_id, box_key) do update set sort = i * 10, updated_by = me, updated_at = now();
  end loop;
  perform pt_doc_log(null, pid, null, 'Boxes reordered', null, jsonb_build_object('row', rw, 'keys', p -> 'keys'));
  return jsonb_build_object('ok', true);
end $$;
-- log_import: as in schema-update-v9.sql
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
  if not (r in ('sa','costing') or pt_is_coord(me)) then raise exception 'Only a costing engineer, the costing coordinator or a super admin uploads this log' using errcode = '42501'; end if;
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

drop function if exists rights_save(jsonb);
drop function if exists people_access();
drop function if exists pt_cost_approver(uuid);
drop function if exists pt_doc_keep(uuid, text);
drop function if exists pt_right(uuid, text, boolean);
drop function if exists pt_role_key(uuid);
drop function if exists pt_right_default(text, text);
drop function if exists pt_rights();
drop function if exists pt_screens();
drop function if exists pt_builtin_roles();
