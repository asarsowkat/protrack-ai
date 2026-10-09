-- ProTrack schema update v4 (Phase 2: foundation)
-- 1. Daily reports can only change through server functions that check role, project access,
--    the approval matrix and the allowed status steps. Direct table writes are refused.
-- 2. The report audit trail and the change log are append-only; each audit entry carries a hash of
--    the one before it, so any tampering is detectable.
-- 3. Imports (invoice register, costing file, baseline) run in one transaction, are recorded as
--    batches with a file hash, and are idempotent: the same file twice changes nothing the second time.
-- 4. Export of a project's data for backup, and a super-admin migration function for moving
--    browser data to the server.
-- Run AFTER schema.sql, schema-update-v2.sql and schema-update-v3.sql. Safe to run more than once.
-- Supabase -> SQL Editor -> New query -> paste -> Run.

-- ------------------------------------------------------------------ columns
alter table dprs add column if not exists foreman_id uuid references profiles(id);
alter table dprs add column if not exists returned boolean not null default false;
alter table dprs add column if not exists late boolean not null default false;
alter table dprs add column if not exists remarks text;
alter table dprs add column if not exists photo_names jsonb not null default '[]'::jsonb;  -- file names only, as in the app today
alter table dpr_lines add column if not exists line_no int not null default 0;
alter table dpr_audit add column if not exists seq bigserial;
alter table dpr_audit add column if not exists by_name text;
alter table dpr_audit add column if not exists by_role text;
alter table dpr_audit add column if not exists prev_hash text;
alter table dpr_audit add column if not exists hash text;
create sequence if not exists dpr_seq start 1;

-- ------------------------------------------------------------------ helpers
create or replace function user_sees(u uuid, p text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when (select role::text from profiles where id = u and active) in ('sa','exec') then true
    when exists (select 1 from project_access a where a.user_id = u and a.project_id = p) then true
    when exists (select 1 from region_access r join projects pr on pr.region = r.region_id
                 where r.user_id = u and pr.id = p) then true
    else false end $$;

create or replace function role_of(u uuid) returns text
language sql stable security definer set search_path = public as $$
  select role::text from profiles where id = u and active $$;

create or replace function name_of(u uuid) returns text
language sql stable security definer set search_path = public as $$
  select name from profiles where id = u $$;

-- assigned reviewer of a foreman on a project, if still valid (active, with access)
create or replace function dpr_reviewer(p text, foreman uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select m.to_user from approval_matrix m
   where m.project_id = p and m.kind = 'fm' and m.from_user = foreman
     and role_of(m.to_user) = 'eng' and user_sees(m.to_user, p) $$;

-- assigned approver of a site engineer on a project, if still valid
create or replace function dpr_approver(p text, engineer uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select m.to_user from approval_matrix m
   where m.project_id = p and m.kind = 'eng' and m.from_user = engineer
     and role_of(m.to_user) = 'sm' and user_sees(m.to_user, p) $$;

-- Kept for compatibility; the guards below check who is writing, not a setting.
create or replace function pt_begin() returns void language sql as
  $$ select set_config('protrack.rpc', 'on', true) $$;

-- ------------------------------------------------------------------ guards
create or replace function pt_guard() returns trigger
language plpgsql as $$
begin
  -- The app signs in as the role 'authenticated'. ProTrack functions run as their owner, so a write
  -- arriving as 'authenticated' or 'anon' came straight from a browser and is refused.
  if current_user in ('authenticated', 'anon') then
    raise exception 'Daily reports can only be changed through ProTrack' using errcode = '42501';
  end if;
  if tg_table_name = 'dprs' and tg_op <> 'INSERT' then
    if old.status = 'Approved' and coalesce(current_setting('protrack.migrating', true), '') <> 'on' then
      raise exception 'An approved report cannot be changed or deleted' using errcode = '42501';
    end if;
  end if;
  return coalesce(new, old);
end $$;

drop trigger if exists trg_guard_dprs on dprs;
create trigger trg_guard_dprs before insert or update or delete on dprs
  for each row execute function pt_guard();
drop trigger if exists trg_guard_lines on dpr_lines;
create trigger trg_guard_lines before insert or update or delete on dpr_lines
  for each row execute function pt_guard();

-- The fingerprint of one audit entry, including the fingerprint of the entry before it.
create or replace function pt_audit_hash(prev text, dpr text, action text, note text, by_user uuid, by_name text, at_time timestamptz)
returns text language sql immutable as $$
  select encode(sha256(convert_to(concat_ws('|', coalesce(prev, ''), dpr, action, coalesce(note, ''),
         coalesce(by_user::text, ''), coalesce(by_name, ''),
         to_char(at_time at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US')), 'UTF8')), 'hex') $$;

create or replace function pt_audit_chain() returns trigger
language plpgsql as $$
declare p text;
begin
  if tg_op <> 'INSERT' then
    raise exception 'The audit trail cannot be changed or deleted' using errcode = '42501';
  end if;
  if current_user in ('authenticated', 'anon') then
    raise exception 'Audit entries can only be written by ProTrack' using errcode = '42501';
  end if;
  if new.at_time is null then new.at_time := clock_timestamp(); end if;
  select a.hash into p from dpr_audit a where a.dpr_id = new.dpr_id order by a.seq desc limit 1;
  new.prev_hash := p;
  new.hash := pt_audit_hash(p, new.dpr_id, new.action, new.note, new.by_user, new.by_name, new.at_time);
  return new;
end $$;

drop trigger if exists trg_audit_chain on dpr_audit;
create trigger trg_audit_chain before insert or update or delete on dpr_audit
  for each row execute function pt_audit_chain();

create or replace function pt_no_truncate() returns trigger language plpgsql as $$
begin raise exception '% cannot be emptied', tg_table_name using errcode = '42501'; end $$;
drop trigger if exists trg_audit_truncate on dpr_audit;
create trigger trg_audit_truncate before truncate on dpr_audit execute function pt_no_truncate();

create or replace function pt_append_only() returns trigger language plpgsql as $$
begin raise exception '% is append-only', tg_table_name using errcode = '42501'; end $$;
drop trigger if exists trg_log_append on change_log;
create trigger trg_log_append before update or delete on change_log
  for each row execute function pt_append_only();
drop trigger if exists trg_log_truncate on change_log;
create trigger trg_log_truncate before truncate on change_log execute function pt_no_truncate();
-- change log entries carry the signed-in person, and nobody can write an entry in someone else's name
alter table change_log alter column by_user set default auth.uid();
drop policy if exists cl_write on change_log;
create policy cl_write on change_log for insert
  with check (auth.uid() is not null and (by_user is null or by_user = auth.uid()));

-- Recomputes a report's audit chain; false means an entry was altered or removed.
create or replace function dpr_audit_verify(p_dpr text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare r record; p text := null; h text;
begin
  if auth.uid() is not null and not exists (select 1 from dprs where id = p_dpr and user_sees(auth.uid(), project_id)) then
    raise exception 'Report not found' using errcode = '42501'; end if;
  for r in select * from dpr_audit where dpr_id = p_dpr order by seq loop
    h := pt_audit_hash(p, r.dpr_id, r.action, r.note, r.by_user, r.by_name, r.at_time);
    if r.hash is distinct from h or r.prev_hash is distinct from p then return false; end if;
    p := r.hash;
  end loop;
  return true;
end $$;

-- Seal audit entries written before this update, so the chain covers them too (runs once; later runs find nothing).
do $$
declare r record; p text; cur text;
begin
  if not exists (select 1 from dpr_audit where hash is null) then return; end if;
  alter table dpr_audit disable trigger trg_audit_chain;
  for r in select * from dpr_audit where hash is null order by dpr_id, seq loop
    if cur is distinct from r.dpr_id then
      cur := r.dpr_id;
      select a.hash into p from dpr_audit a where a.dpr_id = r.dpr_id and a.hash is not null and a.seq < r.seq order by a.seq desc limit 1;
    end if;
    update dpr_audit set prev_hash = p, hash = pt_audit_hash(p, r.dpr_id, r.action, r.note, r.by_user, r.by_name, r.at_time) where id = r.id
      returning hash into p;
  end loop;
  alter table dpr_audit enable trigger trg_audit_chain;
end $$;

-- direct writes from the app are no longer allowed; reads stay project-scoped
drop policy if exists d_insert on dprs;
drop policy if exists d_update on dprs;
drop policy if exists dl_write on dpr_lines;
drop policy if exists da_write on dpr_audit;

-- ------------------------------------------------------------------ audit writer
create or replace function pt_audit(p_dpr text, p_action text, p_note text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform pt_begin();
  insert into dpr_audit (dpr_id, action, note, by_user, by_name, by_role)
  values (p_dpr, p_action, nullif(p_note, ''), auth.uid(), name_of(auth.uid()), role_of(auth.uid()));
end $$;

create or replace function pt_timing(t jsonb, k text, secs int) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when coalesce(secs, 0) <= 0 then coalesce(t, '{}'::jsonb)
  else jsonb_set(coalesce(t, '{}'::jsonb), array[k], jsonb_build_object(
    'secs', coalesce((t -> k ->> 'secs')::int, 0) + secs,
    'by', name_of(auth.uid()), 'role', role_of(auth.uid()),
    'sessions', coalesce((t -> k ->> 'sessions')::int, 0) + 1,
    'at', to_char(now(), 'YYYY-MM-DD HH24:MI'))) end $$;

-- ------------------------------------------------------------------ save and submit
-- p: {id?, project_id, report_date, foreman_id?, foreman?, remarks?, lines:[{activity_id, qty, labour, subs, equip}],
--     submit: bool, secs: int}
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

-- ------------------------------------------------------------------ review, approve, return, reject
create or replace function dpr_act(p_id text, p_action text, p_note text default null, p_secs int default 0) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); r text := role_of(auth.uid()); d dprs; rev uuid; reviewed_by uuid; apr uuid;
  boss boolean; can boolean := false; kind text;
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

-- ------------------------------------------------------------------ import batches
create table if not exists import_batches (
  id uuid primary key default uuid_generate_v4(),
  project_id text references projects(id) on delete cascade,
  kind text not null check (kind in ('invoices','costing','baseline','update','migration','restore')),
  source_system text not null default 'Excel',
  file_name text, file_hash text, source_period text,
  rows_total int, rows_accepted int, rows_rejected int,
  total_source numeric, total_accepted numeric,
  status text not null default 'committed',
  detail jsonb default '{}'::jsonb,
  by_user uuid references profiles(id), at_time timestamptz default now());
drop index if exists import_batches_once;
create index if not exists import_batches_latest on import_batches (project_id, kind, at_time desc);
alter table import_batches enable row level security;
drop policy if exists ib_read on import_batches;
create policy ib_read on import_batches for select using (project_id is null or can_see(project_id));
-- no insert/update/delete policies: only the functions below write batches

-- A load is a repeat when it matches the LAST committed load of that kind for the project. (Loading
-- register A, then B, then A again must apply A again.) The lock makes a double click wait for the first.
create or replace function pt_batch_seen(p text, k text, h text) returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare b import_batches;
begin
  perform pg_advisory_xact_lock(hashtext('protrack:' || coalesce(p, '') || ':' || k));
  select * into b from import_batches where project_id = p and kind = k and status = 'committed'
   order by at_time desc, id desc limit 1;
  return case when b.file_hash = h then b.id end;
end $$;

-- Invoice register: replaces the project's register in one transaction. Rows failing a rule are
-- refused and reported, never stored. Re-sending the same file (same hash) changes nothing.
create or replace function import_invoices(p_project text, p_file text, p_hash text, p_rows jsonb, p_period text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); seen uuid; acc jsonb; rej jsonb; bid uuid; n_all int;
begin
  if me is null or not can_cost(p_project) then raise exception 'Only costing engineers, project managers and super admins of this project can load invoices' using errcode = '42501'; end if;
  if p_hash is null or length(p_hash) < 16 then raise exception 'A file hash is required'; end if;
  seen := pt_batch_seen(p_project, 'invoices', p_hash);
  if seen is not null then return jsonb_build_object('duplicate', true, 'batch_id', seen); end if;
  n_all := jsonb_array_length(p_rows);
  with r as (select x, (x ->> 'no') no_, coalesce((x ->> 'sub')::numeric, 0) sub, coalesce((x ->> 'amount')::numeric, 0) amount,
                    coalesce((x ->> 'appr')::numeric, 0) appr, coalesce((x ->> 'coll')::numeric, 0) coll,
                    count(*) over (partition by x ->> 'no') dup
               from jsonb_array_elements(p_rows) x),
       c as (select *, case when coalesce(trim(no_), '') = '' then 'No invoice number'
                            when dup > 1 then 'Invoice number appears more than once'
                            when greatest(sub, amount) <= 0 then 'No invoice amount'
                            when sub > 0 and appr > sub * 1.001 then 'Approved is more than submitted'
                            when appr > 0 and coll > appr * 1.001 then 'Collected is more than approved' end err from r)
  select coalesce(jsonb_agg(x) filter (where err is null), '[]'::jsonb),
         coalesce(jsonb_agg(jsonb_build_object('no', no_, 'error', err)) filter (where err is not null), '[]'::jsonb)
    into acc, rej from c;
  delete from invoices where project_id = p_project;
  insert into invoices (project_id, invoice_no, invoice_date, inv_type, amount, submitted, approved, collected, remark, uploaded_by)
  select p_project, x ->> 'no', nullif(x ->> 'date', '')::date, coalesce(nullif(x ->> 'type', ''), 'Progress'),
         coalesce((x ->> 'amount')::numeric, (x ->> 'sub')::numeric, 0),
         coalesce((x ->> 'sub')::numeric, (x ->> 'amount')::numeric, 0),
         coalesce((x ->> 'appr')::numeric, 0), coalesce((x ->> 'coll')::numeric, 0), x ->> 'note', me
    from jsonb_array_elements(acc) x;
  insert into import_batches (project_id, kind, file_name, file_hash, source_period, rows_total, rows_accepted, rows_rejected,
                              total_source, total_accepted, detail, by_user)
  values (p_project, 'invoices', p_file, p_hash, p_period, n_all, jsonb_array_length(acc), jsonb_array_length(rej),
          (select coalesce(sum(coalesce((x ->> 'sub')::numeric, (x ->> 'amount')::numeric, 0)), 0) from jsonb_array_elements(p_rows) x),
          (select coalesce(sum(submitted), 0) from invoices where project_id = p_project),
          jsonb_build_object('rejected', rej), me)
  returning id into bid;
  insert into upload_history (project_id, kind, file_name, rows_total, rows_ok, rows_rejected, by_user)
  values (p_project, 'invoices', p_file, n_all, jsonb_array_length(acc), jsonb_array_length(rej), me);
  return jsonb_build_object('duplicate', false, 'batch_id', bid, 'accepted', jsonb_array_length(acc),
                            'rejected', rej, 'total_accepted', (select coalesce(sum(submitted), 0) from invoices where project_id = p_project));
end $$;

-- Costing file: updates matched activities in one transaction, after snapshotting them for undo.
-- p_rows: [{id, qty, uom, rate, cost, mh, gang}]
create or replace function apply_costing(p_project text, p_file text, p_hash text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); seen uuid; bid uuid; src text; n_ok int; rej jsonb;
begin
  if me is null or not can_cost(p_project) then raise exception 'Only costing engineers, project managers and super admins of this project can apply a costing file' using errcode = '42501'; end if;
  if p_hash is null or length(p_hash) < 16 then raise exception 'A file hash is required'; end if;
  seen := pt_batch_seen(p_project, 'costing', p_hash);
  if seen is not null then return jsonb_build_object('duplicate', true, 'batch_id', seen); end if;
  select coalesce(mh_source, 'Costing file') into src from projects where id = p_project;
  select coalesce(jsonb_agg(jsonb_build_object('id', x ->> 'id', 'error',
           case when not exists (select 1 from activities a where a.project_id = p_project and lower(a.id) = lower(x ->> 'id')) then 'Not in the baseline'
                else 'No budget quantity' end)), '[]'::jsonb)
    into rej from jsonb_array_elements(p_rows) x
   where not exists (select 1 from activities a where a.project_id = p_project and lower(a.id) = lower(x ->> 'id'))
      or coalesce((x ->> 'qty')::numeric, 0) <= 0;
  insert into baseline_history (project_id, taken_by, file_name, activities)
  select p_project, me, 'Costing: ' || coalesce(p_file, ''), coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) from activities a where a.project_id = p_project;
  with ok as (select x from jsonb_array_elements(p_rows) x
               where coalesce((x ->> 'qty')::numeric, 0) > 0
                 and exists (select 1 from activities a where a.project_id = p_project and lower(a.id) = lower(x ->> 'id')))
  update activities a set
    p6_mh = coalesce(a.p6_mh, a.budget_mh),
    qty = (x ->> 'qty')::numeric, uom = left(coalesce(x ->> 'uom', ''), 12),
    costing_mh = nullif((x ->> 'mh')::numeric, 0),
    budget_mh = case when coalesce((x ->> 'mh')::numeric, 0) > 0 and src = 'Costing file' then (x ->> 'mh')::numeric
                     when src = 'P6 resource loading' then coalesce(a.p6_mh, a.budget_mh) else a.budget_mh end,
    budget_rate = coalesce((x ->> 'rate')::numeric, 0), budget_cost = coalesce((x ->> 'cost')::numeric, 0),
    gang = coalesce(nullif(x ->> 'gang', ''), a.gang), costed = true
  from ok where a.project_id = p_project and lower(a.id) = lower(ok.x ->> 'id');
  get diagnostics n_ok = row_count;
  insert into import_batches (project_id, kind, file_name, file_hash, rows_total, rows_accepted, rows_rejected,
                              total_source, total_accepted, detail, by_user)
  values (p_project, 'costing', p_file, p_hash, jsonb_array_length(p_rows), n_ok, jsonb_array_length(rej),
          (select coalesce(sum((x ->> 'cost')::numeric), 0) from jsonb_array_elements(p_rows) x),
          (select coalesce(sum(budget_cost), 0) from activities where project_id = p_project and costed),
          jsonb_build_object('rejected', rej), me)
  returning id into bid;
  insert into upload_history (project_id, kind, file_name, rows_total, rows_ok, rows_rejected, by_user)
  values (p_project, 'costing', p_file, jsonb_array_length(p_rows), n_ok, jsonb_array_length(rej), me);
  return jsonb_build_object('duplicate', false, 'batch_id', bid, 'applied', n_ok, 'rejected', rej);
end $$;

-- Baseline: upserts activities by ID (others are kept), after a snapshot for undo. Planning only.
-- p_rows: [{id, name, cls, disc, area, wbs, uom, qty, budget_mh, price_weight, trade_mix, bs, bf, prior_qty}]
create or replace function import_baseline(p_project text, p_file text, p_hash text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); seen uuid; bid uuid; n int;
begin
  if me is null or not can_plan(p_project) then raise exception 'Only planning engineers and super admins of this project can load a baseline' using errcode = '42501'; end if;
  if p_hash is null or length(p_hash) < 16 then raise exception 'A file hash is required'; end if;
  seen := pt_batch_seen(p_project, 'baseline', p_hash);
  if seen is not null then return jsonb_build_object('duplicate', true, 'batch_id', seen); end if;
  if exists (select 1 from jsonb_array_elements(p_rows) x where coalesce(x ->> 'id', '') = '' or coalesce(x ->> 'name', '') = '') then
    raise exception 'Every activity needs an ID and a name; nothing was imported'; end if;
  insert into baseline_history (project_id, taken_by, file_name, activities)
  select p_project, me, p_file, coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) from activities a where a.project_id = p_project;
  insert into activities (id, project_id, name, cls, disc, area, wbs, uom, qty, budget_mh, p6_mh, price_weight, trade_mix, bs, bf, prior_qty, cur)
  select x ->> 'id', p_project, x ->> 'name', coalesce(nullif(x ->> 'cls', ''), 'CON'), x ->> 'disc', x ->> 'area', x ->> 'wbs',
         x ->> 'uom', nullif(x ->> 'qty', '')::numeric, nullif(x ->> 'budget_mh', '')::numeric, nullif(x ->> 'budget_mh', '')::numeric,
         nullif(x ->> 'price_weight', '')::numeric, coalesce(x -> 'trade_mix', '{}'::jsonb),
         nullif(x ->> 'bs', '')::date, nullif(x ->> 'bf', '')::date, coalesce(nullif(x ->> 'prior_qty', '')::numeric, 0),
         coalesce(x -> 'cur', '{}'::jsonb)
    from jsonb_array_elements(p_rows) x
  on conflict (project_id, id) do update set name = excluded.name, cls = excluded.cls, disc = excluded.disc, area = excluded.area,
    wbs = excluded.wbs, uom = coalesce(excluded.uom, activities.uom), qty = coalesce(excluded.qty, activities.qty),
    budget_mh = coalesce(excluded.budget_mh, activities.budget_mh), p6_mh = excluded.p6_mh,
    price_weight = coalesce(excluded.price_weight, activities.price_weight), trade_mix = excluded.trade_mix,
    bs = excluded.bs, bf = excluded.bf, prior_qty = excluded.prior_qty,
    cur = case when excluded.cur = '{}'::jsonb then activities.cur else excluded.cur end;
  get diagnostics n = row_count;
  -- the project's start and finish follow the imported activities, as in the app
  update projects set start_date = coalesce((select min(nullif(x ->> 'bs', '')::date) from jsonb_array_elements(p_rows) x), start_date),
                      finish_date = coalesce((select max(nullif(x ->> 'bf', '')::date) from jsonb_array_elements(p_rows) x), finish_date)
   where id = p_project;
  insert into import_batches (project_id, kind, source_system, file_name, file_hash, rows_total, rows_accepted, rows_rejected, by_user)
  values (p_project, 'baseline', 'Primavera P6', p_file, p_hash, jsonb_array_length(p_rows), n, 0, me) returning id into bid;
  return jsonb_build_object('duplicate', false, 'batch_id', bid, 'upserted', n);
end $$;

-- ------------------------------------------------------------------ team directory
-- The people the caller works with: everyone on a project the caller can see, plus super admins and
-- executives. Gives the app names for the approval route and addresses for approval emails, without
-- opening the whole profiles table.
create or replace function team_directory() returns table (id uuid, name text, title text, role text, active boolean,
  email text, projects text[], regions text[])
language sql stable security definer set search_path = public as $$
  with me as (select auth.uid() as u, role_of(auth.uid()) as r),
       vis as (select p.id from projects p, me where user_sees(me.u, p.id))
  select pr.id, pr.name, pr.title, pr.role::text, pr.active, au.email,
         coalesce((select array_agg(a.project_id order by a.project_id) from project_access a
                    where a.user_id = pr.id and a.project_id in (select vis.id from vis)), '{}'),
         coalesce((select array_agg(r.region_id order by r.region_id) from region_access r where r.user_id = pr.id), '{}')
    from profiles pr left join auth.users au on au.id = pr.id, me
   where me.r is not null
     and (me.r in ('sa','exec') or pr.role::text in ('sa','exec') or pr.id = me.u
          or exists (select 1 from vis where user_sees(pr.id, vis.id)))
   order by pr.name $$;

-- Super admin: give an existing sign-in account its name, role and access, in one step.
-- The account itself is created in Supabase (Authentication -> Users -> Add user); the browser cannot create it.
-- p: {email, name, title, role, active, projects:[...], regions:[...]}
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

-- ------------------------------------------------------------------ backup and migration
-- Everything about one project the caller may see, for a backup file.
create or replace function export_project(p text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not can_see(p) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
  return jsonb_build_object(
    'format', 'protrack-server-export', 'version', 4, 'exported_at', now(), 'project', (select to_jsonb(x) from projects x where id = p),
    'milestones', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from milestones x where project_id = p),
    'activities', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from activities x where project_id = p),
    'dprs', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from dprs x where project_id = p),
    'dpr_lines', (select coalesce(jsonb_agg(to_jsonb(l)), '[]') from dpr_lines l join dprs d on d.id = l.dpr_id where d.project_id = p),
    'dpr_audit', (select coalesce(jsonb_agg(to_jsonb(a) order by a.seq), '[]') from dpr_audit a join dprs d on d.id = a.dpr_id where d.project_id = p),
    'invoices', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from invoices x where project_id = p),
    'approval_matrix', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from approval_matrix x where project_id = p),
    'import_batches', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from import_batches x where project_id = p));
end $$;

-- Super admin only: loads daily reports from a browser export into an existing project.
-- Idempotent: a report whose ID already exists on the server is skipped and counted, never overwritten.
-- p: {project_id, file, hash, dprs:[{id, report_date, foreman, foreman_email?, status, remarks, returned, timing,
--     lines:[...], audit:[{action, note, who, at}]}]}
create or replace function migrate_dprs(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); pid text := p ->> 'project_id'; d jsonb; ln jsonb; au jsonb; i int;
        n_new int := 0; n_skip int := 0; n_lines int := 0; bad jsonb := '[]'::jsonb; seen uuid; bid uuid; fid uuid; mx int;
begin
  if role_of(me) is distinct from 'sa' then raise exception 'Only a super admin can migrate data' using errcode = '42501'; end if;
  if not exists (select 1 from projects where id = pid) then raise exception 'Project % is not on the server yet', pid; end if;
  seen := pt_batch_seen(pid, 'migration', p ->> 'hash');
  if seen is not null then return jsonb_build_object('duplicate', true, 'batch_id', seen); end if;
  perform pt_begin(); perform set_config('protrack.migrating', 'on', true);
  for d in select * from jsonb_array_elements(p -> 'dprs') loop
    if exists (select 1 from dprs where id = d ->> 'id') then n_skip := n_skip + 1; continue; end if;
    if exists (select 1 from jsonb_array_elements(d -> 'lines') l
                where not exists (select 1 from activities a where a.project_id = pid and a.id = l ->> 'activity_id')) then
      bad := bad || jsonb_build_object('id', d ->> 'id', 'error', 'An activity is not in the server baseline'); continue; end if;
    if coalesce(d ->> 'status', 'Draft') not in ('Draft','Submitted','Reviewed','Approved','Rejected') or (d ->> 'report_date') is null then
      bad := bad || jsonb_build_object('id', d ->> 'id', 'error', 'Unknown status or no date'); continue; end if;
    if exists (select 1 from dprs x where x.project_id = pid and x.report_date = (d ->> 'report_date')::date and x.foreman = d ->> 'foreman') then
      bad := bad || jsonb_build_object('id', d ->> 'id', 'error', 'The server already has a report for this foreman on this date'); continue; end if;
    select pr.id into fid from profiles pr join auth.users u on u.id = pr.id
     where lower(u.email) = lower(d ->> 'foreman_email') limit 1;
    insert into dprs (id, project_id, report_date, foreman, foreman_id, status, remarks, returned, late, timing, photo_names, created_by)
    values (d ->> 'id', pid, (d ->> 'report_date')::date, d ->> 'foreman', fid,
            coalesce(d ->> 'status', 'Draft')::dpr_status, d ->> 'remarks', coalesce((d ->> 'returned')::boolean, false),
            coalesce((d ->> 'late')::boolean, false), coalesce(d -> 'timing', '{}'::jsonb), coalesce(d -> 'photos', '[]'::jsonb), me);
    i := 0;
    for ln in select * from jsonb_array_elements(d -> 'lines') loop
      i := i + 1; n_lines := n_lines + 1;
      insert into dpr_lines (dpr_id, activity_id, qty, labour, subs, equip, line_no)
      values (d ->> 'id', ln ->> 'activity_id', coalesce((ln ->> 'qty')::numeric, 0), coalesce(ln -> 'labour', '[]'),
              coalesce(ln -> 'subs', '[]'), coalesce(ln -> 'equip', '[]'), i);
    end loop;
    for au in select * from jsonb_array_elements(coalesce(d -> 'audit', '[]'::jsonb)) loop
      insert into dpr_audit (dpr_id, action, note, by_user, by_name, by_role, at_time)
      values (d ->> 'id', au ->> 'action', nullif(au ->> 'note', ''), null, au ->> 'who', 'migrated',
              coalesce(nullif(au ->> 'at', '')::timestamptz, clock_timestamp()));
    end loop;
    insert into dpr_audit (dpr_id, action, note, by_user, by_name, by_role)
    values (d ->> 'id', 'Migrated to server', p ->> 'file', me, name_of(me), 'sa');
    n_new := n_new + 1;
  end loop;
  select max(nullif(regexp_replace(id, '\D', '', 'g'), '')::int) into mx from dprs;
  if mx is not null then perform setval('dpr_seq', greatest(mx, 1)); end if;
  insert into import_batches (project_id, kind, source_system, file_name, file_hash, rows_total, rows_accepted, rows_rejected, detail, by_user)
  values (pid, 'migration', 'Browser', p ->> 'file', p ->> 'hash', jsonb_array_length(p -> 'dprs'), n_new,
          jsonb_array_length(bad), jsonb_build_object('skipped_existing', n_skip, 'lines', n_lines, 'refused', bad), me)
  returning id into bid;
  return jsonb_build_object('duplicate', false, 'batch_id', bid, 'created', n_new, 'skipped_existing', n_skip,
                            'lines', n_lines, 'refused', bad);
end $$;

-- Only the functions the app needs are callable, and only by signed-in people.
-- Supabase grants new functions to everyone by default, so first take that back.
revoke execute on function pt_audit_hash(text, text, text, text, uuid, text, timestamptz), user_sees(uuid, text), role_of(uuid), name_of(uuid), dpr_reviewer(text, uuid),
  dpr_approver(text, uuid), pt_begin(), pt_guard(), pt_audit_chain(), pt_no_truncate(), pt_append_only(),
  pt_audit(text, text, text), pt_timing(jsonb, text, int), pt_batch_seen(text, text, text),
  dpr_save(jsonb), dpr_act(text, text, text, int), import_invoices(text, text, text, jsonb, text),
  apply_costing(text, text, text, jsonb), import_baseline(text, text, text, jsonb), export_project(text),
  migrate_dprs(jsonb), dpr_audit_verify(text), team_directory(), admin_save_person(jsonb) from public, anon, authenticated;
grant execute on function team_directory(), admin_save_person(jsonb), dpr_save(jsonb), dpr_act(text, text, text, int), import_invoices(text, text, text, jsonb, text),
  apply_costing(text, text, text, jsonb), import_baseline(text, text, text, jsonb), export_project(text),
  migrate_dprs(jsonb), dpr_audit_verify(text) to authenticated;
