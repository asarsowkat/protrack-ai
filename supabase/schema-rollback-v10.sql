-- ProTrack: undo schema update v10 (ProTrackAI v3.1). Removes the issue functions and puts back the v9 release rules.
-- Keeps every issue, its history and every release with its saved issues (nothing is deleted). Safe to run twice.
drop function if exists issue_act(jsonb);
drop function if exists issue_import(jsonb);
create or replace function pt_release_frozen() returns trigger language plpgsql as $$
begin
  if old.status in ('Released','Superseded') and (new.figures is distinct from old.figures or new.overrides is distinct from old.overrides
     or new.narrative is distinct from old.narrative or new.period is distinct from old.period or new.project_id is distinct from old.project_id
     or new.rev is distinct from old.rev or new.data_date is distinct from old.data_date or new.approved_by is distinct from old.approved_by
     or (old.status = 'Superseded' and new.status <> 'Superseded') or (old.status = 'Released' and new.status not in ('Released','Superseded'))) then
    raise exception 'A released version cannot be changed; issue a new revision' using errcode = '42501';
  end if;
  return new;
end $$;

create or replace function release_act(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r text := role_of(auth.uid()); a text := p ->> 'action';
        note text := nullif(btrim(coalesce(p ->> 'note', '')), ''); rel report_releases; cur report_releases;
        pid text; k text; pt text; per text; f jsonb := coalesce(p -> 'figures', '{}'::jsonb); o jsonb := coalesce(p -> 'overrides', '[]'::jsonb);
        nar jsonb := coalesce(p -> 'narrative', '{}'::jsonb); x jsonb; key text; v numeric; budget numeric; supp numeric; nr int;
begin
  if me is null or r is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if a is null or a not in ('save','submit','approve','return','revise') then raise exception 'Unknown action %', a; end if;
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
    else
      foreach key in array array['budget_rev0','actual','commitment','ftc'] loop
        v := pt_num(f ->> key);
        if v is null then raise exception 'Enter %', case key when 'budget_rev0' then 'the Rev-0 budget' when 'actual' then 'the actual cost to date' when 'commitment' then 'the commitments' else 'the forecast cost to complete' end; end if;
        if v < 0 then raise exception '% cannot be negative', key; end if;
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
    update report_releases set status = 'Submitted', submitted_by = me, submitted_at = now(), updated_at = now() where id = rel.id returning * into rel;
    perform pt_rel_log(rel.id, 'Submitted for approval', note, null);
  elsif a = 'approve' then
    if not (r = 'sa' or pt_is_head(me)) then raise exception 'Only the Head of Planning and Cost Control or a super admin can approve a release' using errcode = '42501'; end if;
    if rel.status <> 'Submitted' then raise exception 'Only a submitted version can be approved'; end if;
    if rel.submitted_by = me then raise exception 'You submitted this version, so someone else must approve it' using errcode = '42501'; end if;
    update report_releases set status = 'Superseded', updated_at = now()
     where project_id = rel.project_id and kind = rel.kind and period_type = rel.period_type and period = rel.period and status = 'Released';
    update report_releases set status = 'Released', approved_by = me, approved_at = now(), updated_at = now() where id = rel.id returning * into rel;
    perform pt_rel_log(rel.id, 'Approved and released', note, jsonb_build_object('rev', rel.rev));
  elsif a = 'return' then
    if not (r = 'sa' or pt_is_head(me)) then raise exception 'Only the Head of Planning and Cost Control or a super admin can return a release' using errcode = '42501'; end if;
    if rel.status <> 'Submitted' then raise exception 'Only a submitted version can be returned'; end if;
    if note is null then raise exception 'Add a comment saying what to fix'; end if;
    update report_releases set status = 'Draft', submitted_by = null, submitted_at = null, updated_at = now() where id = rel.id returning * into rel;
    perform pt_rel_log(rel.id, 'Returned', note, null);
  end if;
  return to_jsonb(rel);
end $$;
drop function if exists pt_issue_new(text, text);
drop function if exists pt_issue_apply(uuid, jsonb);
drop function if exists pt_issue_log(uuid, text, text, jsonb);
drop function if exists pt_issue_snapshot(text);
drop function if exists pt_prio(text);
drop function if exists pt_impact(text);
drop function if exists pt_issue_editor(uuid, text);
revoke execute on function release_act(jsonb) from public, anon;
grant execute on function release_act(jsonb) to authenticated;
