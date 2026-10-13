-- ProTrack rollback v15 (ProTrackAI v3.6 back to v3.5).
-- Stops new weightage changes, schedule uploads and client reports, and brings back the v3.5 release rules
-- (release_act, the frozen-version rule and the read rule as in v14). Nothing is deleted: the phase weightage and its
-- history, every updated schedule, every client report and the validation notes stay, and stay readable.
-- The kind check on report_releases keeps 'client', so client reports already saved remain valid.

drop function if exists phase_setup_save(jsonb);
drop function if exists schedule_update_commit(jsonb);
drop function if exists pt_rel_sched(text, text, text, text, jsonb);
drop function if exists pt_rel_client_calc(text, text, text, jsonb);

create or replace function pt_release_staff(u uuid, k text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) = 'sa' or pt_is_head(u) or (k = 'planning' and role_of(u) = 'plan')
                  or (k = 'cost' and (role_of(u) = 'costing' or pt_is_coord(u))), false) $$;
create or replace function pt_release_preparer(u uuid, k text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) = 'sa' or (k = 'planning' and role_of(u) = 'plan') or (k = 'cost' and (role_of(u) = 'costing' or pt_is_coord(u))), false) $$;


-- a released version never changes; the review fields are frozen too
create or replace function pt_release_frozen() returns trigger language plpgsql as $$
begin
  if old.status in ('Released','Superseded') and (new.figures is distinct from old.figures or new.overrides is distinct from old.overrides
     or new.narrative is distinct from old.narrative or new.period is distinct from old.period or new.project_id is distinct from old.project_id
     or new.rev is distinct from old.rev or new.issues_snapshot is distinct from old.issues_snapshot or new.data_date is distinct from old.data_date or new.approved_by is distinct from old.approved_by
     or new.reviewed_by is distinct from old.reviewed_by or new.reviewed_at is distinct from old.reviewed_at or new.review_note is distinct from old.review_note
     or (old.status = 'Superseded' and new.status <> 'Superseded') or (old.status = 'Released' and new.status not in ('Released','Superseded'))) then
    raise exception 'A released version cannot be changed; issue a new revision' using errcode = '42501';
  end if;
  return new;
end $$;

-- submitted progress releases are visible to the people who review and approve them
drop policy if exists rr_read on report_releases;
create policy rr_read on report_releases for select using (
  can_see(project_id) and (kind <> 'cost' or pt_money_ok()) and (status in ('Released','Superseded') or pt_release_staff(auth.uid(), kind)
    or (kind = 'planning' and status = 'Submitted' and pt_rel_decider(auth.uid(), project_id))));


create or replace function release_act(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r text := role_of(auth.uid()); a text := p ->> 'action';
        note text := nullif(btrim(coalesce(p ->> 'note', '')), ''); rel report_releases; cur report_releases;
        pid text; k text; pt text; per text; f jsonb := coalesce(p -> 'figures', '{}'::jsonb); o jsonb := coalesce(p -> 'overrides', '[]'::jsonb);
        nar jsonb := coalesce(p -> 'narrative', '{}'::jsonb); x jsonb; key text; v numeric; budget numeric; supp numeric; nr int; pmr boolean := pt_rel_pm_review();
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
  if k is null or k not in ('planning','cost') then raise exception 'Unknown release kind'; end if;
  if k = 'cost' and pt <> 'month' then raise exception 'Cost reports are monthly'; end if;
  if not pt_period_ok(per, pt) then raise exception 'The period must look like % ', case pt when 'week' then '2026-W38' else '2026-09' end; end if;
  perform pg_advisory_xact_lock(hashtext('protrack:rel:' || pid || ':' || k || ':' || pt || ':' || per));

  if a in ('save','revise') then
    if not pt_release_preparer(me, k) then
      raise exception '%', case k when 'planning' then 'Only a planning engineer or a super admin prepares progress releases' else 'Only a costing engineer, the costing coordinator or a super admin prepares cost reports' end using errcode = '42501'; end if;
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
      -- v14: the release dashboard fields (milestones, energization, external progress, manpower), checked and worked out here
      f := pt_rel_plan_calc(pid, f);
    elsif f ? 'wbs' then
      -- v12: the cost report by WBS head, in the company format; the server works out every total
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
      -- billing to date (optional, from the invoice register): amounts cannot be negative
      foreach key in array array['inv_invoiceable','inv_submitted','inv_approved','inv_collected'] loop
        v := pt_num(f ->> key); if v is not null and v < 0 then raise exception '% cannot be negative', key; end if;
      end loop;
      -- the server works these out, so every cost report uses the same formulas
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
    -- v12: every WBS line with a supplement or a saving (J = D - I not zero) needs a justification before it goes for approval
    if rel.kind = 'cost' and jsonb_typeof(rel.figures -> 'wbs') = 'array' then
      select string_agg(y ->> 'code', ', ') into key from jsonb_array_elements(rel.figures -> 'wbs') y
       where abs(coalesce(pt_num(y ->> 'var'), 0)) >= 1 and nullif(btrim(coalesce(y ->> 'justification', '')), '') is null;
      if key is not null then raise exception 'Give a justification for each WBS line with a supplement or saving before submitting: %', key; end if;
    end if;
    update report_releases set status = 'Submitted', submitted_by = me, submitted_at = now(), reviewed_by = null, reviewed_at = null, review_note = null, updated_at = now() where id = rel.id returning * into rel;
    perform pt_rel_log(rel.id, 'Submitted for approval', note, null);
  elsif a = 'review' then
    -- v14: the project manager's review, only when a super admin has switched that step on
    if rel.kind <> 'planning' then raise exception 'Only progress releases have a review step'; end if;
    if not pmr then raise exception 'The project manager review step is not switched on'; end if;
    if not (r = 'sa' or (r = 'pm' and user_sees(me, rel.project_id))) then raise exception 'Only the project manager of this project reviews it' using errcode = '42501'; end if;
    if rel.status <> 'Submitted' then raise exception 'Only a submitted version can be reviewed'; end if;
    if rel.reviewed_by is not null then raise exception 'This version is already reviewed'; end if;
    if rel.submitted_by = me then raise exception 'You submitted this version, so someone else must review it' using errcode = '42501'; end if;
    update report_releases set reviewed_by = me, reviewed_at = now(), review_note = note, updated_at = now() where id = rel.id returning * into rel;
    perform pt_rel_log(rel.id, 'Reviewed by the project manager', note, null);
  elsif a = 'approve' then
    if rel.kind = 'planning' then
      if not pt_rel_approver(me, rel.project_id) then raise exception 'Only the Head of Planning and Cost Control, the regional planning section manager or a super admin can approve a progress release' using errcode = '42501'; end if;
    elsif not (r = 'sa' or pt_is_head(me)) then raise exception 'Only the Head of Planning and Cost Control or a super admin can approve a release' using errcode = '42501'; end if;
    if rel.status <> 'Submitted' then raise exception 'Only a submitted version can be approved'; end if;
    if rel.submitted_by = me then raise exception 'You submitted this version, so someone else must approve it' using errcode = '42501'; end if;
    if rel.kind = 'planning' and pmr and rel.reviewed_by is null then raise exception 'The project manager must review this progress release before it is approved'; end if;
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
    if rel.kind = 'planning' then
      if not (pt_rel_approver(me, rel.project_id) or (pmr and r = 'pm' and user_sees(me, rel.project_id) and rel.reviewed_by is null)) then
        raise exception 'Only the Head of Planning and Cost Control, the regional planning section manager or a super admin can return a progress release' using errcode = '42501'; end if;
    elsif not (r = 'sa' or pt_is_head(me)) then raise exception 'Only the Head of Planning and Cost Control or a super admin can return a release' using errcode = '42501'; end if;
    if rel.status <> 'Submitted' then raise exception 'Only a submitted version can be returned'; end if;
    if note is null then raise exception 'Add a comment saying what to fix'; end if;
    update report_releases set status = 'Draft', submitted_by = null, submitted_at = null, reviewed_by = null, reviewed_at = null, review_note = null, updated_at = now() where id = rel.id returning * into rel;
    perform pt_rel_log(rel.id, 'Returned', note, null);
  end if;
  return to_jsonb(rel);
end $$;



revoke execute on function release_act(jsonb) from public, anon;
grant execute on function release_act(jsonb) to authenticated;
