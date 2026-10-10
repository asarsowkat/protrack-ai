-- ProTrack schema update v12 (ProTrackAI v3.3): the monthly cost report in the company format, by WBS head.
-- Each cost report may carry WBS lines (tender, Rev-0, revised Rev-0, previous version, current budget, actual, commitment,
-- ETC, justification). The server works out balance, EAC and supplement/saving per line and every total, and takes the
-- previous version from the last released cost report. Cost reports without WBS lines work exactly as before.
-- Additive: one helper; release_act accepts the WBS lines. No table changes. Safe to run twice.
-- Undo with schema-rollback-v12.sql (keeps every cost report).

-- The cost report by WBS head (columns of the company format):
--   A tender, B1 Rev-0, B2 revised Rev-0 (latest approved CRF), C previous version, D current budget, E actual,
--   F commitment, G balance = D - E - F, H ETC, I EAC = E + F + H, J supplement (-) / saving (+) = D - I.
-- C is the current budget of the last released cost report of the project, when there is one.
-- The overall figures keep the meaning used everywhere else: budget_current = D, ftc = F + H, eac = E + F + H, vac = D - EAC.
create or replace function pt_cost_wbs(pid text, per text, f jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare w jsonb := f -> 'wbs'; x jsonb; y jsonb; outl jsonb := '[]'::jsonb; prevf jsonb; prevper text; codes text[] := '{}'; c text; k text; v numeric;
        n jsonb; lp numeric; l_t numeric; l_r0 numeric; l_rr numeric; l_b numeric; l_a numeric; l_c numeric; l_e numeric;
        t_t numeric := 0; t_r0 numeric := 0; t_rr numeric := 0; t_p numeric := 0; t_b numeric := 0; t_a numeric := 0; t_c numeric := 0; t_e numeric := 0;
begin
  if jsonb_typeof(w) is distinct from 'array' or jsonb_array_length(w) = 0 then raise exception 'The cost report needs at least one WBS line'; end if;
  if jsonb_array_length(w) > 60 then raise exception 'At most 60 WBS lines'; end if;
  select r.period, r.figures into prevper, prevf from report_releases r
   where r.project_id = pid and r.kind = 'cost' and r.status = 'Released' and r.period < per order by r.period desc, r.rev desc limit 1;
  for x in select * from jsonb_array_elements(w) loop
    if jsonb_typeof(x) <> 'object' then raise exception 'Each WBS line must be a row'; end if;
    c := upper(btrim(coalesce(x ->> 'code', '')));
    if c = '' or length(c) > 20 then raise exception 'Each WBS line needs a code of up to 20 characters'; end if;
    if c = any(codes) then raise exception 'WBS % appears twice', c; end if;
    codes := codes || c;
    if length(coalesce(x ->> 'name', '')) > 60 then raise exception 'The WBS name for % is too long', c; end if;
    if length(coalesce(x ->> 'justification', '')) > 600 then raise exception 'The justification for % is too long (600 characters at most)', c; end if;
    foreach k in array array['tender','rev0','rev0_rev','prev','budget','actual','commitment','etc'] loop
      if x ? k and jsonb_typeof(x -> k) not in ('number','null') and pt_bad_num(x ->> k) then raise exception 'WBS %: % must be a number', c, k; end if;
      if coalesce(pt_num(x ->> k), 0) < 0 then raise exception 'WBS %: % cannot be negative', c, k; end if;
    end loop;
    l_t := coalesce(pt_num(x ->> 'tender'), 0); l_r0 := coalesce(pt_num(x ->> 'rev0'), 0); l_rr := coalesce(pt_num(x ->> 'rev0_rev'), 0);
    l_b := coalesce(pt_num(x ->> 'budget'), 0); l_a := coalesce(pt_num(x ->> 'actual'), 0); l_c := coalesce(pt_num(x ->> 'commitment'), 0); l_e := coalesce(pt_num(x ->> 'etc'), 0);
    if prevf is not null and jsonb_typeof(prevf -> 'wbs') = 'array' then
      lp := null;
      select coalesce(pt_num(y2 ->> 'budget'), 0) into lp from jsonb_array_elements(prevf -> 'wbs') y2 where upper(btrim(y2 ->> 'code')) = c limit 1;
      lp := coalesce(lp, 0);
    else
      lp := coalesce(pt_num(x ->> 'prev'), 0);
    end if;
    n := jsonb_build_object('code', c, 'name', left(btrim(coalesce(x ->> 'name', '')), 60),
           'tender', l_t, 'rev0', l_r0, 'rev0_rev', l_rr, 'prev', lp, 'budget', l_b, 'actual', l_a, 'commitment', l_c, 'etc', l_e,
           'balance', l_b - l_a - l_c, 'eac', l_a + l_c + l_e, 'var', l_b - (l_a + l_c + l_e),
           'justification', nullif(left(btrim(coalesce(x ->> 'justification', '')), 600), ''));
    outl := outl || jsonb_build_array(n);
    t_t := t_t + l_t; t_r0 := t_r0 + l_r0; t_rr := t_rr + l_rr; t_p := t_p + lp; t_b := t_b + l_b; t_a := t_a + l_a; t_c := t_c + l_c; t_e := t_e + l_e;
  end loop;
  foreach k in array array['planned_poc','actual_poc'] loop
    v := pt_num(f ->> k); if v is not null and (v < 0 or v > 100) then raise exception '% must be between 0 and 100', k; end if;
  end loop;
  if coalesce(pt_num(f ->> 'contract_value'), 0) < 0 then raise exception 'The contract value cannot be negative'; end if;
  return (f - 'wbs' - 'prev_period_text') || jsonb_build_object('wbs', outl,
    'tender_total', t_t, 'budget_rev0', t_r0, 'rev0_rev_total', t_rr, 'prev_total', t_p, 'budget_current', t_b,
    'actual', t_a, 'commitment', t_c, 'etc', t_e, 'balance_total', t_b - t_a - t_c,
    'ftc', t_c + t_e, 'eac', t_a + t_c + t_e, 'vac', t_b - (t_a + t_c + t_e),
    'supplements_approved', pt_supp_approved(pid, per))
    || case when prevper is not null and jsonb_typeof(prevf -> 'wbs') = 'array' then jsonb_build_object('prev_period_text', prevper) else '{}'::jsonb end;
end $$;
revoke execute on function pt_cost_wbs(text, text, jsonb) from public, anon, authenticated;

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
    update report_releases set status = 'Submitted', submitted_by = me, submitted_at = now(), updated_at = now() where id = rel.id returning * into rel;
    perform pt_rel_log(rel.id, 'Submitted for approval', note, null);
  elsif a = 'approve' then
    if not (r = 'sa' or pt_is_head(me)) then raise exception 'Only the Head of Planning and Cost Control or a super admin can approve a release' using errcode = '42501'; end if;
    if rel.status <> 'Submitted' then raise exception 'Only a submitted version can be approved'; end if;
    if rel.submitted_by = me then raise exception 'You submitted this version, so someone else must approve it' using errcode = '42501'; end if;
    update report_releases set status = 'Superseded', updated_at = now()
     where project_id = rel.project_id and kind = rel.kind and period_type = rel.period_type and period = rel.period and status = 'Released';
    update report_releases set status = 'Released', approved_by = me, approved_at = now(), updated_at = now(),
           issues_snapshot = case when rel.kind = 'planning' then pt_issue_snapshot(rel.project_id) else issues_snapshot end
     where id = rel.id returning * into rel;
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

