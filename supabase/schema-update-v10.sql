-- ProTrack schema update v10 (ProTrackAI v3.1: issue register, released summary)
-- * Issue register for every project, with the columns of the company issue log: owner and sub-owner, issue type,
--   start date, description, impact, action taken and required, client and internal priority, action by, planned and
--   forecast target, status and closure, remarks, schedule and cost impact. Planning and costing engineers keep the
--   issues of their own projects (one by one or by uploading the Excel log); the Head of Planning and Cost Control
--   and super admins can keep any project's and mark issues reviewed. Every change is kept (append-only history).
-- * When a progress release is approved, the project's open issues are saved with it, so the released report shows
--   the issues as they stood. Released versions stay frozen.
-- Run AFTER schema-update-v9.sql. Additive and safe to run more than once. Undo: schema-rollback-v10.sql.

alter table import_batches drop constraint if exists import_batches_kind_check;
alter table import_batches add constraint import_batches_kind_check
  check (kind in ('invoices','costing','baseline','update','migration','restore','volog','supplements','issues'));

create table if not exists issues (
  id uuid primary key default uuid_generate_v4(),
  project_id text not null references projects(id) on delete cascade,
  issue_no text not null,
  data_date date,
  owner text, sub_owner text, issue_type text, started_on date,
  description text not null,
  impact text check (impact in ('Extremely High','High','Medium','Low')),
  action_taken text, action_required text,
  priority_client text check (priority_client in ('A','B','C')),
  priority_internal text check (priority_internal in ('A','B','C')),
  action_by text, planned_target date, forecast_target date,
  status text not null default 'Open' check (status in ('Open','Closed')),
  closed_on date, remarks text, schedule_impact text, cost_impact text,
  reviewed_by uuid references profiles(id), reviewed_at timestamptz, review_note text,
  created_by uuid references profiles(id), created_at timestamptz not null default now(),
  updated_by uuid references profiles(id), updated_at timestamptz not null default now(),
  unique (project_id, issue_no));
create index if not exists issues_proj on issues (project_id, status);
create table if not exists issue_audit (
  id bigserial primary key,
  issue_id uuid not null references issues(id) on delete cascade,
  project_id text not null references projects(id) on delete cascade,
  action text not null, note text, detail jsonb,
  by_user uuid references profiles(id), by_name text, by_role text,
  at_time timestamptz not null default now());
alter table issues enable row level security;
alter table issue_audit enable row level security;
drop policy if exists is_read on issues;
create policy is_read on issues for select using (can_see(project_id) and pt_money_ok());
drop policy if exists isa_read on issue_audit;
create policy isa_read on issue_audit for select using (can_see(project_id) and pt_money_ok());
drop trigger if exists trg_isa_append on issue_audit;
create trigger trg_isa_append before update or delete on issue_audit for each row execute function pt_append_only();
drop trigger if exists trg_isa_truncate on issue_audit;
create trigger trg_isa_truncate before truncate on issue_audit execute function pt_no_truncate();
-- no write policies: only issue_act and issue_import below write

alter table report_releases add column if not exists issues_snapshot jsonb not null default '[]'::jsonb;

-- who keeps a project's issues: its planning and costing engineers, the Head of Planning and Cost Control, super admins
create or replace function pt_issue_editor(u uuid, pid text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(user_sees(u, pid) and (role_of(u) in ('sa','plan','costing') or pt_is_head(u)), false) $$;
create or replace function pt_impact(t text) returns text language sql immutable as $$
  select case lower(btrim(coalesce(t, ''))) when 'extremely high' then 'Extremely High' when 'very high' then 'Extremely High' when 'high' then 'High'
              when 'medium' then 'Medium' when 'low' then 'Low' else null end $$;
create or replace function pt_prio(t text) returns text language sql immutable as $$
  select case when upper(btrim(coalesce(t, ''))) in ('A','B','C') then upper(btrim(t)) else null end $$;
create or replace function pt_issue_snapshot(pid text) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('no', issue_no, 'type', issue_type, 'owner', owner, 'sub_owner', sub_owner, 'description', left(description, 600),
           'impact', impact, 'action_required', left(action_required, 400), 'action_by', action_by, 'planned_target', planned_target, 'forecast_target', forecast_target,
           'priority_client', priority_client, 'priority_internal', priority_internal, 'started_on', started_on,
           'schedule_impact', left(schedule_impact, 200))
         order by case impact when 'Extremely High' then 0 when 'High' then 1 when 'Medium' then 2 else 3 end, started_on nulls last, issue_no), '[]'::jsonb)
    from issues where project_id = pid and status = 'Open' $$;
create or replace function pt_issue_log(iid uuid, a text, note text, detail jsonb) returns void language sql security definer set search_path = public as $$
  insert into issue_audit (issue_id, project_id, action, note, detail, by_user, by_name, by_role)
  select id, project_id, a, note, detail, auth.uid(), name_of(auth.uid()), role_of(auth.uid()) from issues where id = iid $$;

-- apply the editable fields of one issue; returns the list of fields that changed
create or replace function pt_issue_apply(iid uuid, f jsonb) returns text[] language plpgsql security definer set search_path = public as $$
declare i issues; ch text[] := '{}'; k text; v text;
begin
  select * into i from issues where id = iid for update;
  foreach k in array array['data_date','started_on','planned_target','forecast_target','closed_on'] loop
    if f ? k and pt_bad_date(f ->> k) then raise exception 'The % is not a valid date', replace(k, '_', ' '); end if;
  end loop;
  if f ? 'description' and nullif(btrim(coalesce(f ->> 'description', '')), '') is null then raise exception 'The issue description cannot be empty'; end if;
  if f ? 'impact' and nullif(btrim(coalesce(f ->> 'impact', '')), '') is not null and pt_impact(f ->> 'impact') is null then
    raise exception 'Impact must be Extremely High, High, Medium or Low'; end if;
  foreach k in array array['priority_client','priority_internal'] loop
    if f ? k and nullif(btrim(coalesce(f ->> k, '')), '') is not null and pt_prio(f ->> k) is null then raise exception 'Priority must be A, B or C'; end if;
  end loop;
  foreach k in array array['data_date','owner','sub_owner','issue_type','started_on','description','impact','action_taken','action_required','priority_client',
                           'priority_internal','action_by','planned_target','forecast_target','remarks','schedule_impact','cost_impact'] loop
    if f ? k then
      v := nullif(btrim(coalesce(f ->> k, '')), '');
      if k = 'impact' then v := pt_impact(v); elsif k like 'priority%' then v := pt_prio(v); end if;
      if (to_jsonb(i) ->> k) is distinct from (case when k in ('data_date','started_on','planned_target','forecast_target') then pt_date(v)::text else left(v, 4000) end) then ch := ch || k; end if;
    end if;
  end loop;
  if array_length(ch, 1) is null then return ch; end if;
  update issues set
    data_date = case when f ? 'data_date' then pt_date(f ->> 'data_date') else data_date end,
    owner = case when f ? 'owner' then left(nullif(btrim(f ->> 'owner'), ''), 200) else owner end,
    sub_owner = case when f ? 'sub_owner' then left(nullif(btrim(f ->> 'sub_owner'), ''), 200) else sub_owner end,
    issue_type = case when f ? 'issue_type' then left(nullif(btrim(f ->> 'issue_type'), ''), 120) else issue_type end,
    started_on = case when f ? 'started_on' then pt_date(f ->> 'started_on') else started_on end,
    description = case when f ? 'description' then left(btrim(f ->> 'description'), 4000) else description end,
    impact = case when f ? 'impact' then pt_impact(f ->> 'impact') else impact end,
    action_taken = case when f ? 'action_taken' then left(nullif(btrim(f ->> 'action_taken'), ''), 4000) else action_taken end,
    action_required = case when f ? 'action_required' then left(nullif(btrim(f ->> 'action_required'), ''), 4000) else action_required end,
    priority_client = case when f ? 'priority_client' then pt_prio(f ->> 'priority_client') else priority_client end,
    priority_internal = case when f ? 'priority_internal' then pt_prio(f ->> 'priority_internal') else priority_internal end,
    action_by = case when f ? 'action_by' then left(nullif(btrim(f ->> 'action_by'), ''), 200) else action_by end,
    planned_target = case when f ? 'planned_target' then pt_date(f ->> 'planned_target') else planned_target end,
    forecast_target = case when f ? 'forecast_target' then pt_date(f ->> 'forecast_target') else forecast_target end,
    remarks = case when f ? 'remarks' then left(nullif(btrim(f ->> 'remarks'), ''), 4000) else remarks end,
    schedule_impact = case when f ? 'schedule_impact' then left(nullif(btrim(f ->> 'schedule_impact'), ''), 1000) else schedule_impact end,
    cost_impact = case when f ? 'cost_impact' then left(nullif(btrim(f ->> 'cost_impact'), ''), 1000) else cost_impact end,
    updated_by = auth.uid(), updated_at = now()
   where id = iid;
  return ch;
end $$;

create or replace function pt_issue_new(pid text, descr text) returns uuid language plpgsql security definer set search_path = public as $$
declare n int; iid uuid;
begin
  perform pg_advisory_xact_lock(hashtext('protrack:issue:' || pid));
  select coalesce(max(nullif(regexp_replace(issue_no, '\D', '', 'g'), '')::int), 0) + 1 into n from issues where project_id = pid;
  insert into issues (project_id, issue_no, description, created_by, updated_by) values (pid, 'ISS-' || lpad(n::text, 3, '0'), left(btrim(descr), 4000), auth.uid(), auth.uid())
  returning id into iid;
  return iid;
end $$;

-- p: {action: save|close|reopen|review, id, project_id, fields:{...}, note, closed_on}
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

-- upload of the Excel issue log, all-or-nothing. A row matches an existing issue of the same project with the same
-- description (ignoring case and spaces); otherwise it is a new issue. Rows for projects the person does not keep are refused.
-- p: {file_name, hash, ack, rows:[{project_id, ...fields, status, closed_on}]}
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

-- released versions: the open issues are saved at approval; they never change afterwards
create or replace function pt_release_frozen() returns trigger language plpgsql as $$
begin
  if old.status in ('Released','Superseded') and (new.figures is distinct from old.figures or new.overrides is distinct from old.overrides
     or new.narrative is distinct from old.narrative or new.period is distinct from old.period or new.project_id is distinct from old.project_id
     or new.rev is distinct from old.rev or new.issues_snapshot is distinct from old.issues_snapshot or new.data_date is distinct from old.data_date or new.approved_by is distinct from old.approved_by
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

revoke execute on function pt_issue_editor(uuid, text), pt_impact(text), pt_prio(text), pt_issue_snapshot(text), pt_issue_log(uuid, text, text, jsonb),
  pt_issue_apply(uuid, jsonb), pt_issue_new(text, text), issue_act(jsonb), issue_import(jsonb), release_act(jsonb) from public, anon, authenticated;
grant execute on function issue_act(jsonb), issue_import(jsonb), release_act(jsonb) to authenticated;
