-- ProTrack schema update v24 (ProTrackAI v3.19): the delay events register (Claims & Variations).
-- 1. delay_events holds each project's delay events in the columns of the company "Delay Events Register" workbook:
--    claim contractual data (event no., name, identification, start date, status Ongoing / Closed, closing date,
--    supporting documents), notice of claim data (time bar in days, submission date, documents), schedule impact data
--    (description, affected baseline activities, schedule impact, data date, entitlement, liability) and cost impact
--    data (prolongation cost, variation orders omitted and added, concurrency, mitigation, owner). Ref. is the event's
--    order in the project. The claim duration, notice days used, notice days against the time bar and days to the
--    notice deadline are worked out by the app (dlyCalc), never stored.
--    Schedule impact and the three costs are "if calculated": a number, or a short note such as "Not calculated yet".
-- 2. Who sees: everyone who sees cost figures, on the projects in their access only (can_see and pt_money_ok), as the
--    app's canDlyView() and dlyVisible(). Who keeps: the new right "delay.keep" (planning engineers by default; the Head
--    of Planning and Cost Control by position; super admins always) on the projects in their access, as canDlyEdit().
-- 3. delay_act(p) adds, changes or deletes one event with the app's rules (delayActLocal). delay_import(p) takes the
--    rows of one uploaded workbook for one project: events are matched by Claim Event No., else by name; refused rows
--    need the acknowledgement; the same file twice in a row changes nothing; the upload is logged in import_batches.
-- 4. delay_audit keeps every change, and a deleted event's last content; it cannot be changed or emptied.
-- Needs schema-update-v16.sql (rights: pt_right, pt_rights, pt_screens, pt_right_default) and schema-update-v10.sql.
-- Additive: two tables, new functions; the right and the screen are added to the lists. Safe to run twice.
-- Undo: schema-rollback-v24.sql.

do $$ begin
  if to_regprocedure('public.pt_right(uuid,text,boolean)') is null or to_regprocedure('public.pt_right_default(text,text)') is null
     or to_regprocedure('public.pt_screens()') is null or to_regclass('public.issue_audit') is null then
    raise exception 'Run schema-update-v10.sql (STAGE-7-SETUP) and schema-update-v16.sql (STAGE-13-SETUP) first, then this update'; end if;
end $$;

-- ------------------------------------------------------------------ 1. the tables
create table if not exists delay_events (
  id uuid primary key default uuid_generate_v4(),
  project_id text not null references projects(id) on delete cascade,
  ref int not null,
  event_no text not null,
  name text not null,
  identification text,
  start_date date not null,
  status text not null default 'Ongoing' check (status in ('Ongoing','Closed')),
  closed_on date,
  support_docs text,
  time_bar int check (time_bar between 0 and 3650),
  notice_date date,
  notice_docs text,
  description text,
  affected text,
  sched_impact text,
  data_date date,
  entitlement text,
  liability text,
  prolong_cost text,
  vo_omit text,
  vo_add text,
  concurrency text,
  mitigation text,
  owner text,
  created_by uuid references profiles(id), created_at timestamptz not null default now(),
  updated_by uuid references profiles(id), updated_at timestamptz not null default now(),
  unique (project_id, ref),
  check ((status = 'Closed') = (closed_on is not null)));
create index if not exists delay_events_proj on delay_events (project_id, status);
create table if not exists delay_audit (
  id bigserial primary key,
  event_id uuid not null,   -- no foreign key: the history of a deleted event stays
  project_id text not null references projects(id) on delete cascade,
  event_no text,
  action text not null, note text, detail jsonb,
  by_user uuid references profiles(id), by_name text, by_role text,
  at_time timestamptz not null default now());
create index if not exists delay_audit_event on delay_audit (event_id);

alter table delay_events enable row level security;
alter table delay_audit enable row level security;
drop policy if exists de_read on delay_events;
create policy de_read on delay_events for select using (can_see(project_id) and pt_money_ok());
drop policy if exists dea_read on delay_audit;
create policy dea_read on delay_audit for select using (can_see(project_id) and pt_money_ok());
drop trigger if exists trg_dea_append on delay_audit;
create trigger trg_dea_append before update or delete on delay_audit for each row execute function pt_append_only();
drop trigger if exists trg_dea_truncate on delay_audit;
create trigger trg_dea_truncate before truncate on delay_audit execute function pt_no_truncate();
revoke all on delay_events, delay_audit from anon;
revoke insert, update, delete, truncate on delay_events, delay_audit from authenticated;
grant select on delay_events, delay_audit to authenticated;

-- uploads of the register are logged as kind 'delays' (the kind list is extended, whatever it holds today)
do $$
declare d text;
begin
  select pg_get_constraintdef(oid) into d from pg_constraint where conname = 'import_batches_kind_check' and conrelid = 'public.import_batches'::regclass;
  if d is not null and position('''delays''' in d) = 0 then
    if position(']' in d) = 0 then raise exception 'Unexpected import_batches_kind_check: %', d; end if;
    execute 'alter table import_batches drop constraint import_batches_kind_check';
    execute 'alter table import_batches add constraint import_batches_kind_check ' || regexp_replace(d, '\]', ', ''delays''::text]');
  end if;
end $$;

-- ------------------------------------------------------------------ 2. the right and the screen
-- "Keep the delay events register of their projects": planning engineers by default, the Head of Planning and Cost
-- Control by position (pt_right(me, 'delay.keep', pt_is_head(me))), super admins always. The screen 'dly' joins the
-- list of Settings -> Roles and rights -> Screens by role. Every right and screen already there is kept.
do $$
declare cur text[] := pt_rights(); scr text[] := pt_screens(); src text;
begin
  if not ('delay.keep' = any(cur)) then
    execute format('create or replace function pt_rights() returns text[] language sql immutable as $f$ select %L::text[] $f$', (cur || 'delay.keep'::text)::text);
  end if;
  if not ('dly' = any(scr)) then
    execute format('create or replace function pt_screens() returns text[] language sql immutable as $f$ select %L::text[] $f$', (scr || 'dly'::text)::text);
  end if;
  select prosrc into src from pg_proc where proname = 'pt_right_default' and pronamespace = 'public'::regnamespace and pronargs = 2;
  if position('delay.keep' in src) = 0 then
    if position('else false end' in src) = 0 then raise exception 'pt_right_default does not have the expected shape; add delay.keep by hand'; end if;
    src := regexp_replace(src, 'else false end', E'when ''delay.keep''              then base = ''plan''\n    else false end');
    execute format('create or replace function pt_right_default(base text, k text) returns boolean language sql immutable as $f$%s$f$', src);
  end if;
end $$;

-- ------------------------------------------------------------------ 3. the rules
create or replace function pt_dly_keeper(u uuid, pid text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(user_sees(u, pid) and pt_right(u, 'delay.keep', pt_is_head(u)), false) $$;
create or replace function pt_dly_status(t text) returns text language sql immutable as $$
  select case when lower(btrim(coalesce(t, ''))) ~ '^(ongoing|open|on-?going|in progress|active)' then 'Ongoing'
              when lower(btrim(coalesce(t, ''))) ~ '^(closed?|completed?|finished)' then 'Closed' end $$;
-- "Event 01" and "event 1" are the same number
create or replace function pt_dly_nokey(t text) returns text language sql immutable as $$
  select regexp_replace(lower(regexp_replace(btrim(coalesce(t, '')), '\s+', ' ', 'g')), '(^|[^0-9])0+([0-9])', '\1\2', 'g') $$;
create or replace function pt_dly_num(t text) returns numeric language sql immutable as $$
  select case when regexp_replace(coalesce(t, ''), '(?i)sar|,|\s', '', 'g') ~ '^-?[0-9]+(\.[0-9]+)?$'
              then regexp_replace(t, '(?i)sar|,|\s', '', 'g')::numeric end $$;
-- a schedule impact or cost: a number kept as written in digits, else the note (200 characters)
create or replace function pt_dly_numtext(t text) returns text language sql immutable as $$
  select case when nullif(btrim(coalesce(t, '')), '') is null then null
              when pt_dly_num(t) is not null then pt_dly_num(t)::text else left(btrim(t), 200) end $$;
create or replace function pt_dly_label(k text) returns text language sql immutable as $$
  select case k when 'start_date' then 'Claim event start date' when 'closed_on' then 'Claim event closing date (if closed)'
    when 'notice_date' then 'Notice of claim submission date' when 'data_date' then 'Claim data date'
    when 'prolong_cost' then 'Prolongation cost impact (SAR, if calculated)' when 'vo_omit' then 'Variation orders cost, omission (SAR, if calculated)'
    when 'vo_add' then 'Variation orders cost, added (SAR, if calculated)' else k end $$;
create or replace function pt_dly_keys() returns text[] language sql immutable as $$
  select array['event_no','name','identification','start_date','status','closed_on','support_docs','time_bar','notice_date','notice_docs',
               'description','affected','sched_impact','data_date','entitlement','liability','prolong_cost','vo_omit','vo_add',
               'concurrency','mitigation','owner'] $$;

-- the event after the change: the stored row (or nothing) with the fields sent, cleaned; raises the app's messages
create or replace function pt_dly_merge(pid text, eid uuid, f jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare m jsonb := '{}'::jsonb; k text; v text; n numeric; today date := current_date;
begin
  if eid is not null then select to_jsonb(e) into m from delay_events e where id = eid; end if;
  foreach k in array pt_dly_keys() loop
    if not (f ? k) then continue; end if;
    v := nullif(btrim(coalesce(f ->> k, '')), '');
    if k in ('start_date','closed_on','notice_date','data_date') then
      if v is not null and (v !~ '^\d{4}-\d{2}-\d{2}$' or pt_date(v) is null) then raise exception '%: not a valid date', pt_dly_label(k); end if;
      m := m || jsonb_build_object(k, v);
    elsif k = 'time_bar' then
      if v is not null and (v !~ '^[0-9]{1,4}$' or v::int > 3650) then raise exception 'The time bar is a whole number of days, from 0 to 3650'; end if;
      m := m || jsonb_build_object(k, v::int);
    elsif k in ('sched_impact','prolong_cost','vo_omit','vo_add') then m := m || jsonb_build_object(k, pt_dly_numtext(v));
    elsif k = 'status' then
      if pt_dly_status(v) is null then raise exception 'The delay event status is Ongoing or Closed'; end if;
      m := m || jsonb_build_object(k, pt_dly_status(v));
    else m := m || jsonb_build_object(k, left(v, case when k in ('event_no','identification','entitlement','liability','concurrency','owner') then 200 else 4000 end));
    end if;
  end loop;
  if eid is null and nullif(m ->> 'status', '') is null then m := m || jsonb_build_object('status', case when nullif(m ->> 'closed_on', '') is not null then 'Closed' else 'Ongoing' end); end if;
  if nullif(btrim(coalesce(m ->> 'name', '')), '') is null then raise exception 'Enter the claim event name'; end if;
  if nullif(m ->> 'start_date', '') is null then raise exception 'Enter the claim event start date'; end if;
  if (m ->> 'start_date')::date > today then raise exception 'The claim event start date cannot be in the future'; end if;
  if m ->> 'status' = 'Closed' and nullif(m ->> 'closed_on', '') is null then raise exception 'Enter the closing date of a closed event'; end if;
  if m ->> 'status' <> 'Closed' and nullif(m ->> 'closed_on', '') is not null then
    raise exception 'A closing date is entered only when the event is closed: set the status to Closed, or clear the date'; end if;
  if (m ->> 'closed_on')::date < (m ->> 'start_date')::date then raise exception 'The closing date cannot be before the start date'; end if;
  if (m ->> 'closed_on')::date > today then raise exception 'The closing date cannot be in the future'; end if;
  if (m ->> 'notice_date')::date < (m ->> 'start_date')::date then raise exception 'The notice of claim cannot be dated before the event started'; end if;
  if (m ->> 'notice_date')::date > today then raise exception 'The notice of claim submission date cannot be in the future'; end if;
  if (m ->> 'data_date')::date > today then raise exception 'The claim data date cannot be in the future'; end if;
  if pt_dly_num(m ->> 'sched_impact') < 0 then raise exception 'The schedule impact cannot be negative'; end if;
  foreach k in array array['prolong_cost','vo_omit','vo_add'] loop
    n := pt_dly_num(m ->> k);
    if n < 0 then raise exception '%: enter the amount as a positive number', pt_dly_label(k); end if;
  end loop;
  if nullif(m ->> 'event_no', '') is not null and exists (select 1 from delay_events where project_id = pid and id is distinct from eid and pt_dly_nokey(event_no) = pt_dly_nokey(m ->> 'event_no')) then
    raise exception '% is already used on this project', m ->> 'event_no'; end if;
  return m;
end $$;

create or replace function pt_dly_log(e delay_events, a text, note text, detail jsonb) returns void language sql security definer set search_path = public as $$
  insert into delay_audit (event_id, project_id, event_no, action, note, detail, by_user, by_name, by_role)
  values (e.id, e.project_id, e.event_no, a, note, detail, auth.uid(), name_of(auth.uid()), role_of(auth.uid())) $$;

-- writes one event (new when eid is null); returns the row; logs Created / Updated with the fields changed
create or replace function pt_dly_write(pid text, eid uuid, f jsonb, note text, label text) returns delay_events language plpgsql security definer set search_path = public as $$
declare m jsonb := pt_dly_merge(pid, eid, f); e delay_events; old jsonb; ch text[] := '{}'; k text; n int; no text;
begin
  if eid is null then
    select coalesce(max(ref), 0) + 1 into n from delay_events where project_id = pid;
    no := nullif(btrim(coalesce(m ->> 'event_no', '')), '');
    if no is null then
      select 'Event ' || lpad((coalesce(max(nullif(substring(event_no from '[0-9]+'), '')::int), 0) + 1)::text, 2, '0') into no from delay_events where project_id = pid;
    end if;
    insert into delay_events (project_id, ref, event_no, name, start_date, status, closed_on, created_by, updated_by)
    values (pid, n, no, m ->> 'name', (m ->> 'start_date')::date, m ->> 'status', (m ->> 'closed_on')::date, auth.uid(), auth.uid()) returning * into e;
    old := '{}'::jsonb;   -- v3.26.1: a new event's audit lists every field set
  else
    select to_jsonb(x) into old from delay_events x where id = eid;
  end if;
  update delay_events set
    name = m ->> 'name', identification = m ->> 'identification', start_date = (m ->> 'start_date')::date, status = m ->> 'status',
    closed_on = (m ->> 'closed_on')::date, support_docs = m ->> 'support_docs', time_bar = (m ->> 'time_bar')::int,
    notice_date = (m ->> 'notice_date')::date, notice_docs = m ->> 'notice_docs', description = m ->> 'description', affected = m ->> 'affected',
    sched_impact = m ->> 'sched_impact', data_date = (m ->> 'data_date')::date, entitlement = m ->> 'entitlement', liability = m ->> 'liability',
    prolong_cost = m ->> 'prolong_cost', vo_omit = m ->> 'vo_omit', vo_add = m ->> 'vo_add', concurrency = m ->> 'concurrency',
    mitigation = m ->> 'mitigation', owner = m ->> 'owner',
    event_no = coalesce(nullif(btrim(coalesce(m ->> 'event_no', '')), ''), event_no)
  where id = coalesce(eid, e.id) returning * into e;
  foreach k in array pt_dly_keys() loop
    if (to_jsonb(e) -> k) is distinct from (old -> k) then ch := ch || k; end if;
  end loop;
  if eid is null then perform pt_dly_log(e, 'Created', null, jsonb_build_object('fields', to_jsonb(ch), 'source', label));
  elsif array_length(ch, 1) > 0 then
    update delay_events set updated_by = auth.uid(), updated_at = now() where id = e.id returning * into e;
    perform pt_dly_log(e, 'Updated', note, jsonb_build_object('changes', to_jsonb(ch), 'source', label));
  end if;
  return e;
end $$;

-- p: {action: 'save' | 'delete', id?, project_id? (new), fields?, note?}
create or replace function delay_act(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); a text := p ->> 'action'; eid uuid; e delay_events; pid text; note text := nullif(btrim(coalesce(p ->> 'note', '')), '');
begin
  if me is null or role_of(me) is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if a is null or a not in ('save','delete') then raise exception 'Unknown action %', coalesce(a, ''); end if;
  if nullif(p ->> 'id', '') is not null then
    eid := (p ->> 'id')::uuid;
    select * into e from delay_events where id = eid for update;
    if not found then raise exception 'Unknown delay event'; end if;
    pid := e.project_id;
  else pid := p ->> 'project_id'; end if;
  if pid is null or not user_sees(me, pid) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
  if not pt_dly_keeper(me, pid) then
    raise exception 'Only the planning engineers of this project, the Head of Planning and Cost Control or a super admin can change its delay events register' using errcode = '42501'; end if;
  if a = 'delete' then
    if eid is null then raise exception 'Unknown delay event'; end if;
    if note is null then raise exception 'Say why this delay event is deleted'; end if;
    perform pt_dly_log(e, 'Deleted', note, jsonb_build_object('event', to_jsonb(e)));
    delete from delay_events where id = eid;
    return to_jsonb(e);
  end if;
  e := pt_dly_write(pid, eid, coalesce(p -> 'fields', '{}'::jsonb), note, 'window');
  return to_jsonb(e);
end $$;

-- p: {project_id, file_name, hash, ack, rows: [{row, event_no, name, ...}]}
create or replace function delay_import(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); pid text := p ->> 'project_id'; rows jsonb := coalesce(p -> 'rows', '[]'::jsonb); x jsonb; f jsonb; err text; n int := 0;
        acc jsonb := '[]'::jsonb; rej jsonb := '[]'::jsonb; eid uuid; e delay_events; before bigint; created int := 0; updated int := 0; same int := 0; bid uuid;
        seen jsonb := '{}'::jsonb; key text;
begin
  if me is null or role_of(me) is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if pid is null or not exists (select 1 from projects where id = pid) then raise exception 'Choose the project of this register'; end if;
  if not pt_dly_keeper(me, pid) then
    raise exception 'Only the planning engineers of this project, the Head of Planning and Cost Control or a super admin upload its delay events register' using errcode = '42501'; end if;
  if jsonb_typeof(rows) <> 'array' or jsonb_array_length(rows) = 0 then raise exception 'The file has no rows'; end if;
  if jsonb_array_length(rows) > 2000 then raise exception 'At most 2000 rows per upload'; end if;
  if exists (select 1 from import_batches where kind = 'delays' and project_id = pid and by_user = me and status = 'committed' and file_hash = p ->> 'hash'
             and at_time = (select max(at_time) from import_batches where kind = 'delays' and project_id = pid and by_user = me and status = 'committed')) then
    return jsonb_build_object('duplicate', true); end if;
  -- first every row is checked, nothing is written
  for x in select * from jsonb_array_elements(rows) loop
    n := n + 1; err := null; f := x - 'row' - 'ref'; eid := null;
    if nullif(btrim(coalesce(f ->> 'event_no', '')), '') is null then f := f - 'event_no'; end if;
    select id into eid from delay_events where project_id = pid and
      case when f ? 'event_no' then pt_dly_nokey(event_no) = pt_dly_nokey(f ->> 'event_no') else pt_dly_nokey(name) = pt_dly_nokey(f ->> 'name') end
      order by ref limit 1;
    key := case when f ? 'event_no' then pt_dly_nokey(f ->> 'event_no') end;
    if nullif(btrim(coalesce(f ->> 'name', '')), '') is null then err := 'claim event name missing';
    elsif key is not null and seen ? key then err := format('%s appears twice in the file (row %s)', f ->> 'event_no', seen ->> key);
    else
      begin perform pt_dly_merge(pid, eid, f); exception when others then err := sqlerrm; end;
    end if;
    if err is null then
      acc := acc || jsonb_build_array(jsonb_build_object('id', eid, 'f', f));
      if key is not null then seen := seen || jsonb_build_object(key, coalesce(x ->> 'row', n::text)); end if;
    else rej := rej || jsonb_build_array(jsonb_build_object('row', case when x ->> 'row' ~ '^[0-9]{1,7}$' then (x ->> 'row')::int else n end,
                                                          'event', left(coalesce(f ->> 'event_no', f ->> 'name', ''), 80), 'error', err)); end if;
  end loop;
  if jsonb_array_length(acc) = 0 then raise exception 'No valid rows, so nothing was saved. First problem: row % %', rej -> 0 ->> 'row', rej -> 0 ->> 'error'; end if;
  if jsonb_array_length(rej) > 0 and not coalesce((p ->> 'ack')::boolean, false) then
    raise exception '% row(s) refused; acknowledge them to save the rest. First: row % %', jsonb_array_length(rej), rej -> 0 ->> 'row', rej -> 0 ->> 'error'; end if;
  insert into import_batches (project_id, kind, file_name, file_hash, rows_total, rows_accepted, rows_rejected, recon_status, recon_accepted_by, detail, by_user)
  values (pid, 'delays', left(p ->> 'file_name', 200), p ->> 'hash', jsonb_array_length(rows), jsonb_array_length(acc), jsonb_array_length(rej),
          case when jsonb_array_length(rej) > 0 then 'Accepted with difference' end, case when jsonb_array_length(rej) > 0 then me end,
          jsonb_build_object('rejected', rej), me) returning id into bid;
  for x in select e2 from jsonb_array_elements(acc) e2 order by (nullif(e2 ->> 'id', '') is not null or (e2 -> 'f') ? 'event_no') desc loop   -- explicit numbers before generated ones
    eid := nullif(x ->> 'id', '')::uuid;
    if eid is null then perform pt_dly_write(pid, null, x -> 'f', p ->> 'file_name', 'upload'); created := created + 1;
    else
      select count(*) into before from delay_audit where event_id = eid;
      perform pt_dly_write(pid, eid, x -> 'f', 'From upload ' || coalesce(p ->> 'file_name', ''), 'upload');
      if (select count(*) from delay_audit where event_id = eid) > before then updated := updated + 1; else same := same + 1; end if;
    end if;
  end loop;
  return jsonb_build_object('duplicate', false, 'batch_id', bid, 'created', created, 'updated', updated, 'unchanged', same, 'rejected', rej);
end $$;

-- the app asks this to know v24 is in (schema-rollback-v24.sql removes it)
create or replace function delay_features() returns jsonb language sql immutable as $$
  select '{"version":24,"delay_register":true}'::jsonb $$;

-- ------------------------------------------------------------------ grants
revoke execute on function pt_dly_keeper(uuid, text), pt_dly_status(text), pt_dly_nokey(text), pt_dly_num(text), pt_dly_numtext(text), pt_dly_label(text),
  pt_dly_keys(), pt_dly_merge(text, uuid, jsonb), pt_dly_log(delay_events, text, text, jsonb), pt_dly_write(text, uuid, jsonb, text, text),
  delay_act(jsonb), delay_import(jsonb), delay_features() from public, anon, authenticated;
grant execute on function delay_act(jsonb), delay_import(jsonb), delay_features() to authenticated;
