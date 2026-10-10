-- ProTrack schema update v7 (ProTrackAI v2.8: Tender register, PE numbers, stages 1 to 5 follow the Tender-to-SAP process)
-- * Projects carry the Tender details: TE number, client, location, expected value, notification, award and
--   contract-signing dates. A TE number is registered once.
-- * ProTrackAI proposes the PE number: a number released by a cancelled project first, otherwise the next in
--   sequence. Only a super admin can choose another. No two live projects ever hold the same PE number; a
--   cancelled project releases its number so it can go to another L1 project, and the history keeps both.
-- * The costing coordinator records Tender L1 projects and stages 1 to 4; the Head of Planning and Cost
--   Control (or a super admin) approves stages 1 to 5. Project managers keep stages 6 to 12.
-- * Stage 4 is due 7 days after contract signing.
-- Run AFTER schema-update-v6.sql. Additive and safe to run more than once. Undo: schema-rollback-v7.sql.

-- ------------------------------------------------------------------ Tender details on the project (new columns only)
alter table projects add column if not exists te_number text;
alter table projects add column if not exists pe_number text;
alter table projects add column if not exists client text;
alter table projects add column if not exists location text;
alter table projects add column if not exists expected_value_m numeric;
alter table projects add column if not exists notified_on date;
alter table projects add column if not exists award_on date;
alter table projects add column if not exists contract_signed_on date;
alter table projects add column if not exists cancelled_on date;
alter table projects add column if not exists cancel_reason text;
alter table projects add column if not exists registered_by uuid references profiles(id);
alter table projects add column if not exists registered_at timestamptz;

-- PE-5, pe 005 and PE-005 are the same number
create or replace function pt_pe_canon(t text) returns text language sql immutable as $$
  select case when t is null or btrim(t) = '' then null
              when upper(btrim(t)) ~ '^PE\s*-?\s*[0-9]{1,6}$' then
                'PE-' || (select case when length(d) >= 3 then d else lpad(d, 3, '0') end
                            from (select coalesce(nullif(ltrim(substring(upper(btrim(t)) from '([0-9]+)$'), '0'), ''), '0') as d) x)
              else upper(btrim(t)) end $$;
create or replace function pt_pe_seq(t text) returns int language sql immutable as $$
  select case when pt_pe_canon(t) ~ '^PE-[0-9]+$' then substring(pt_pe_canon(t) from 4)::int end $$;

create unique index if not exists projects_te_uq on projects (upper(btrim(te_number))) where te_number is not null;
-- the database itself refuses a second live project with the same PE number
do $$ begin
  create unique index if not exists projects_pe_live_uq on projects (pt_pe_canon(coalesce(pe_number, id))) where status is distinct from 'Cancelled';
exception when unique_violation then
  raise notice 'Two existing projects already share a project code, so the PE uniqueness index was not created. ProTrackAI still checks every new PE number.';
end $$;

-- ------------------------------------------------------------------ designations: Head of Planning and Cost Control, costing coordinator
create table if not exists pcc_designations (
  user_id uuid not null references profiles(id) on delete cascade,
  designation text not null check (designation in ('head','coordinator')),
  granted_by uuid references profiles(id), granted_at timestamptz not null default now(),
  primary key (user_id, designation));
alter table pcc_designations enable row level security;
drop policy if exists pccd_read on pcc_designations;
create policy pccd_read on pcc_designations for select using (auth.uid() is not null);
-- no write policies: only pcc_designate below writes

-- ------------------------------------------------------------------ register history (append-only)
create table if not exists register_audit (
  id bigserial primary key,
  project_id text not null references projects(id) on delete cascade,
  te_number text, pe_number text,
  action text not null, note text, detail jsonb,
  by_user uuid references profiles(id), by_name text, by_role text,
  at_time timestamptz not null default now());
alter table register_audit enable row level security;
drop policy if exists ra_read on register_audit;
create policy ra_read on register_audit for select using (can_see(project_id));
drop trigger if exists trg_ra_append on register_audit;
create trigger trg_ra_append before update or delete on register_audit for each row execute function pt_append_only();
drop trigger if exists trg_ra_truncate on register_audit;
create trigger trg_ra_truncate before truncate on register_audit execute function pt_no_truncate();
create index if not exists ra_proj on register_audit (project_id, id);
create index if not exists ra_pe on register_audit (pe_number, action);

-- Browsers cannot set the Tender fields, the PE number or the Cancelled status directly; tender_act does.
create or replace function pt_proj_guard() returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      if new.te_number is not null or new.pe_number is not null or new.status = 'Cancelled' or new.cancelled_on is not null then
        raise exception 'Tender details, PE numbers and cancellations are recorded in the Tender register' using errcode = '42501'; end if;
    elsif new.te_number is distinct from old.te_number or new.pe_number is distinct from old.pe_number
       or new.cancelled_on is distinct from old.cancelled_on or new.cancel_reason is distinct from old.cancel_reason
       or coalesce(new.status = 'Cancelled', false) <> coalesce(old.status = 'Cancelled', false) then
      raise exception 'Tender details, PE numbers and cancellations are recorded in the Tender register' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_proj_guard on projects;
create trigger trg_proj_guard before insert or update on projects for each row execute function pt_proj_guard();

-- ------------------------------------------------------------------ helpers
create or replace function pt_is_head(u uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) is not null and exists (select 1 from pcc_designations where user_id = u and designation = 'head'), false) $$;
create or replace function pt_is_coord(u uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) is not null and exists (select 1 from pcc_designations where user_id = u and designation = 'coordinator'), false) $$;
create or replace function pt_can_register(u uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) = 'sa' or pt_is_head(u) or pt_is_coord(u), false) $$;

-- the live project holding a PE number, if any
create or replace function pt_pe_holder(pe text, except_pid text) returns text language sql stable security definer set search_path = public as $$
  select id from projects where pt_pe_canon(coalesce(pe_number, id)) = pt_pe_canon(pe) and status is distinct from 'Cancelled'
     and id is distinct from except_pid order by id limit 1 $$;

-- The proposal: the longest-released free number first, otherwise the next in sequence
create or replace function pt_pe_propose() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare nxt int; rel jsonb;
begin
  select coalesce(max(n), 0) + 1 into nxt from (
    select pt_pe_seq(id) n from projects union all select pt_pe_seq(pe_number) from projects
    union all select pt_pe_seq(pe_number) from register_audit) x;
  select coalesce(jsonb_agg(jsonb_build_object('pe', pe, 'te', te, 'project', pid, 'at', at) order by at), '[]'::jsonb) into rel from (
    select distinct on (pt_pe_canon(a.pe_number)) pt_pe_canon(a.pe_number) pe, a.te_number te, a.project_id pid, a.at_time at
      from register_audit a where a.action = 'PE released' and pt_pe_seq(a.pe_number) is not null
     order by pt_pe_canon(a.pe_number), a.at_time desc) r
   where pt_pe_holder(pe, null) is null;
  return jsonb_build_object('proposed', coalesce(rel -> 0 ->> 'pe', pt_pe_canon('PE-' || nxt)), 'next', pt_pe_canon('PE-' || nxt), 'released', rel);
end $$;

create or replace function pt_reg_log(pid text, a text, note text, detail jsonb, pe text default null) returns void
language sql security definer set search_path = public as $$
  insert into register_audit (project_id, te_number, pe_number, action, note, detail, by_user, by_name, by_role)
  select id, te_number, coalesce(pe, pt_pe_canon(coalesce(pe_number, id))), a, note, detail, auth.uid(), name_of(auth.uid()), role_of(auth.uid())
    from projects where id = pid $$;

-- ------------------------------------------------------------------ stage definitions: stages 1 to 5 follow the Tender-to-SAP process
create or replace function pt_lc_dept(n int) returns text language sql immutable as $$
  select (array['Tendering','Planning and Cost Control','Planning and Cost Control','Tendering and Planning','Planning and Cost Control','Planning','Projects and site',
                'Procurement','Cost Control','Contracts and commercial','Planning and project management','Commercial and projects'])[n] $$;

create or replace function pt_lc_template(n int) returns jsonb language sql immutable as $$
  select case n
  when 1 then '[{"k":"te","label":"TE number, project name, region, client and location recorded from the Tender L1 list","req":true},{"k":"value","label":"Expected project value recorded","req":true}]'
  when 2 then '[{"k":"number","label":"PE number allocated against the TE number","req":true},{"k":"informed","label":"Tender department informed of the PE number","req":false}]'
  when 3 then '[{"k":"loa","label":"Notice of award received from the client","req":true},{"k":"wbs","label":"Higher-level WBS created in SAP","req":true},{"k":"fwbs","label":"Finance WBS sent to Tender for the advance bank guarantee charges","req":true},{"k":"sapact","label":"SAP team activated only the finance WBS for actual cost","req":true},{"k":"contract","label":"Contract signed","req":true}]'
  when 4 then '[{"k":"kickoff","label":"Kick-off meeting held by Tender","req":true},{"k":"docs","label":"Tender documents handed over to Planning","req":true},{"k":"costfile","label":"Costing file with detailed breakup handed over","req":true},{"k":"minutes","label":"Kick-off meeting minutes","req":false}]'
  when 5 then '[{"k":"site","label":"Site management breakup checked","req":true},{"k":"install","label":"Installation breakup checked","req":true},{"k":"mech","label":"Mechanical breakup checked","req":true},{"k":"civil","label":"Civil breakup checked","req":true},{"k":"missing","label":"Missing items received from Tender (if any were missing)","req":false},{"k":"brief","label":"Project brief prepared","req":true},{"k":"cashflow","label":"Cash flow prepared","req":true},{"k":"finance","label":"Project brief, cash flow and signed contract copy sent to Finance / Treasury","req":true},{"k":"sapupload","label":"Costing uploaded to SAP with the standard template","req":true}]'
  when 6 then '[{"k":"prepared","label":"Baseline programme prepared and loaded","req":true},{"k":"dcma","label":"Schedule quality check reviewed","req":false},{"k":"costing","label":"Costing file applied","req":true},{"k":"submitted","label":"Baseline submitted to the client","req":true},{"k":"approved","label":"Client approval of the baseline received","req":true}]'
  when 7 then '[{"k":"dpr","label":"Daily reports flowing","req":true},{"k":"weekly","label":"Weekly progress updates current","req":true},{"k":"lookahead","label":"Look-ahead programme issued","req":false}]'
  when 8 then '[{"k":"pos","label":"Subcontract purchase orders recorded","req":true},{"k":"longlead","label":"Long-lead items tracked","req":true},{"k":"materials","label":"Material tracking in place","req":false}]'
  when 9 then '[{"k":"budget","label":"Budget loaded from the costing file","req":true},{"k":"invoices","label":"Invoice register current","req":true},{"k":"forecast","label":"Forecast at completion reviewed","req":true}]'
  when 10 then '[{"k":"register","label":"Variation register maintained","req":true},{"k":"claims","label":"Claims and extension of time submitted where due","req":false},{"k":"approvals","label":"Variation approvals recorded","req":true}]'
  when 11 then '[{"k":"report","label":"Monthly report issued","req":true},{"k":"review","label":"Management review held","req":true},{"k":"actions","label":"Actions from the review assigned","req":false}]'
  when 12 then '[{"k":"tcc","label":"Technical completion (TCC) achieved","req":true},{"k":"pac","label":"Provisional acceptance (PAC) achieved","req":true},{"k":"final","label":"Final account agreed","req":true},{"k":"handover","label":"Handover to operations","req":true},{"k":"lessons","label":"Lessons learned recorded","req":false}]'
  end::jsonb $$;

-- who may approve, return, skip and assign owners: stages 1 to 5 the Head of Planning and Cost Control or a
-- super admin; stages 6 to 12 as before (a project manager on the project or a super admin)
create or replace function pt_lc_boss(u uuid, p text, n int) returns boolean language sql stable security definer set search_path = public as $$
  select case when n <= 5 then coalesce(role_of(u) = 'sa' or pt_is_head(u), false) else coalesce(pt_lc_approver(u, p), false) end $$;
create or replace function pt_lc_boss_text(n int) returns text language sql immutable as $$
  select case when n <= 5 then 'the Head of Planning and Cost Control or a super admin' else 'the project manager or a super admin' end $$;

-- the stage row, created from the template the first time anyone touches it
create or replace function pt_lc_row(pid text, n int) returns lifecycle_stages language plpgsql security definer set search_path = public as $$
declare s lifecycle_stages;
begin
  select * into s from lifecycle_stages where project_id = pid and stage_no = n for update;
  if s.project_id is null then
    insert into lifecycle_stages (project_id, stage_no, department, deliverables)
    values (pid, n, pt_lc_dept(n), (select jsonb_agg(x || '{"done":false}'::jsonb) from jsonb_array_elements(pt_lc_template(n)) x))
    returning * into s;
  end if;
  return s;
end $$;

-- ------------------------------------------------------------------ the one way to change a stage (v7)
create or replace function lifecycle_act(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r text := role_of(auth.uid()); pid text := p ->> 'project_id'; n int := pt_num(p ->> 'stage_no');
        a text := p ->> 'action'; note text := nullif(btrim(coalesce(p ->> 'note', '')), ''); s lifecycle_stages;
        f jsonb := coalesce(p -> 'fields', '{}'::jsonb); boss boolean; editor boolean; t jsonb; missing text; newowner uuid; changes text[] := '{}';
        who text;
begin
  if me is null or r is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if pid is null or not user_sees(me, pid) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
  if n is null or n < 1 or n > 12 or n <> trunc(n) then raise exception 'Unknown lifecycle stage'; end if;
  if a is null or a not in ('update','start','submit','approve','return','na','reopen') then raise exception 'Unknown action %', a; end if;
  if (select status from projects where id = pid) = 'Cancelled' then
    raise exception 'This project was cancelled; a super admin must reinstate it in the Tender register before its stages change' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtext('protrack:lc:' || pid || ':' || n));

  s := pt_lc_row(pid, n);
  boss := pt_lc_boss(me, pid, n);
  who := pt_lc_boss_text(n);
  editor := coalesce(boss, false) or coalesce(s.owner = me, false);   -- no owner yet means "not the owner", never "unknown"

  if a = 'update' then
    if not editor then raise exception 'Only the stage owner, % can change this stage', who using errcode = '42501'; end if;
    if s.status in ('Complete','Not applicable') then raise exception 'This stage is %; a super admin must reopen it first', lower(s.status) using errcode = '42501'; end if;
    if f ? 'owner' then
      if not boss then raise exception 'Only % can assign the owner', who using errcode = '42501'; end if;
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
    if not editor then raise exception 'Only the stage owner, % can start this stage', who using errcode = '42501'; end if;
    if s.status <> 'Not started' then raise exception 'This stage is already %', lower(s.status); end if;
    s.status := 'In progress';
  elsif a = 'submit' then
    if not editor then raise exception 'Only the stage owner, % can submit this stage', who using errcode = '42501'; end if;
    if s.status not in ('Not started','In progress') then raise exception 'Only a stage in progress can be submitted; this one is %', lower(s.status); end if;
    if s.owner is null then raise exception 'Assign an owner before submitting'; end if;
    select string_agg(x ->> 'label', '; ') into missing from jsonb_array_elements(s.deliverables) x
     where coalesce((x ->> 'req')::boolean, false) and not coalesce((x ->> 'done')::boolean, false);
    if missing is not null then raise exception 'Required deliverables are not done: %', missing; end if;
    s.status := 'Awaiting approval'; s.submitted_by := me; s.submitted_at := now();
  elsif a = 'approve' then
    if not boss then raise exception 'Only % can approve stage %', who, n using errcode = '42501'; end if;
    if s.status <> 'Awaiting approval' then raise exception 'Only a stage awaiting approval can be approved'; end if;
    if s.submitted_by = me then raise exception 'You submitted this stage, so someone else must approve it' using errcode = '42501'; end if;
    s.status := 'Complete'; s.approved_by := me; s.approved_at := now();
  elsif a = 'return' then
    if not boss then raise exception 'Only % can return stage %', who, n using errcode = '42501'; end if;
    if s.status <> 'Awaiting approval' then raise exception 'Only a stage awaiting approval can be returned'; end if;
    if note is null then raise exception 'Add a comment saying what to fix'; end if;
    s.status := 'In progress'; s.submitted_by := null; s.submitted_at := null;
  elsif a = 'na' then
    if not boss then raise exception 'Only % can mark stage % not applicable', who, n using errcode = '42501'; end if;
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

-- ------------------------------------------------------------------ Tender register: register, update, change PE, cancel, reinstate
-- p: {action, project_id, note, fields:{te_number, name, short, region, sector, client, location, expected_value_m,
--     notified_on, award_on, contract_signed_on, pe_number}}
create or replace function tender_act(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r text := role_of(auth.uid()); a text := p ->> 'action';
        note text := nullif(btrim(coalesce(p ->> 'note', '')), ''); f jsonb := coalesce(p -> 'fields', '{}'::jsonb);
        pid text := nullif(btrim(coalesce(p ->> 'project_id', '')), ''); pr projects; te text; pe text; holder text; prop jsonb;
        newid text; k int := 1; changes text[] := '{}'; prev text; oldsigned date; s4 lifecycle_stages; reused boolean;
begin
  if me is null or r is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if a is null or a not in ('register','update','change_pe','cancel','reinstate') then raise exception 'Unknown action %', a; end if;
  perform pg_advisory_xact_lock(hashtext('protrack:pe'));
  if pt_bad_num(f ->> 'expected_value_m') or pt_num(f ->> 'expected_value_m') < 0 then
    raise exception 'The expected value must be a number of SAR millions, zero or more'; end if;
  if pt_bad_date(f ->> 'notified_on') then raise exception 'The notification date is not a valid date'; end if;
  if pt_bad_date(f ->> 'award_on') then raise exception 'The award date is not a valid date'; end if;
  if pt_bad_date(f ->> 'contract_signed_on') then raise exception 'The contract signing date is not a valid date'; end if;
  if pt_date(f ->> 'award_on') > current_date + 1 then raise exception 'The award date cannot be in the future'; end if;
  if pt_date(f ->> 'contract_signed_on') > current_date + 1 then raise exception 'The contract signing date cannot be in the future'; end if;
  if nullif(f ->> 'region', '') is not null and not exists (select 1 from regions where id = f ->> 'region') then raise exception 'Unknown region'; end if;
  if nullif(f ->> 'sector', '') is not null and not exists (select 1 from sectors where id = f ->> 'sector') then raise exception 'Unknown sector'; end if;

  if a = 'register' then
    if not pt_can_register(me) then
      raise exception 'Only the costing coordinator, the Head of Planning and Cost Control or a super admin can register a Tender L1 project' using errcode = '42501'; end if;
    te := upper(btrim(coalesce(f ->> 'te_number', '')));
    if te = '' then raise exception 'Enter the TE number from the Tender list'; end if;
    if length(te) > 30 then raise exception 'The TE number is too long'; end if;
    select coalesce(pe_number, id) into holder from projects where upper(btrim(te_number)) = te limit 1;
    if holder is not null then raise exception 'TE number % is already registered, as %', te, holder; end if;
    if nullif(btrim(coalesce(f ->> 'name', '')), '') is null then raise exception 'Enter the project name'; end if;
    prop := pt_pe_propose();
    if r = 'sa' and nullif(btrim(coalesce(f ->> 'pe_number', '')), '') is not null then
      pe := pt_pe_canon(f ->> 'pe_number');
    else
      pe := prop ->> 'proposed';      -- everyone else gets the proposal made now, under the lock
    end if;
    if pe !~ '^PE-[0-9]{3,6}$' then raise exception 'A PE number looks like PE-123'; end if;
    holder := pt_pe_holder(pe, null);
    if holder is not null then raise exception '% is already given to a live project (%)', pe, holder; end if;
    reused := exists (select 1 from jsonb_array_elements(prop -> 'released') x where x ->> 'pe' = pe);
    newid := pe;
    while exists (select 1 from projects where id = newid) loop k := k + 1; newid := pe || '-R' || k; end loop;
    insert into projects (id, name, short, region, sector, status, te_number, pe_number, client, location, expected_value_m, notified_on,
                          award_on, contract_signed_on, registered_by, registered_at)
    values (newid, left(btrim(f ->> 'name'), 200), left(coalesce(nullif(btrim(f ->> 'short'), ''), btrim(f ->> 'name')), 22),
            nullif(f ->> 'region', ''), nullif(f ->> 'sector', ''), 'Pre-award', te, pe,
            left(nullif(btrim(f ->> 'client'), ''), 200), left(nullif(btrim(f ->> 'location'), ''), 200), pt_num(f ->> 'expected_value_m'),
            pt_date(f ->> 'notified_on'), null, null, me, now())
    returning * into pr;
    -- the person registering, the Heads of Planning and Cost Control and the costing coordinators can see it
    insert into project_access (user_id, project_id)
      select distinct x, newid from (select me as x union select user_id from pcc_designations) y
       where role_of(x) is not null and role_of(x) not in ('sa', 'exec')
    on conflict do nothing;
    -- a costing coordinator records stages 1 to 4 on Tender's behalf, so they own them from the start
    if pt_is_coord(me) and r <> 'sa' then
      for k in 1..4 loop
        perform pt_lc_row(newid, k);
        update lifecycle_stages set owner = me, updated_at = now() where project_id = newid and stage_no = k;
        insert into lifecycle_audit (project_id, stage_no, action, note, detail, by_user, by_name, by_role)
        values (newid, k, 'Updated', 'Owner set when the project was registered from the Tender list', jsonb_build_object('changes', jsonb_build_array('owner ' || name_of(me))), me, name_of(me), r);
      end loop;
    end if;
    perform pt_reg_log(newid, 'Registered', null, jsonb_build_object('te', te, 'name', pr.name, 'client', pr.client, 'location', pr.location,
                       'region', pr.region, 'expected_value_m', pr.expected_value_m, 'notified_on', pr.notified_on));
    perform pt_reg_log(newid, 'PE allocated', case when reused then 'Reallocated: released earlier by a cancelled project' end,
                       jsonb_build_object('pe', pe, 'proposed', prop ->> 'proposed', 'chosen_by_super_admin', pe is distinct from prop ->> 'proposed', 'reused', reused), pe);
    return to_jsonb(pr) || jsonb_build_object('proposed', prop ->> 'proposed');
  end if;

  select * into pr from projects where id = pid for update;
  if pr.id is null or not user_sees(me, pid) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;

  if a = 'update' then
    if not pt_can_register(me) then
      raise exception 'Only the costing coordinator, the Head of Planning and Cost Control or a super admin can change the Tender details' using errcode = '42501'; end if;
    if pr.status = 'Cancelled' then raise exception 'This project was cancelled; a super admin must reinstate it first' using errcode = '42501'; end if;
    if f ? 'te_number' then
      te := nullif(upper(btrim(coalesce(f ->> 'te_number', ''))), '');
      if te is distinct from upper(btrim(pr.te_number)) then
        if pr.te_number is not null and r <> 'sa' then raise exception 'Only a super admin can change a TE number once it is recorded' using errcode = '42501'; end if;
        if te is null then raise exception 'Enter the TE number'; end if;
        if length(te) > 30 then raise exception 'The TE number is too long'; end if;
        if exists (select 1 from projects where upper(btrim(te_number)) = te and id <> pid) then raise exception 'TE number % is already registered', te; end if;
        changes := changes || ('TE ' || coalesce(pr.te_number, 'none') || ' to ' || te); pr.te_number := te;
      end if;
    end if;
    if f ? 'name' then
      if nullif(btrim(coalesce(f ->> 'name', '')), '') is null then raise exception 'The project name cannot be empty'; end if;
      if btrim(f ->> 'name') is distinct from pr.name then changes := changes || 'name'::text; pr.name := left(btrim(f ->> 'name'), 200); end if;
    end if;
    if f ? 'client' and nullif(btrim(coalesce(f ->> 'client', '')), '') is distinct from pr.client then changes := changes || 'client'::text; pr.client := left(nullif(btrim(f ->> 'client'), ''), 200); end if;
    if f ? 'location' and nullif(btrim(coalesce(f ->> 'location', '')), '') is distinct from pr.location then changes := changes || 'location'::text; pr.location := left(nullif(btrim(f ->> 'location'), ''), 200); end if;
    if f ? 'region' and nullif(f ->> 'region', '') is distinct from pr.region then changes := changes || 'region'::text; pr.region := nullif(f ->> 'region', ''); end if;
    if f ? 'expected_value_m' and pt_num(f ->> 'expected_value_m') is distinct from pr.expected_value_m then changes := changes || ('expected value ' || coalesce(f ->> 'expected_value_m', 'none')); pr.expected_value_m := pt_num(f ->> 'expected_value_m'); end if;
    if f ? 'notified_on' and pt_date(f ->> 'notified_on') is distinct from pr.notified_on then changes := changes || ('notified ' || coalesce(f ->> 'notified_on', 'none')); pr.notified_on := pt_date(f ->> 'notified_on'); end if;
    if f ? 'award_on' and pt_date(f ->> 'award_on') is distinct from pr.award_on then
      changes := changes || ('award ' || coalesce(f ->> 'award_on', 'none')); pr.award_on := pt_date(f ->> 'award_on');
      if pr.award_on is not null and pr.status = 'Pre-award' then pr.status := 'Active'; changes := changes || 'status Active'::text; end if;
    end if;
    oldsigned := pr.contract_signed_on;
    if f ? 'contract_signed_on' and pt_date(f ->> 'contract_signed_on') is distinct from pr.contract_signed_on then
      changes := changes || ('contract signed ' || coalesce(f ->> 'contract_signed_on', 'none')); pr.contract_signed_on := pt_date(f ->> 'contract_signed_on');
    end if;
    if array_length(changes, 1) is null then return to_jsonb(pr); end if;
    update projects set te_number = pr.te_number, name = pr.name, client = pr.client, location = pr.location, region = pr.region,
           expected_value_m = pr.expected_value_m, notified_on = pr.notified_on, award_on = pr.award_on, contract_signed_on = pr.contract_signed_on,
           status = pr.status where id = pid returning * into pr;
    perform pt_reg_log(pid, 'Details updated', null, jsonb_build_object('changes', to_jsonb(changes)));
    -- stage 4 (kick-off and handover) is due 7 days after contract signing, unless someone set another date
    if pr.contract_signed_on is not null and pr.contract_signed_on is distinct from oldsigned then
      s4 := pt_lc_row(pid, 4);
      if s4.status in ('Not started','In progress') and (s4.due_date is null or s4.due_date = oldsigned + 7) and s4.due_date is distinct from pr.contract_signed_on + 7 then
        update lifecycle_stages set due_date = pr.contract_signed_on + 7, updated_at = now() where project_id = pid and stage_no = 4;
        insert into lifecycle_audit (project_id, stage_no, action, note, detail, by_user, by_name, by_role)
        values (pid, 4, 'Updated', 'Due 7 days after contract signing', jsonb_build_object('changes', jsonb_build_array('due ' || to_char(pr.contract_signed_on + 7, 'YYYY-MM-DD'))), me, name_of(me), r);
      end if;
    end if;
    return to_jsonb(pr);

  elsif a = 'change_pe' then
    if r <> 'sa' then raise exception 'Only a super admin can change a PE number' using errcode = '42501'; end if;
    if pr.status = 'Cancelled' then raise exception 'Reinstate the project before changing its PE number'; end if;
    if note is null then raise exception 'Add a comment saying why the PE number changes'; end if;
    pe := pt_pe_canon(f ->> 'pe_number');
    if pe is null or pe !~ '^PE-[0-9]{3,6}$' then raise exception 'A PE number looks like PE-123'; end if;
    prev := pt_pe_canon(coalesce(pr.pe_number, pr.id));
    if pe = prev then raise exception 'That is already this project''s PE number'; end if;
    holder := pt_pe_holder(pe, pid);
    if holder is not null then raise exception '% is already given to a live project (%)', pe, holder; end if;
    update projects set pe_number = pe where id = pid returning * into pr;
    perform pt_reg_log(pid, 'PE changed', note, jsonb_build_object('from', prev, 'to', pe), pe);
    if pt_pe_seq(prev) is not null then perform pt_reg_log(pid, 'PE released', 'Released when the PE number was changed', jsonb_build_object('pe', prev), prev); end if;
    return to_jsonb(pr);

  elsif a = 'cancel' then
    if not (r = 'sa' or pt_is_head(me)) then
      raise exception 'Only the Head of Planning and Cost Control or a super admin can cancel a project' using errcode = '42501'; end if;
    if pr.status = 'Cancelled' then raise exception 'This project is already cancelled'; end if;
    if note is null then raise exception 'Add a comment saying why, for example cancelled by the client after L1'; end if;
    prev := pr.status;
    update projects set status = 'Cancelled', cancelled_on = current_date, cancel_reason = left(note, 500) where id = pid returning * into pr;
    perform pt_reg_log(pid, 'Cancelled', note, jsonb_build_object('previous_status', prev));
    if pt_pe_seq(coalesce(pr.pe_number, pr.id)) is not null then
      perform pt_reg_log(pid, 'PE released', 'Released when the project was cancelled; it can go to another L1 project', jsonb_build_object('pe', pt_pe_canon(coalesce(pr.pe_number, pr.id))));
    end if;
    return to_jsonb(pr);

  else -- reinstate
    if r <> 'sa' then raise exception 'Only a super admin can reinstate a cancelled project' using errcode = '42501'; end if;
    if pr.status is distinct from 'Cancelled' then raise exception 'Only a cancelled project can be reinstated'; end if;
    if note is null then raise exception 'Add a comment saying why the project is reinstated'; end if;
    pe := coalesce(pt_pe_canon(nullif(btrim(coalesce(f ->> 'pe_number', '')), '')), pt_pe_canon(coalesce(pr.pe_number, pr.id)));
    if pe <> pt_pe_canon(coalesce(pr.pe_number, pr.id)) and pe !~ '^PE-[0-9]{3,6}$' then raise exception 'A PE number looks like PE-123'; end if;
    holder := pt_pe_holder(pe, pid);
    if holder is not null then
      raise exception '% now belongs to another live project (%). Give this project a new PE number to reinstate it', pe, holder; end if;
    select coalesce(nullif(detail ->> 'previous_status', 'Cancelled'), 'Active') into prev from register_audit
     where project_id = pid and action = 'Cancelled' order by id desc limit 1;
    update projects set status = coalesce(prev, 'Active'), cancelled_on = null, cancel_reason = null,
           pe_number = case when pe = pt_pe_canon(coalesce(pe_number, id)) then pe_number else pe end
     where id = pid returning * into pr;
    perform pt_reg_log(pid, 'Reinstated', note, jsonb_build_object('status', pr.status));
    perform pt_reg_log(pid, 'PE allocated', 'Allocated again when the project was reinstated', jsonb_build_object('pe', pe, 'reinstated', true), pe);
    return to_jsonb(pr);
  end if;
end $$;

-- what the register form shows: the PE number ProTrackAI would give now
create or replace function pe_proposal() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not pt_can_register(auth.uid()) then raise exception 'Only the costing coordinator, the Head of Planning and Cost Control or a super admin can register projects' using errcode = '42501'; end if;
  return pt_pe_propose();
end $$;

-- super admin: give or remove a designation. p: {user_id, designation: head|coordinator, on: true|false}
create or replace function pcc_designate(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); u uuid; d text := p ->> 'designation'; o boolean := coalesce((p ->> 'on')::boolean, false);
        label text;
begin
  if role_of(me) is distinct from 'sa' then raise exception 'Only a super admin can change designations' using errcode = '42501'; end if;
  if d is null or d not in ('head','coordinator') then raise exception 'Unknown designation'; end if;
  u := nullif(p ->> 'user_id', '')::uuid;
  if u is null or role_of(u) is null then raise exception 'Choose an active person'; end if;
  label := case d when 'head' then 'Head of Planning and Cost Control' else 'Costing coordinator' end;
  if o then
    insert into pcc_designations (user_id, designation, granted_by) values (u, d, me) on conflict do nothing;
    if found then insert into change_log (project_id, text, by_user) values (null, label || ' designation given to ' || name_of(u), me); end if;
  else
    delete from pcc_designations where user_id = u and designation = d;
    if found then insert into change_log (project_id, text, by_user) values (null, label || ' designation removed from ' || name_of(u), me); end if;
  end if;
  return coalesce((select jsonb_agg(designation order by designation) from pcc_designations where user_id = u), '[]'::jsonb);
end $$;

-- ------------------------------------------------------------------ one-time: stages already started get the new checklists
-- Not started or In progress stages 1 to 5 take the new items. Ticks already given are kept (same item, same tick);
-- items from the old checklist that a stage in progress had stay listed as optional. Awaiting approval, complete
-- and not-applicable stages are not touched. Every change is written to the stage history.
do $$
declare s record; tpl jsonb; merged jsonb; added text[]; legacy text[];
begin
  for s in select * from lifecycle_stages ls where ls.stage_no between 1 and 5 and ls.status in ('Not started','In progress')
              and not exists (select 1 from lifecycle_audit a where a.project_id = ls.project_id and a.stage_no = ls.stage_no and a.action = 'Checklist updated') loop
    tpl := pt_lc_template(s.stage_no);
    select coalesce(jsonb_agg(coalesce(
             (select o || jsonb_build_object('label', t ->> 'label', 'req', (t ->> 'req')::boolean) from jsonb_array_elements(s.deliverables) o where o ->> 'k' = t ->> 'k' limit 1),
             t || '{"done":false}'::jsonb) order by ord), '[]'::jsonb)
      into merged from jsonb_array_elements(tpl) with ordinality as x(t, ord);
    added := array(select t ->> 'label' from jsonb_array_elements(tpl) t where not exists (select 1 from jsonb_array_elements(s.deliverables) o where o ->> 'k' = t ->> 'k'));
    legacy := '{}';
    if s.status = 'In progress' then
      legacy := array(select o ->> 'label' from jsonb_array_elements(s.deliverables) o where not exists (select 1 from jsonb_array_elements(tpl) t where t ->> 'k' = o ->> 'k'));
      merged := merged || coalesce((select jsonb_agg(o || '{"req":false,"legacy":true}'::jsonb) from jsonb_array_elements(s.deliverables) o
                                     where not exists (select 1 from jsonb_array_elements(tpl) t where t ->> 'k' = o ->> 'k')), '[]'::jsonb);
    end if;
    continue when merged = s.deliverables;   -- already on the new checklist
    update lifecycle_stages set deliverables = merged, department = pt_lc_dept(s.stage_no), updated_at = now()
     where project_id = s.project_id and stage_no = s.stage_no;
    insert into lifecycle_audit (project_id, stage_no, action, note, detail, by_user, by_name, by_role)
    values (s.project_id, s.stage_no, 'Checklist updated', 'Stages 1 to 5 now follow the Tender-to-SAP process (ProTrackAI v2.8). Ticks already given are kept.',
            jsonb_build_object('added', to_jsonb(added), 'now_optional', to_jsonb(legacy), 'department', pt_lc_dept(s.stage_no)), null, 'ProTrackAI v2.8 update', 'system');
  end loop;
end $$;

revoke execute on function pt_pe_canon(text), pt_pe_seq(text), pt_proj_guard(), pt_is_head(uuid), pt_is_coord(uuid), pt_can_register(uuid),
  pt_pe_holder(text, text), pt_pe_propose(), pt_reg_log(text, text, text, jsonb, text), pt_lc_dept(int), pt_lc_template(int),
  pt_lc_boss(uuid, text, int), pt_lc_boss_text(int), pt_lc_row(text, int), lifecycle_act(jsonb), tender_act(jsonb), pe_proposal(), pcc_designate(jsonb)
  from public, anon, authenticated;
grant execute on function lifecycle_act(jsonb), tender_act(jsonb), pe_proposal(), pcc_designate(jsonb) to authenticated;
-- the PE index and the guard trigger call these as the signed-in person
grant execute on function pt_pe_canon(text), pt_pe_seq(text) to authenticated;
