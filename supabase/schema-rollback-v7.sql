-- ProTrack: undo schema update v7 (ProTrackAI v2.8). Removes the Tender register functions and puts back the v6
-- lifecycle rules and checklists. Keeps every project, Tender detail, PE history entry, designation, stage and
-- stage history (nothing is deleted). Supabase -> SQL Editor -> New query -> paste -> Run. Safe to run twice.
drop function if exists tender_act(jsonb);
drop function if exists pe_proposal();
drop function if exists pcc_designate(jsonb);
drop trigger if exists trg_proj_guard on projects;
drop function if exists pt_proj_guard();
drop index if exists projects_pe_live_uq;

-- the v6 lifecycle rules, exactly as they were
-- ------------------------------------------------------------------ stage definitions (the app shows the same)
create or replace function pt_lc_dept(n int) returns text language sql immutable as $$
  select (array['Tendering','Tendering','Contracts','Projects','Planning and Cost Control','Planning','Projects and site',
                'Procurement','Cost Control','Contracts and commercial','Planning and project management','Commercial and projects'])[n] $$;

create or replace function pt_lc_template(n int) returns jsonb language sql immutable as $$
  select case n
  when 1 then '[{"k":"notice","label":"Tender notice received","req":true},{"k":"bid","label":"Bid or no-bid decision recorded","req":true},{"k":"team","label":"Tender team named","req":false}]'
  when 2 then '[{"k":"number","label":"Project number given under the numbering convention","req":true},{"k":"registered","label":"Project registered in ProTrackAI","req":true},{"k":"notified","label":"Stakeholders notified","req":false}]'
  when 3 then '[{"k":"loa","label":"Letter of award received","req":true},{"k":"contract","label":"Contract signed","req":true},{"k":"terms","label":"Contract value and payment terms recorded","req":true},{"k":"bonds","label":"Bonds and insurances in place","req":false}]'
  when 4 then '[{"k":"docs","label":"Tender documents handed over","req":true},{"k":"scope","label":"Scope and BOQ clarified","req":true},{"k":"minutes","label":"Handover meeting minutes","req":false},{"k":"team","label":"Project team assigned","req":true}]'
  when 5 then '[{"k":"planner","label":"Planning engineer assigned","req":true},{"k":"coster","label":"Costing engineer assigned","req":true},{"k":"matrix","label":"Approval matrix set for the site team","req":true}]'
  when 6 then '[{"k":"prepared","label":"Baseline programme prepared and loaded","req":true},{"k":"dcma","label":"Schedule quality check reviewed","req":false},{"k":"costing","label":"Costing file applied","req":true},{"k":"submitted","label":"Baseline submitted to the client","req":true},{"k":"approved","label":"Client approval of the baseline received","req":true}]'
  when 7 then '[{"k":"dpr","label":"Daily reports flowing","req":true},{"k":"weekly","label":"Weekly progress updates current","req":true},{"k":"lookahead","label":"Look-ahead programme issued","req":false}]'
  when 8 then '[{"k":"pos","label":"Subcontract purchase orders recorded","req":true},{"k":"longlead","label":"Long-lead items tracked","req":true},{"k":"materials","label":"Material tracking in place","req":false}]'
  when 9 then '[{"k":"budget","label":"Budget loaded from the costing file","req":true},{"k":"invoices","label":"Invoice register current","req":true},{"k":"forecast","label":"Forecast at completion reviewed","req":true}]'
  when 10 then '[{"k":"register","label":"Variation register maintained","req":true},{"k":"claims","label":"Claims and extension of time submitted where due","req":false},{"k":"approvals","label":"Variation approvals recorded","req":true}]'
  when 11 then '[{"k":"report","label":"Monthly report issued","req":true},{"k":"review","label":"Management review held","req":true},{"k":"actions","label":"Actions from the review assigned","req":false}]'
  when 12 then '[{"k":"tcc","label":"Technical completion (TCC) achieved","req":true},{"k":"pac","label":"Provisional acceptance (PAC) achieved","req":true},{"k":"final","label":"Final account agreed","req":true},{"k":"handover","label":"Handover to operations","req":true},{"k":"lessons","label":"Lessons learned recorded","req":false}]'
  end::jsonb $$;

-- who may approve a stage: a super admin, or a project manager on that project
create or replace function pt_lc_approver(u uuid, p text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) = 'sa' or (role_of(u) = 'pm' and user_sees(u, p)), false) $$;

-- ------------------------------------------------------------------ the one way to change a stage
-- p: {project_id, stage_no, action: update|start|submit|approve|return|na|reopen, note,
--     fields:{owner, department, due_date, next_action, blockers, risk}, ticks:[{k, done}]}
create or replace function lifecycle_act(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r text := role_of(auth.uid()); pid text := p ->> 'project_id'; n int := pt_num(p ->> 'stage_no');
        a text := p ->> 'action'; note text := nullif(btrim(coalesce(p ->> 'note', '')), ''); s lifecycle_stages;
        f jsonb := coalesce(p -> 'fields', '{}'::jsonb); boss boolean; editor boolean; t jsonb; d jsonb; missing text; newowner uuid; changes text[] := '{}';
begin
  if me is null or r is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if pid is null or not user_sees(me, pid) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
  if n is null or n < 1 or n > 12 or n <> trunc(n) then raise exception 'Unknown lifecycle stage'; end if;
  if a is null or a not in ('update','start','submit','approve','return','na','reopen') then raise exception 'Unknown action %', a; end if;
  perform pg_advisory_xact_lock(hashtext('protrack:lc:' || pid || ':' || n));

  select * into s from lifecycle_stages where project_id = pid and stage_no = n for update;
  if s.project_id is null then
    insert into lifecycle_stages (project_id, stage_no, department, deliverables)
    values (pid, n, pt_lc_dept(n), (select jsonb_agg(x || '{"done":false}'::jsonb) from jsonb_array_elements(pt_lc_template(n)) x))
    returning * into s;
  end if;

  boss := pt_lc_approver(me, pid);
  editor := coalesce(boss, false) or coalesce(s.owner = me, false);   -- no owner yet means "not the owner", never "unknown"

  if a = 'update' then
    if not editor then raise exception 'Only the stage owner, the project manager or a super admin can change this stage' using errcode = '42501'; end if;
    if s.status in ('Complete','Not applicable') then raise exception 'This stage is %; a super admin must reopen it first', lower(s.status) using errcode = '42501'; end if;
    if f ? 'owner' then
      if not boss then raise exception 'Only the project manager or a super admin can assign the owner' using errcode = '42501'; end if;
      newowner := nullif(f ->> 'owner', '')::uuid;
      if newowner is not null and (role_of(newowner) is null or not user_sees(newowner, pid)) then
        raise exception 'The owner must be an active person with access to this project'; end if;
      if newowner is distinct from s.owner then changes := changes || ('owner ' || coalesce(name_of(newowner), 'none')); end if;
      s.owner := newowner;
    end if;
    if f ? 'due_date' then
      if pt_bad_date(f ->> 'due_date') then raise exception 'The due date is not a valid date'; end if;
      if pt_date(f ->> 'due_date') is distinct from s.due_date then changes := changes || ('due ' || coalesce(f ->> 'due_date', 'none')); end if;
      s.due_date := pt_date(f ->> 'due_date');
    end if;
    if f ? 'department' then s.department := left(nullif(btrim(f ->> 'department'), ''), 80); end if;
    if f ? 'next_action' and (f ->> 'next_action') is distinct from s.next_action then changes := changes || 'next action'::text; s.next_action := left(nullif(btrim(f ->> 'next_action'), ''), 500); end if;
    if f ? 'blockers' and (f ->> 'blockers') is distinct from s.blockers then changes := changes || 'blockers'::text; s.blockers := left(nullif(btrim(f ->> 'blockers'), ''), 500); end if;
    if f ? 'risk' and (f ->> 'risk') is distinct from s.risk then changes := changes || 'risk'::text; s.risk := left(nullif(btrim(f ->> 'risk'), ''), 500); end if;
    for t in select * from jsonb_array_elements(coalesce(p -> 'ticks', '[]'::jsonb)) loop
      if not exists (select 1 from jsonb_array_elements(s.deliverables) x where x ->> 'k' = t ->> 'k') then raise exception 'Unknown deliverable %', t ->> 'k'; end if;
      select jsonb_agg(case when x ->> 'k' = t ->> 'k' and coalesce((x ->> 'done')::boolean, false) is distinct from coalesce((t ->> 'done')::boolean, false)
                            then x || jsonb_build_object('done', coalesce((t ->> 'done')::boolean, false), 'by', name_of(me), 'at', to_char(now(), 'YYYY-MM-DD HH24:MI'))
                            else x end)
        into s.deliverables from jsonb_array_elements(s.deliverables) x;
      changes := changes || ((case when coalesce((t ->> 'done')::boolean, false) then 'ticked ' else 'unticked ' end) || (t ->> 'k'));
    end loop;
    if s.status = 'Not started' and (array_length(changes, 1) > 0) and exists (select 1 from jsonb_array_elements(s.deliverables) x where (x ->> 'done')::boolean) then
      s.status := 'In progress'; changes := changes || 'started'::text;
    end if;
  elsif a = 'start' then
    if not editor then raise exception 'Only the stage owner, the project manager or a super admin can start this stage' using errcode = '42501'; end if;
    if s.status <> 'Not started' then raise exception 'This stage is already %', lower(s.status); end if;
    s.status := 'In progress';
  elsif a = 'submit' then
    if not editor then raise exception 'Only the stage owner, the project manager or a super admin can submit this stage' using errcode = '42501'; end if;
    if s.status not in ('Not started','In progress') then raise exception 'Only a stage in progress can be submitted; this one is %', lower(s.status); end if;
    if s.owner is null then raise exception 'Assign an owner before submitting'; end if;
    select string_agg(x ->> 'label', '; ') into missing from jsonb_array_elements(s.deliverables) x
     where coalesce((x ->> 'req')::boolean, false) and not coalesce((x ->> 'done')::boolean, false);
    if missing is not null then raise exception 'Required deliverables are not done: %', missing; end if;
    s.status := 'Awaiting approval'; s.submitted_by := me; s.submitted_at := now();
  elsif a = 'approve' then
    if not boss then raise exception 'Only the project manager or a super admin can approve a stage' using errcode = '42501'; end if;
    if s.status <> 'Awaiting approval' then raise exception 'Only a stage awaiting approval can be approved'; end if;
    if s.submitted_by = me then raise exception 'You submitted this stage, so someone else must approve it' using errcode = '42501'; end if;
    s.status := 'Complete'; s.approved_by := me; s.approved_at := now();
  elsif a = 'return' then
    if not boss then raise exception 'Only the project manager or a super admin can return a stage' using errcode = '42501'; end if;
    if s.status <> 'Awaiting approval' then raise exception 'Only a stage awaiting approval can be returned'; end if;
    if note is null then raise exception 'Add a comment saying what to fix'; end if;
    s.status := 'In progress'; s.submitted_by := null; s.submitted_at := null;
  elsif a = 'na' then
    if not boss then raise exception 'Only the project manager or a super admin can mark a stage not applicable' using errcode = '42501'; end if;
    if s.status in ('Complete','Not applicable') then raise exception 'This stage is already %', lower(s.status); end if;
    if note is null then raise exception 'Add a comment saying why the stage does not apply'; end if;
    s.status := 'Not applicable';
  elsif a = 'reopen' then
    if r <> 'sa' then raise exception 'Only a super admin can reopen a stage' using errcode = '42501'; end if;
    if s.status not in ('Complete','Not applicable') then raise exception 'Only a complete or not-applicable stage can be reopened'; end if;
    if note is null then raise exception 'Add a comment saying why the stage is reopened'; end if;
    s.status := 'In progress'; s.approved_by := null; s.approved_at := null; s.submitted_by := null; s.submitted_at := null;
  end if;

  update lifecycle_stages set status = s.status, owner = s.owner, department = s.department, due_date = s.due_date,
    deliverables = s.deliverables, next_action = s.next_action, blockers = s.blockers, risk = s.risk,
    submitted_by = s.submitted_by, submitted_at = s.submitted_at, approved_by = s.approved_by, approved_at = s.approved_at, updated_at = now()
   where project_id = pid and stage_no = n
  returning * into s;
  if a <> 'update' or array_length(changes, 1) > 0 then
    insert into lifecycle_audit (project_id, stage_no, action, note, detail, by_user, by_name, by_role)
    values (pid, n, case a when 'update' then 'Updated' when 'start' then 'Started' when 'submit' then 'Submitted for approval'
                           when 'approve' then 'Approved' when 'return' then 'Returned' when 'na' then 'Marked not applicable' else 'Reopened' end,
            note, case when a = 'update' then jsonb_build_object('changes', to_jsonb(changes)) end, me, name_of(me), r);
  end if;
  return to_jsonb(s);
end $$;

revoke execute on function pt_lc_dept(int), pt_lc_template(int), pt_lc_approver(uuid, text), lifecycle_act(jsonb) from public, anon, authenticated;
grant execute on function lifecycle_act(jsonb) to authenticated;

drop function if exists pt_lc_boss(uuid, text, int);
drop function if exists pt_lc_boss_text(int);
drop function if exists pt_lc_row(text, int);
drop function if exists pt_reg_log(text, text, text, jsonb, text);
drop function if exists pt_pe_propose();
drop function if exists pt_pe_holder(text, text);
drop function if exists pt_can_register(uuid);
drop function if exists pt_is_coord(uuid);
drop function if exists pt_is_head(uuid);
drop function if exists pt_pe_seq(text);
drop function if exists pt_pe_canon(text);
