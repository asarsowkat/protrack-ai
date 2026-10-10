-- ProTrack schema update v9 (ProTrackAI v3.0: released reporting)
-- * Progress releases: the planning engineer reviews site, design and procurement progress and releases it weekly
--   and monthly. Monthly cost reports: the costing engineer (or costing coordinator) records actual cost,
--   commitments, the Rev-0 budget and the forecast to complete; the server works out the approved budget (Rev-0 plus
--   approved budget supplements), EAC and VAC. Both are submitted and approved by the Head of Planning and Cost
--   Control (or a super admin) before anyone else sees them; nobody approves their own submission. A released
--   version never changes: a correction is a new revision, and the previous one is kept as superseded.
-- * Change order and claim log, and budget supplement log: uploaded per project each month, all-or-nothing, as
--   numbered import batches. Every upload is kept, so each month's log can be looked at later.
-- * Cost figures and both logs reach only roles that may see cost (not foremen, site engineers or site managers).
-- Run AFTER schema-update-v8.sql. Additive and safe to run more than once. Undo: schema-rollback-v9.sql.

-- ------------------------------------------------------------------ import batches may now also be the two logs
alter table import_batches drop constraint if exists import_batches_kind_check;
alter table import_batches add constraint import_batches_kind_check
  check (kind in ('invoices','costing','baseline','update','migration','restore','volog','supplements'));
drop policy if exists ib_read on import_batches;
create policy ib_read on import_batches for select using (
  ((project_id is not null and can_see(project_id)) or (project_id is null and my_role_text() in ('sa','exec','plan')))
  and (pt_money_ok() or kind not in ('costing','invoices','volog','supplements')));

-- ------------------------------------------------------------------ the two logs (one full copy per monthly upload)
create table if not exists co_log (
  id bigserial primary key,
  batch_id uuid not null references import_batches(id),
  project_id text not null references projects(id) on delete cascade,
  period text not null,
  ref_no text not null,
  kind text not null check (kind in ('VO','Claim')),
  description text,
  submission_status text, submitted_on date,
  client_status text,
  est_price numeric, est_cost numeric, expected_price numeric,
  price_internal text, cost_internal text,
  rev0_change numeric,
  internal_wf text, overall_status text, remarks text,
  unique (batch_id, ref_no));
create table if not exists budget_supplements (
  id bigserial primary key,
  batch_id uuid not null references import_batches(id),
  project_id text not null references projects(id) on delete cascade,
  period text not null,
  supp_no text not null, supp_date date, description text,
  amount numeric not null,
  category text not null check (category in ('Project execution','Under estimate','External factor','Saudization','Finance','Claims','Change order')),
  linked_ref text, approval_status text, remarks text,
  unique (batch_id, supp_no));
create index if not exists co_log_proj on co_log (project_id, period, batch_id);
create index if not exists bs_proj on budget_supplements (project_id, period, batch_id);
alter table co_log enable row level security;
alter table budget_supplements enable row level security;
drop policy if exists col_read on co_log;
create policy col_read on co_log for select using (can_see(project_id) and pt_money_ok());
drop policy if exists bsu_read on budget_supplements;
create policy bsu_read on budget_supplements for select using (can_see(project_id) and pt_money_ok());
drop trigger if exists trg_col_append on co_log;
create trigger trg_col_append before update or delete on co_log for each row execute function pt_append_only();
drop trigger if exists trg_bsu_append on budget_supplements;
create trigger trg_bsu_append before update or delete on budget_supplements for each row execute function pt_append_only();

-- ------------------------------------------------------------------ releases
create table if not exists report_releases (
  id uuid primary key default uuid_generate_v4(),
  project_id text not null references projects(id) on delete cascade,
  kind text not null check (kind in ('planning','cost')),
  period_type text not null check (period_type in ('week','month')),
  period text not null,
  rev int not null default 0,
  status text not null default 'Draft' check (status in ('Draft','Submitted','Released','Superseded')),
  data_date date,
  figures jsonb not null default '{}'::jsonb,
  overrides jsonb not null default '[]'::jsonb,
  narrative jsonb not null default '{}'::jsonb,
  revise_reason text,
  prepared_by uuid references profiles(id), prepared_at timestamptz default now(),
  submitted_by uuid references profiles(id), submitted_at timestamptz,
  approved_by uuid references profiles(id), approved_at timestamptz,
  updated_at timestamptz default now(),
  check (kind <> 'cost' or period_type = 'month'));
create unique index if not exists rr_one_open on report_releases (project_id, kind, period_type, period) where status in ('Draft','Submitted');
create unique index if not exists rr_one_released on report_releases (project_id, kind, period_type, period) where status = 'Released';
create table if not exists release_audit (
  id bigserial primary key,
  release_id uuid not null references report_releases(id) on delete cascade,
  project_id text not null references projects(id) on delete cascade,
  action text not null, note text, detail jsonb,
  by_user uuid references profiles(id), by_name text, by_role text,
  at_time timestamptz not null default now());
drop trigger if exists trg_rla_append on release_audit;
create trigger trg_rla_append before update or delete on release_audit for each row execute function pt_append_only();
drop trigger if exists trg_rla_truncate on release_audit;
create trigger trg_rla_truncate before truncate on release_audit execute function pt_no_truncate();

-- a released version never changes, even from the database console: only its status may move to Superseded
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
drop trigger if exists trg_rr_frozen on report_releases;
create trigger trg_rr_frozen before update on report_releases for each row execute function pt_release_frozen();
create or replace function pt_release_nodelete() returns trigger language plpgsql as $$
begin
  if old.status in ('Released','Superseded','Submitted') then raise exception 'Submitted and released versions cannot be deleted' using errcode = '42501'; end if;
  return old;
end $$;
drop trigger if exists trg_rr_nodelete on report_releases;
create trigger trg_rr_nodelete before delete on report_releases for each row execute function pt_release_nodelete();

-- who prepares each kind: planning = planning engineers; cost = costing engineers and costing coordinators; super admin both
create or replace function pt_release_staff(u uuid, k text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) = 'sa' or pt_is_head(u) or (k = 'planning' and role_of(u) = 'plan')
                  or (k = 'cost' and (role_of(u) = 'costing' or pt_is_coord(u))), false) $$;
create or replace function pt_release_preparer(u uuid, k text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) = 'sa' or (k = 'planning' and role_of(u) = 'plan') or (k = 'cost' and (role_of(u) = 'costing' or pt_is_coord(u))), false) $$;

alter table report_releases enable row level security;
alter table release_audit enable row level security;
drop policy if exists rr_read on report_releases;
create policy rr_read on report_releases for select using (
  can_see(project_id) and (kind <> 'cost' or pt_money_ok()) and (status in ('Released','Superseded') or pt_release_staff(auth.uid(), kind)));
drop policy if exists rla_read on release_audit;
create policy rla_read on release_audit for select using (exists (select 1 from report_releases r where r.id = release_id));
-- no write policies: only release_act and log_import below write

-- ------------------------------------------------------------------ helpers
create or replace function pt_period_ok(t text, typ text) returns boolean language sql immutable as $$
  select case when typ = 'month' then coalesce(t ~ '^\d{4}-(0[1-9]|1[0-2])$', false)
              when typ = 'week' then coalesce(t ~ '^\d{4}-W(0[1-9]|[1-4][0-9]|5[0-3])$', false) else false end $$;
create or replace function pt_month_of(t text) returns text language sql immutable as $$
  select case when t ~ '^\d{4}-\d{2}$' then t else null end $$;
-- approved budget supplements in the latest supplement log uploaded for the project up to the given month
create or replace function pt_supp_approved(pid text, per text) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(s.amount), 0) from budget_supplements s
   where s.batch_id = (select b.id from import_batches b where b.project_id = pid and b.kind = 'supplements' and b.status = 'committed'
                         and coalesce(b.source_period, '') <= per order by b.source_period desc, b.at_time desc limit 1)
     and lower(coalesce(s.approval_status, '')) = 'approved' $$;
create or replace function pt_rel_log(rid uuid, a text, note text, detail jsonb) returns void language sql security definer set search_path = public as $$
  insert into release_audit (release_id, project_id, action, note, detail, by_user, by_name, by_role)
  select id, project_id, a, note, detail, auth.uid(), name_of(auth.uid()), role_of(auth.uid()) from report_releases where id = rid $$;

-- ------------------------------------------------------------------ the one way to prepare, submit, approve, return and revise
-- p: {action: save|submit|approve|return|revise, id, project_id, kind, period_type, period, data_date, figures, overrides, narrative, note}
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

-- ------------------------------------------------------------------ monthly log upload (all-or-nothing, as an import batch)
-- p: {kind: volog|supplements, project_id, period: 'YYYY-MM', file_name, hash, rows:[...], ack: bool}
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

revoke execute on function pt_release_frozen(), pt_release_nodelete(), pt_release_staff(uuid, text), pt_release_preparer(uuid, text), pt_period_ok(text, text),
  pt_month_of(text), pt_supp_approved(text, text), pt_rel_log(uuid, text, text, jsonb), release_act(jsonb), log_import(jsonb) from public, anon, authenticated;
grant execute on function release_act(jsonb), log_import(jsonb) to authenticated;
grant execute on function pt_release_staff(uuid, text) to authenticated;   -- used by the read rule
