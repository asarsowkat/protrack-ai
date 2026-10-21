-- ProTrack schema update v27 (ProTrackAI v3.20): the cash-out forecast (Invoices & Cash Flow).
-- What the server keeps and checks, as the app's cash-out code (index.html, "v3.20: Cash-out forecast"):
-- 1. co_actuals: Finance's cumulative actual cash-out per project and month (SAR, project level). A period has one
--    current record; a correction adds a new record and marks the original superseded (kept, with the reason). Records
--    are never deleted or changed otherwise. co_batches: each import (file fingerprint, cutoff, projects, counts, refused
--    rows). The same file is imported once. co_opening: a verified zero opening balance per project.
--    Only a super admin or the Head Office cost control coordinator (pcc_designations 'coordinator') imports, on the
--    projects in their access.
-- 2. co_po_terms: each purchase order's payment terms and milestones (purchase_orders is the PO register). Kept by the
--    new right "cashout.keep" (costing engineers by default; the Head and the coordinator by position; super admins).
--    A paid milestone keeps what was paid unless an approver changes it with a reason; approving sets the baseline date.
--    A PO revision changes purchase_orders.po_value and is recorded with its reference and reason.
-- 3. co_other_lines: cash-out in the budget not covered by a PO (paid to date with its Finance reference, remaining,
--    months). co_scenarios: simulations. co_versions: forecast versions (draft → reviewed by someone else → published by
--    the Head or a super admin); a published version cannot change. co_reviews: the management review of an overrun,
--    required before an over-budget version is published.
-- 4. Everyone who sees cost figures reads the projects in their access (can_see and pt_money_ok). Every write goes
--    through cashout_act(p) = {kind, args}, with the app's rules. co_audit keeps every change and cannot be changed.
-- The forecast itself (months, forecast at completion, status) is worked out in the app from these records and the
-- released cost reports (the approved current budget); a version stores the figures as published.
-- Needs schema-update-v16.sql (rights) and schema-update-v7.sql (pt_is_coord). Additive. Safe to run twice.
-- Undo: schema-rollback-v27.sql.

do $$ begin
  if to_regprocedure('public.pt_right(uuid,text,boolean)') is null or to_regprocedure('public.pt_is_coord(uuid)') is null or to_regclass('public.purchase_orders') is null then
    raise exception 'Run schema-update-v7.sql and schema-update-v16.sql (STAGE-13-SETUP) first, then this update'; end if;
end $$;

-- ------------------------------------------------------------------ 1. the tables
create table if not exists co_batches (
  id text primary key, file_name text, file_hash text not null, sheet text, cutoff text not null, projects text[] not null,
  rows_total int, added int, restated int, unchanged int, refused int, result text not null default 'Committed',
  "by" uuid references profiles(id), by_name text, at timestamptz not null default now(), reason text, rejected jsonb);
create unique index if not exists co_batches_hash on co_batches (file_hash) where result = 'Committed';
create table if not exists co_actuals (
  id text primary key default 'CA' || replace(uuid_generate_v4()::text, '-', ''),
  project_id text not null references projects(id) on delete cascade,
  period text not null check (period ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  cum numeric(18,2) not null check (cum >= 0),
  currency text not null default 'SAR' check (currency = 'SAR'),
  remarks text, source_file text, batch_id text references co_batches(id),
  created_by uuid references profiles(id), created_by_name text, created_at timestamptz not null default now(),
  superseded_by text, supersedes text, reason text);
create unique index if not exists co_actuals_current on co_actuals (project_id, period) where superseded_by is null;
create table if not exists co_opening (project_id text primary key references projects(id) on delete cascade, zero boolean not null, note text, "by" text, at timestamptz not null default now());
create table if not exists co_po_terms (po_id uuid primary key references purchase_orders(id) on delete cascade, project_id text not null references projects(id) on delete cascade,
  state jsonb not null, updated_by uuid references profiles(id), updated_at timestamptz not null default now());
create table if not exists co_other_lines (
  id text primary key default 'CL' || replace(uuid_generate_v4()::text, '-', ''), project_id text not null references projects(id) on delete cascade,
  name text not null, category text, note text, paid_to_date numeric(18,2) not null default 0 check (paid_to_date >= 0), paid_ref text,
  remaining numeric(18,2) not null default 0 check (remaining >= 0), "from" text, "to" text, not_in_po boolean not null check (not_in_po),
  base_total numeric(18,2), base_from text, base_to text, created_by text, created_at timestamptz not null default now(), updated_by text, updated_at timestamptz,
  removed_at timestamptz, removed_by text, remove_note text);
create table if not exists co_versions (
  id text primary key default 'CV' || replace(uuid_generate_v4()::text, '-', ''), project_id text not null references projects(id) on delete cascade, no int not null,
  cutoff text not null, created_at timestamptz not null default now(), created_by uuid references profiles(id), created_by_name text, source_import text, schedule_rev int, budget_rev text,
  months jsonb not null, fac bigint not null, actual bigint not null, remaining bigint not null, budget bigint, headroom bigint, status text not null, comments text,
  state text not null default 'Draft' check (state in ('Draft','Reviewed','Published','Discarded')),
  reviewed_by text, reviewed_at timestamptz, review_note text, published_by text, published_at timestamptz, discarded_by text, discarded_at timestamptz, discard_note text,
  unique (project_id, no));
create table if not exists co_reviews (id text primary key default 'CR' || replace(uuid_generate_v4()::text, '-', ''), project_id text not null references projects(id) on delete cascade,
  version_id text references co_versions(id), cutoff text, fac bigint, budget bigint, actual bigint, overrun bigint, decision text not null, action text not null, "by" text, by_role text, at timestamptz not null default now());
create table if not exists co_scenarios (id text primary key default 'CS' || replace(uuid_generate_v4()::text, '-', ''), project_id text not null references projects(id) on delete cascade,
  name text not null, kind text not null default 'User-defined', shift_days int not null check (shift_days between -365 and 365), value_pct numeric(6,2) not null check (value_pct between -50 and 50),
  note text, "by" text, at timestamptz not null default now());
create table if not exists co_maps (name text primary key, map jsonb not null, "by" text, at timestamptz not null default now());
create table if not exists co_audit (id bigserial primary key, project_id text not null references projects(id) on delete cascade, action text not null, note text, detail jsonb,
  by_user uuid references profiles(id), by_name text, by_role text, at_time timestamptz not null default now());

-- read rules: cost-figure viewers, on the projects in their access
do $$
declare t text;
begin
  foreach t in array array['co_actuals','co_opening','co_po_terms','co_other_lines','co_versions','co_reviews','co_scenarios','co_audit'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists %I on %I', t || '_read', t);
    execute format('create policy %I on %I for select using (can_see(project_id) and pt_money_ok())', t || '_read', t);
    execute format('revoke all on %I from anon', t);
    execute format('revoke insert, update, delete, truncate on %I from authenticated', t);
    execute format('grant select on %I to authenticated', t);
  end loop;
end $$;
alter table co_batches enable row level security;
drop policy if exists co_batches_read on co_batches;
create policy co_batches_read on co_batches for select using (pt_money_ok() and exists (select 1 from unnest(projects) p where can_see(p)));
alter table co_maps enable row level security;
drop policy if exists co_maps_read on co_maps;
create policy co_maps_read on co_maps for select using (role_of(auth.uid()) = 'sa' or pt_is_coord(auth.uid()));
revoke all on co_batches, co_maps from anon;
revoke insert, update, delete, truncate on co_batches, co_maps from authenticated;
grant select on co_batches, co_maps to authenticated;
-- what was recorded stays: the audit never changes; an actual only gets its superseded_by once; a published version is frozen
drop trigger if exists trg_co_audit_append on co_audit;
create trigger trg_co_audit_append before update or delete on co_audit for each row execute function pt_append_only();
create or replace function pt_co_actual_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'Finance actuals are never deleted: import a correction'; end if;
  if old.superseded_by is not null or new.superseded_by is null or (to_jsonb(new) - 'superseded_by') <> (to_jsonb(old) - 'superseded_by') then
    raise exception 'A Finance actual is never changed: import a correction'; end if;
  return new;
end $$;
drop trigger if exists trg_co_actual_guard on co_actuals;
create trigger trg_co_actual_guard before update or delete on co_actuals for each row execute function pt_co_actual_guard();
create or replace function pt_co_version_guard() returns trigger language plpgsql as $$
begin
  if old.state = 'Published' then raise exception 'A published forecast version is kept as it is: create a new version'; end if;
  if tg_op = 'UPDATE' and (new.months <> old.months or new.fac <> old.fac or new.actual <> old.actual or new.cutoff <> old.cutoff) then raise exception 'The figures of a version do not change'; end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
drop trigger if exists trg_co_version_guard on co_versions;
create trigger trg_co_version_guard before update or delete on co_versions for each row execute function pt_co_version_guard();

-- Finance imports are logged in import_batches as kind 'cashout' (the kind list is extended, whatever it holds today)
do $$
declare d text;
begin
  select pg_get_constraintdef(oid) into d from pg_constraint where conname = 'import_batches_kind_check' and conrelid = 'public.import_batches'::regclass;
  if d is not null and position('''cashout''' in d) = 0 then
    execute 'alter table import_batches drop constraint import_batches_kind_check';
    execute 'alter table import_batches add constraint import_batches_kind_check ' || regexp_replace(d, '\]', ', ''cashout''::text]');
  end if;
end $$;

-- ------------------------------------------------------------------ 2. the right and the screen
do $$
declare cur text[] := pt_rights(); scr text[] := pt_screens(); src text;
begin
  if not ('cashout.keep' = any(cur)) then
    execute format('create or replace function pt_rights() returns text[] language sql immutable as $f$ select %L::text[] $f$', (cur || 'cashout.keep'::text)::text); end if;
  if not ('cout' = any(scr)) then
    execute format('create or replace function pt_screens() returns text[] language sql immutable as $f$ select %L::text[] $f$', (scr || 'cout'::text)::text); end if;
  select prosrc into src from pg_proc where proname = 'pt_right_default' and pronamespace = 'public'::regnamespace and pronargs = 2;
  if position('cashout.keep' in src) = 0 then
    if position('else false end' in src) = 0 then raise exception 'pt_right_default does not have the expected shape; add cashout.keep by hand'; end if;
    src := regexp_replace(src, 'else false end', E'when ''cashout.keep''            then base = ''costing''\n    else false end');
    execute format('create or replace function pt_right_default(base text, k text) returns boolean language sql immutable as $f$%s$f$', src);
  end if;
end $$;

-- ------------------------------------------------------------------ 3. the rules
create or replace function pt_co_keeper(u uuid, pid text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(user_sees(u, pid) and pt_right(u, 'money.view') and pt_right(u, 'cashout.keep', pt_is_head(u) or pt_is_coord(u)), false) $$;
create or replace function pt_co_uploader(u uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) = 'sa' or pt_is_coord(u), false) $$;
create or replace function pt_co_approver(u uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) = 'sa' or pt_is_head(u) or pt_is_coord(u), false) $$;
create or replace function pt_co_publisher(u uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) = 'sa' or pt_is_head(u), false) $$;
create or replace function pt_co_log(pid text, a text, note text, detail jsonb) returns void language sql security definer set search_path = public as $$
  insert into co_audit (project_id, action, note, detail, by_user, by_name, by_role) values (pid, a, note, detail, auth.uid(), name_of(auth.uid()), role_of(auth.uid())) $$;
create or replace function pt_co_num(t text) returns numeric language sql immutable as $$
  select case when regexp_replace(coalesce(t, ''), '(?i)sar|,|\s', '', 'g') ~ '^-?[0-9]+(\.[0-9]+)?$' then round(regexp_replace(t, '(?i)sar|,|\s', '', 'g')::numeric, 2) end $$;
create or replace function pt_co_pay_date(m jsonb) returns date language sql immutable as $$
  select coalesce(pt_date(m ->> 'pay_date_override'), coalesce(pt_date(m ->> 'invoice_date'), pt_date(m ->> 'planned_date')) + coalesce(nullif(m ->> 'pay_days', '')::int, 0)) $$;

-- one PO milestone, cleaned and checked (the app's coMsClean)
create or replace function pt_co_ms(m jsonb, value numeric) returns jsonb language plpgsql stable as $$
declare o jsonb; nm text := left(btrim(coalesce(m ->> 'name', '')), 120); basis text := case when m ->> 'basis' = 'fixed' then 'fixed' else 'pct' end;
        pct numeric := pt_co_num(m ->> 'pct'); amt numeric := pt_co_num(m ->> 'amount'); ded numeric := pt_co_num(m ->> 'deduction'); gross numeric; st text := coalesce(nullif(m ->> 'status', ''), 'Planned');
        days int; k text;
begin
  if nm = '' then raise exception 'Every milestone needs a name'; end if;
  if coalesce(m ->> 'kind', 'Custom') not in ('Advance payment','Drawing / document approval','Material procurement / manufacturing progress','Factory Acceptance Test (FAT)','Dispatch / shipment','Delivery to site',
     'Installation','Testing and commissioning','Taking-over / acceptance','Retention release','Final payment','Progress payment','Custom') then raise exception '%: choose its payment term', nm; end if;
  if st not in ('Planned','Invoiced','Paid','On hold','Cancelled') then raise exception '%: unknown status', nm; end if;
  if basis = 'pct' and (pct is null or not (pct > 0 and pct <= 100)) then raise exception '%: the percentage of the PO value is between 0 and 100', nm; end if;
  if basis = 'fixed' and (amt is null or not (amt > 0)) then raise exception '%: the fixed amount must be more than 0', nm; end if;
  foreach k in array array['planned_date','invoice_date','pay_date_override','paid_date'] loop
    if nullif(m ->> k, '') is not null and (m ->> k !~ '^\d{4}-\d{2}-\d{2}$' or pt_date(m ->> k) is null) then raise exception '%: a date is not valid', nm; end if; end loop;
  if coalesce(m ->> 'pay_days', '') !~ '^\d{0,3}$' then raise exception '%: contractual payment days are a whole number from 0 to 365', nm; end if;
  days := coalesce(nullif(m ->> 'pay_days', '')::int, 0); if days > 365 then raise exception '%: contractual payment days are a whole number from 0 to 365', nm; end if;
  gross := case when basis = 'fixed' then amt else round(value * pct / 100, 2) end;
  if ded is not null and (ded < 0 or ded >= gross) then raise exception '%: the retention or deduction must be positive and less than the amount', nm; end if;
  if st = 'Paid' then
    if pt_date(m ->> 'paid_date') is null then raise exception '%: a paid milestone needs its payment date', nm; end if;
    if pt_date(m ->> 'paid_date') > current_date then raise exception '%: the payment date cannot be in the future', nm; end if;
    if nullif(btrim(coalesce(m ->> 'evidence', '')), '') is null then raise exception '%: a paid milestone needs its evidence (Finance payment reference)', nm; end if;
    if coalesce(pt_co_num(m ->> 'paid_amount'), gross - coalesce(ded, 0)) <= 0 then raise exception '%: the paid amount must be more than 0', nm; end if;
  end if;
  o := jsonb_build_object('id', coalesce(nullif(m ->> 'id', ''), 'MS' || replace(uuid_generate_v4()::text, '-', '')), 'name', nm, 'kind', coalesce(m ->> 'kind', 'Custom'), 'basis', basis,
    'pct', case when basis = 'pct' then pct end, 'amount', case when basis = 'fixed' then amt end, 'event', nullif(left(btrim(coalesce(m ->> 'event', '')), 120), ''),
    'planned_date', nullif(m ->> 'planned_date', ''), 'invoice_date', nullif(m ->> 'invoice_date', ''), 'pay_days', days, 'pay_date_override', nullif(m ->> 'pay_date_override', ''),
    'deduction', ded, 'status', st, 'paid_date', case when st = 'Paid' then m ->> 'paid_date' end,
    'paid_amount', case when st = 'Paid' then coalesce(pt_co_num(m ->> 'paid_amount'), gross - coalesce(ded, 0)) end,
    'evidence', nullif(left(btrim(coalesce(m ->> 'evidence', '')), 200), ''), 'notes', nullif(left(btrim(coalesce(m ->> 'notes', '')), 1000), ''),
    'approval', 'Draft', 'approved_by', null, 'approved_at', null, 'base_pay_date', null);   -- v3.26.1: approval comes from the stored milestone, never from the client
  return o;
end $$;

-- p: {kind, args}; the kinds and their arguments are the app's coAct()
create or replace function cashout_act(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); kind text := p ->> 'kind'; a jsonb := coalesce(p -> 'args', '[]'::jsonb); x jsonb; o jsonb; r record; pid text; s jsonb; old jsonb; ms jsonb; m jsonb; om jsonb;
        val numeric; note text; n int := 0; bid text; acc jsonb := '[]'::jsonb; rej jsonb := '[]'::jsonb; err text; per text; cur record; added int := 0; restated int := 0; same int := 0; v co_versions; vid text;
        po record; reason text; hit boolean; keys text[] := array['name','kind','basis','pct','amount','planned_date','invoice_date','pay_days','pay_date_override','deduction','status','paid_date','paid_amount'];
begin
  if me is null or role_of(me) is null then raise exception 'Sign in first' using errcode = '42501'; end if;

  if kind = 'fin' then
    x := a -> 0; o := coalesce(a -> 1, '{}'::jsonb);
    if not pt_co_uploader(me) then raise exception 'Only the super admin or the Head Office cost control coordinator imports Finance cash-out' using errcode = '42501'; end if;
    if coalesce(x ->> 'cutoff', '') !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Choose the reporting cutoff'; end if;
    if jsonb_typeof(x -> 'projects') is distinct from 'array' or jsonb_array_length(x -> 'projects') = 0 then raise exception 'Choose the projects the file covers'; end if;
    if exists (select 1 from co_batches where file_hash = x ->> 'hash' and result = 'Committed') then raise exception 'This file was already imported; nothing changed.'; end if;
    if jsonb_array_length(coalesce(x -> 'rows', '[]'::jsonb)) = 0 or jsonb_array_length(x -> 'rows') > 5000 then raise exception 'The file has no rows, or more than 5000'; end if;
    for m in select * from jsonb_array_elements(x -> 'rows') loop
      n := n + 1; err := null; pid := m ->> 'project_id'; per := m ->> 'period'; val := pt_co_num(m ->> 'cum');
      if pid is null or not exists (select 1 from projects where id = pid) then err := 'unknown project';
      elsif not user_sees(me, pid) then err := 'not in your access';
      elsif not (x -> 'projects') ? pid then err := 'not one of the projects chosen for this file';
      elsif coalesce(per, '') !~ '^\d{4}-(0[1-9]|1[0-2])$' then err := 'reporting period is not a month';
      elsif per > x ->> 'cutoff' then err := 'after the reporting cutoff';
      elsif val is null then err := 'cumulative actual cash-out is not a number';
      elsif val < 0 then err := 'cumulative actual cash-out cannot be negative';
      elsif upper(coalesce(nullif(btrim(m ->> 'currency'), ''), 'SAR')) <> 'SAR' then err := 'the project currency is SAR and no exchange rate is configured';
      elsif exists (select 1 from jsonb_array_elements(acc) y where y ->> 'project_id' = pid and y ->> 'period' = per) then err := 'the same project and period appear twice in the file';
      end if;
      if err is null then acc := acc || jsonb_build_array(m || jsonb_build_object('cum', val));
      else rej := rej || jsonb_build_array(jsonb_build_object('row', coalesce(nullif(m ->> 'row', '')::int, n), 'project', m ->> 'code', 'error', err)); end if;
    end loop;
    if jsonb_array_length(rej) > 0 and not coalesce((o ->> 'ack')::boolean, false) then raise exception 'Tick the box to confirm the refused rows first.'; end if;
    for m in select * from jsonb_array_elements(acc) loop
      select * into cur from co_actuals where project_id = m ->> 'project_id' and period = m ->> 'period' and superseded_by is null;
      if found and cur.cum = (m ->> 'cum')::numeric then same := same + 1; elsif found then restated := restated + 1; else added := added + 1; end if;
    end loop;
    if restated > 0 and (not coalesce((o ->> 'correct')::boolean, false) or length(btrim(coalesce(o ->> 'reason', ''))) < 5) then
      raise exception '% period(s) were already imported with another amount. Tick "Record them as corrections" and give the reason.', restated; end if;
    if added + restated = 0 then raise exception 'Nothing new in this file: every valid row is already imported with the same amount.'; end if;
    bid := 'FCO-' || lpad(((select count(*) from co_batches) + 1)::text, 4, '0');
    insert into co_batches (id, file_name, file_hash, sheet, cutoff, projects, rows_total, added, restated, unchanged, refused, "by", by_name, reason, rejected)
    values (bid, left(x ->> 'file', 200), x ->> 'hash', null, x ->> 'cutoff', array(select jsonb_array_elements_text(x -> 'projects')), n, added, restated, same, jsonb_array_length(rej), me, name_of(me),
            case when restated > 0 then btrim(o ->> 'reason') end, rej);
    for m in select * from jsonb_array_elements(acc) loop
      select * into cur from co_actuals where project_id = m ->> 'project_id' and period = m ->> 'period' and superseded_by is null; hit := found;
      if hit and cur.cum = (m ->> 'cum')::numeric then continue; end if;
      vid := 'CA' || replace(uuid_generate_v4()::text, '-', '');
      if hit then update co_actuals set superseded_by = vid where id = cur.id; end if;
      insert into co_actuals (id, project_id, period, cum, remarks, source_file, batch_id, created_by, created_by_name, supersedes, reason)
      values (vid, m ->> 'project_id', m ->> 'period', (m ->> 'cum')::numeric, nullif(left(m ->> 'remarks', 300), ''), left(x ->> 'file', 200), bid, me, name_of(me),
              case when hit then cur.id end, case when hit then btrim(o ->> 'reason') end);
      if hit then perform pt_co_log(m ->> 'project_id', 'Actual restated', o ->> 'reason', jsonb_build_object('period', m ->> 'period', 'from', cur.cum, 'to', m ->> 'cum', 'batch', bid)); end if;
    end loop;
    for pid in select distinct y ->> 'project_id' from jsonb_array_elements(acc) y loop perform pt_co_log(pid, 'Finance cash-out imported', null, jsonb_build_object('batch', bid, 'file', x ->> 'file', 'cutoff', x ->> 'cutoff')); end loop;
    insert into import_batches (project_id, kind, file_name, file_hash, rows_total, rows_accepted, rows_rejected, recon_status, recon_accepted_by, detail, by_user)
    values (case when jsonb_array_length(x -> 'projects') = 1 then x -> 'projects' ->> 0 end, 'cashout', left(x ->> 'file', 200), x ->> 'hash', n, jsonb_array_length(acc), jsonb_array_length(rej),
            case when jsonb_array_length(rej) > 0 then 'Accepted with difference' end, case when jsonb_array_length(rej) > 0 then me end, jsonb_build_object('batch', bid, 'rejected', rej), me);
    if nullif(btrim(coalesce(o ->> 'saveMap', '')), '') is not null and jsonb_typeof(x -> 'map') = 'object' then
      insert into co_maps (name, map, "by") values (left(btrim(o ->> 'saveMap'), 60), x -> 'map', name_of(me)) on conflict (name) do update set map = excluded.map, "by" = excluded."by", at = now(); end if;
    return (select to_jsonb(b) from co_batches b where id = bid);

  elsif kind = 'opening' then
    pid := a ->> 0; note := btrim(coalesce(a ->> 2, ''));
    if not pt_co_uploader(me) then raise exception 'Only the super admin or the Head Office cost control coordinator sets the opening balance' using errcode = '42501'; end if;
    if not user_sees(me, pid) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
    if note = '' then raise exception 'Say how the zero opening balance was verified'; end if;
    insert into co_opening (project_id, zero, note, "by") values (pid, (a ->> 1)::boolean, note, name_of(me))
    on conflict (project_id) do update set zero = excluded.zero, note = excluded.note, "by" = excluded."by", at = now();
    perform pt_co_log(pid, case when (a ->> 1)::boolean then 'Zero opening balance verified' else 'Zero opening balance withdrawn' end, note, null);
    return jsonb_build_object('ok', true);

  elsif kind in ('posave','poapprove','porevise') then
    select * into po from purchase_orders where id = (a ->> 0)::uuid;
    if not found then raise exception 'Unknown purchase order'; end if;
    pid := po.project_id; note := btrim(coalesce(case when kind = 'posave' then a ->> 2 else a ->> 1 end, ''));
    select state into old from co_po_terms where po_id = po.id;
    old := coalesce(old, jsonb_build_object('status', 'Open', 'milestones', '[]'::jsonb, 'revisions', '[]'::jsonb, 'orig_value', po.po_value, 'last_value', po.po_value, 'currency', 'SAR'));
    if kind = 'poapprove' then
      if not (pt_co_approver(me) and user_sees(me, pid)) then raise exception 'Only the costing coordinator, the Head of Planning and Cost Control or a super admin approves payment terms' using errcode = '42501'; end if;
      if coalesce(old ->> 'status', 'Open') <> 'Cancelled' and abs((select coalesce(sum(case when m2 ->> 'basis' = 'fixed' then (m2 ->> 'amount')::numeric else round(po.po_value * (m2 ->> 'pct')::numeric / 100, 2) end), 0)
            from jsonb_array_elements(old -> 'milestones') m2 where m2 ->> 'status' <> 'Cancelled') - po.po_value) > 0.01 then raise exception 'Fix these first: the milestones must total 100%% of the PO value'; end if;
      if exists (select 1 from jsonb_array_elements(old -> 'milestones') m2 where m2 ->> 'status' not in ('Paid','Cancelled') and pt_co_pay_date(m2) is null) then raise exception 'Fix these first: every open milestone needs its expected payment date'; end if;
      ms := '[]'::jsonb; n := 0;
      for m in select * from jsonb_array_elements(old -> 'milestones') loop
        if coalesce(m ->> 'approval', 'Draft') <> 'Approved' then n := n + 1;
          m := m || jsonb_build_object('approval', 'Approved', 'approved_by', name_of(me), 'approved_at', now(), 'base_pay_date', coalesce(m ->> 'base_pay_date', pt_co_pay_date(m)::text)); end if;
        ms := ms || jsonb_build_array(m); end loop;
      if n = 0 then raise exception 'Nothing is waiting for approval'; end if;
      s := old || jsonb_build_object('milestones', ms, 'last_value', po.po_value);
      perform pt_co_log(pid, 'Payment terms approved', nullif(note, ''), jsonb_build_object('po', po.po_no, 'milestones', n));
    else
      if not pt_co_keeper(me, pid) then raise exception 'Only the costing engineers of this project, the costing coordinator, the Head of Planning and Cost Control or a super admin change its payment terms' using errcode = '42501'; end if;
      if kind = 'porevise' then
        o := a -> 1; val := pt_co_num(o ->> 'value'); reason := btrim(coalesce(o ->> 'reason', ''));
        if not (val > 0) then raise exception 'The revised PO value must be more than 0'; end if;
        if nullif(btrim(coalesce(o ->> 'ref', '')), '') is null then raise exception 'Give the reference of the approved PO revision'; end if;
        if length(reason) < 5 then raise exception 'Say why the PO value changed'; end if;
        if pt_date(o ->> 'date') is null or pt_date(o ->> 'date') > current_date then raise exception 'Give the date of the revision (not in the future)'; end if;
        if val = po.po_value then raise exception 'The value is the same as now'; end if;
        update purchase_orders set po_value = val where id = po.id;
        s := old || jsonb_build_object('orig_value', coalesce(old -> 'orig_value', to_jsonb(po.po_value)), 'last_value', val,
          'revisions', coalesce(old -> 'revisions', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('from', po.po_value, 'to', val, 'ref', btrim(o ->> 'ref'), 'reason', reason, 'date', o ->> 'date', 'by', name_of(me), 'at', now())));
        perform pt_co_log(pid, 'PO revised', reason, jsonb_build_object('po', po.po_no, 'from', po.po_value, 'to', val, 'ref', o ->> 'ref'));
      else
        o := a -> 1; ms := '[]'::jsonb;
        if coalesce(o ->> 'status', 'Open') not in ('Open','Completed','Cancelled') then raise exception 'Unknown PO status'; end if;
        if o ->> 'status' = 'Cancelled' and coalesce(old ->> 'status', 'Open') <> 'Cancelled' and length(btrim(coalesce(o ->> 'cancel_reason', ''))) < 5 then raise exception 'Say why the PO is cancelled'; end if;
        for m in select * from jsonb_array_elements(coalesce(o -> 'milestones', '[]'::jsonb)) loop
          m := pt_co_ms(m, po.po_value);
          select y into om from jsonb_array_elements(old -> 'milestones') y where y ->> 'id' = m ->> 'id';
          if om is not null and om ->> 'base_pay_date' is not null then m := m || jsonb_build_object('base_pay_date', om ->> 'base_pay_date'); end if;
          if om is null or exists (select 1 from unnest(keys) k where k not in ('status','paid_date','paid_amount') and (m -> k) is distinct from (om -> k)) then
            m := m || jsonb_build_object('approval', 'Draft', 'approved_by', null, 'approved_at', null);
          else m := m || jsonb_build_object('approval', coalesce(om ->> 'approval', 'Draft'), 'approved_by', om -> 'approved_by', 'approved_at', om -> 'approved_at'); end if;
          ms := ms || jsonb_build_array(m); om := null;
        end loop;
        for om in select * from jsonb_array_elements(old -> 'milestones') loop
          if om ->> 'status' = 'Paid' then
            select y into m from jsonb_array_elements(ms) y where y ->> 'id' = om ->> 'id';
            if m is null then raise exception '% is paid and cannot be removed', om ->> 'name'; end if;
            if exists (select 1 from unnest(array['basis','pct','amount','deduction','paid_date','paid_amount','status']) k where (m -> k) is distinct from (om -> k)) then
              if not pt_co_approver(me) then raise exception '% is paid: what was paid cannot be changed. Ask the costing coordinator, the Head of Planning and Cost Control or a super admin', om ->> 'name'; end if;
              if length(note) < 5 then raise exception 'Say why the paid milestone % is changed', om ->> 'name'; end if; end if;
            m := null; end if;
        end loop;
        s := old || jsonb_build_object('status', coalesce(o ->> 'status', 'Open'), 'delivery_date', nullif(o ->> 'delivery_date', ''), 'terms', nullif(left(btrim(coalesce(o ->> 'terms', '')), 500), ''),
          'cancel_reason', case when o ->> 'status' = 'Cancelled' then coalesce(nullif(btrim(o ->> 'cancel_reason'), ''), old ->> 'cancel_reason') end, 'currency', 'SAR', 'milestones', ms,
          'orig_value', coalesce(old -> 'orig_value', to_jsonb(po.po_value)), 'last_value', po.po_value, 'updated_by', name_of(me), 'updated_at', now());
        perform pt_co_log(pid, 'Payment terms changed', nullif(note, ''), jsonb_build_object('po', po.po_no, 'status', s ->> 'status', 'milestones', jsonb_array_length(ms)));
      end if;
    end if;
    insert into co_po_terms (po_id, project_id, state, updated_by) values (po.id, pid, s, me) on conflict (po_id) do update set state = excluded.state, updated_by = excluded.updated_by, updated_at = now();
    return s;

  elsif kind in ('other','otherdel') then
    pid := a ->> 0;
    if not pt_co_keeper(me, pid) then raise exception 'Only the people who keep this project''s cash-out forecast change its other cash-out lines' using errcode = '42501'; end if;
    if kind = 'otherdel' then
      if length(btrim(coalesce(a ->> 2, ''))) < 5 then raise exception 'Say why the line is removed'; end if;
      update co_other_lines set removed_at = now(), removed_by = name_of(me), remove_note = btrim(a ->> 2) where id = a ->> 1 and project_id = pid and removed_at is null;
      if not found then raise exception 'Unknown line'; end if;
      perform pt_co_log(pid, 'Other cash-out line removed', a ->> 2, jsonb_build_object('line', a ->> 1));
      return jsonb_build_object('ok', true);
    end if;
    o := a -> 1;
    if nullif(btrim(coalesce(o ->> 'name', '')), '') is null then raise exception 'Name the cash-out line'; end if;
    if not coalesce((o ->> 'not_in_po')::boolean, false) then raise exception 'Confirm the line is not covered by a purchase order, so it is not counted twice'; end if;
    if coalesce(pt_co_num(nullif(o ->> 'paid_to_date', '')), 0) < 0 or coalesce(pt_co_num(nullif(o ->> 'remaining', '')), 0) < 0
       or (nullif(o ->> 'paid_to_date', '') is not null and pt_co_num(o ->> 'paid_to_date') is null) or (nullif(o ->> 'remaining', '') is not null and pt_co_num(o ->> 'remaining') is null) then
      raise exception 'Paid to date and remaining are amounts of 0 or more'; end if;
    if coalesce(pt_co_num(nullif(o ->> 'paid_to_date', '')), 0) > 0 and nullif(btrim(coalesce(o ->> 'paid_ref', '')), '') is null then raise exception 'Give the Finance reference for the paid to date'; end if;
    if coalesce(pt_co_num(nullif(o ->> 'remaining', '')), 0) > 0 and (coalesce(o ->> 'from', '') !~ '^\d{4}-(0[1-9]|1[0-2])$' or coalesce(o ->> 'to', '') !~ '^\d{4}-(0[1-9]|1[0-2])$' or o ->> 'to' < o ->> 'from') then
      raise exception 'Give the months the remaining amount is paid in (from, to)'; end if;
    if nullif(o ->> 'id', '') is not null and exists (select 1 from co_other_lines where id = o ->> 'id' and project_id = pid) then
      update co_other_lines set name = left(btrim(o ->> 'name'), 120), category = nullif(left(btrim(coalesce(o ->> 'category', '')), 60), ''), note = nullif(left(btrim(coalesce(o ->> 'note', '')), 500), ''),
        paid_to_date = coalesce(pt_co_num(nullif(o ->> 'paid_to_date', '')), 0), paid_ref = nullif(left(btrim(coalesce(o ->> 'paid_ref', '')), 200), ''), remaining = coalesce(pt_co_num(nullif(o ->> 'remaining', '')), 0),
        "from" = nullif(o ->> 'from', ''), "to" = nullif(o ->> 'to', ''), updated_by = name_of(me), updated_at = now() where id = o ->> 'id';
      perform pt_co_log(pid, 'Other cash-out line changed', null, o);
    else
      insert into co_other_lines (project_id, name, category, note, paid_to_date, paid_ref, remaining, "from", "to", not_in_po, base_total, base_from, base_to, created_by)
      values (pid, left(btrim(o ->> 'name'), 120), nullif(left(btrim(coalesce(o ->> 'category', '')), 60), ''), nullif(left(btrim(coalesce(o ->> 'note', '')), 500), ''),
        coalesce(pt_co_num(nullif(o ->> 'paid_to_date', '')), 0), nullif(left(btrim(coalesce(o ->> 'paid_ref', '')), 200), ''), coalesce(pt_co_num(nullif(o ->> 'remaining', '')), 0),
        nullif(o ->> 'from', ''), nullif(o ->> 'to', ''), true, coalesce(pt_co_num(nullif(o ->> 'paid_to_date', '')), 0) + coalesce(pt_co_num(nullif(o ->> 'remaining', '')), 0),
        coalesce(nullif(o ->> 'from', ''), to_char(current_date, 'YYYY-MM')), coalesce(nullif(o ->> 'to', ''), nullif(o ->> 'from', ''), to_char(current_date, 'YYYY-MM')), name_of(me));
      perform pt_co_log(pid, 'Other cash-out line added', null, o);
    end if;
    return jsonb_build_object('ok', true);

  elsif kind = 'ver' then
    o := a -> 0;
    if o ->> 'action' = 'create' then
      pid := o ->> 'project_id';
      if not (pt_co_keeper(me, pid) or (pt_co_approver(me) and user_sees(me, pid))) then raise exception 'Only the people who keep this project''s cash-out forecast create versions' using errcode = '42501'; end if;
      if jsonb_typeof(o -> 'snapshot' -> 'months') is distinct from 'array' then raise exception 'The version needs the forecast figures'; end if;
      insert into co_versions (project_id, no, cutoff, created_by, created_by_name, source_import, schedule_rev, budget_rev, months, fac, actual, remaining, budget, headroom, status, comments)
      select pid, coalesce((select max(no) from co_versions where project_id = pid), 0) + 1, o -> 'snapshot' ->> 'cutoff', me, name_of(me), o -> 'snapshot' ->> 'source_import',
        nullif(o -> 'snapshot' ->> 'schedule_rev', '')::int, o -> 'snapshot' ->> 'budget_rev', o -> 'snapshot' -> 'months', (o -> 'snapshot' ->> 'fac')::bigint, (o -> 'snapshot' ->> 'actual')::bigint,
        (o -> 'snapshot' ->> 'remaining')::bigint, nullif(o -> 'snapshot' ->> 'budget', '')::bigint, nullif(o -> 'snapshot' ->> 'headroom', '')::bigint, o -> 'snapshot' ->> 'status', nullif(left(btrim(coalesce(o ->> 'comments', '')), 1000), '')
      returning * into v;
      perform pt_co_log(pid, 'Forecast version created', v.comments, jsonb_build_object('version', v.no, 'fac', v.fac, 'status', v.status));
      return to_jsonb(v);
    end if;
    select * into v from co_versions where id = o ->> 'id' for update;
    if not found then raise exception 'Unknown forecast version'; end if;
    if not user_sees(me, v.project_id) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
    note := nullif(btrim(coalesce(o ->> 'note', '')), '');
    if o ->> 'action' = 'review' then
      if not pt_co_approver(me) then raise exception 'Only the costing coordinator, the Head of Planning and Cost Control or a super admin reviews forecast versions' using errcode = '42501'; end if;
      if v.state <> 'Draft' then raise exception 'Only a draft is reviewed'; end if;
      if v.created_by = me then raise exception 'You created this version, so someone else must review it' using errcode = '42501'; end if;
      update co_versions set state = 'Reviewed', reviewed_by = name_of(me), reviewed_at = now(), review_note = note where id = v.id returning * into v;
    elsif o ->> 'action' = 'publish' then
      if not pt_co_publisher(me) then raise exception 'Only the Head of Planning and Cost Control or a super admin publishes forecast versions' using errcode = '42501'; end if;
      if v.state <> 'Reviewed' then raise exception 'Only a reviewed version is published'; end if;
      if v.budget is not null and (v.fac > v.budget or v.actual > v.budget) and not exists (select 1 from co_reviews where version_id = v.id) then
        raise exception 'This forecast is over the approved budget: record the management review and its action first'; end if;
      update co_versions set state = 'Published', published_by = name_of(me), published_at = now() where id = v.id returning * into v;
    elsif o ->> 'action' = 'discard' then
      if v.state = 'Published' then raise exception 'A published version is kept'; end if;
      if not (v.created_by = me or role_of(me) = 'sa') then raise exception 'Only its author or a super admin discards a version' using errcode = '42501'; end if;
      if length(coalesce(note, '')) < 5 then raise exception 'Say why the version is discarded'; end if;
      update co_versions set state = 'Discarded', discarded_by = name_of(me), discarded_at = now(), discard_note = note where id = v.id returning * into v;
    else raise exception 'Unknown action'; end if;
    perform pt_co_log(v.project_id, 'Forecast version ' || lower(v.state), note, jsonb_build_object('version', v.no));
    return to_jsonb(v);

  elsif kind = 'review' then
    o := a -> 0; pid := o ->> 'project_id';
    if not pt_co_publisher(me) then raise exception 'Only the Head of Planning and Cost Control or a super admin records the management review of an overrun' using errcode = '42501'; end if;
    if not user_sees(me, pid) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
    if coalesce(o ->> 'decision', '') not in ('Corrective action agreed','Budget revision to be requested (cost report workflow)','Accepted for monitoring','Data to be corrected (verified information)') then raise exception 'Choose the decision'; end if;
    if length(btrim(coalesce(o ->> 'action', ''))) < 15 then raise exception 'Describe the action decided (at least a sentence)'; end if;
    if nullif(o ->> 'version_id', '') is not null then
      select * into v from co_versions where id = o ->> 'version_id' and project_id = pid;
      if not found then raise exception 'Unknown forecast version'; end if;
      if v.budget is null then raise exception 'The project has no approved budget (Budget Not Configured)'; end if;
      if not (v.fac > v.budget or v.actual > v.budget) then raise exception 'This forecast is within the approved budget: no overrun to review'; end if;
      insert into co_reviews (project_id, version_id, cutoff, fac, budget, actual, overrun, decision, action, "by", by_role)
      values (pid, v.id, v.cutoff, v.fac, v.budget, v.actual, v.fac - v.budget, o ->> 'decision', left(btrim(o ->> 'action'), 2000), name_of(me), role_of(me));
    else
      if jsonb_typeof(o -> 'snapshot') <> 'object' or nullif(o -> 'snapshot' ->> 'budget', '') is null then raise exception 'The project has no approved budget (Budget Not Configured)'; end if;
      if not ((o -> 'snapshot' ->> 'fac')::bigint > (o -> 'snapshot' ->> 'budget')::bigint or (o -> 'snapshot' ->> 'actual')::bigint > (o -> 'snapshot' ->> 'budget')::bigint) then
        raise exception 'This forecast is within the approved budget: no overrun to review'; end if;
      insert into co_reviews (project_id, cutoff, fac, budget, actual, overrun, decision, action, "by", by_role)
      values (pid, o -> 'snapshot' ->> 'cutoff', (o -> 'snapshot' ->> 'fac')::bigint, (o -> 'snapshot' ->> 'budget')::bigint, (o -> 'snapshot' ->> 'actual')::bigint,
              (o -> 'snapshot' ->> 'fac')::bigint - (o -> 'snapshot' ->> 'budget')::bigint, o ->> 'decision', left(btrim(o ->> 'action'), 2000), name_of(me), role_of(me));
    end if;
    perform pt_co_log(pid, 'Overrun reviewed', o ->> 'action', jsonb_build_object('decision', o ->> 'decision'));
    return jsonb_build_object('ok', true);

  elsif kind in ('scen','scendel') then
    pid := a ->> 0;
    if not pt_co_keeper(me, pid) then raise exception 'Only the people who keep this project''s cash-out forecast change scenarios' using errcode = '42501'; end if;
    if kind = 'scendel' then delete from co_scenarios where id = a ->> 1 and project_id = pid; if not found then raise exception 'Unknown scenario'; end if;
      perform pt_co_log(pid, 'Scenario removed', null, jsonb_build_object('scenario', a ->> 1)); return jsonb_build_object('ok', true); end if;
    o := a -> 1;
    if nullif(btrim(coalesce(o ->> 'name', '')), '') is null then raise exception 'Name the scenario'; end if;
    if coalesce(nullif(o ->> 'shift_days', ''), '0') !~ '^-?\d{1,3}$' or abs(coalesce(nullif(o ->> 'shift_days', ''), '0')::int) > 365 then raise exception 'The date shift is a whole number of days, −365 to 365'; end if;
    if pt_co_num(coalesce(nullif(o ->> 'value_pct', ''), '0')) is null or pt_co_num(coalesce(nullif(o ->> 'value_pct', ''), '0')) not between -50 and 50 then raise exception 'The change to the remaining obligations is between −50%% and +50%%'; end if;
    insert into co_scenarios (project_id, name, shift_days, value_pct, note, "by") values (pid, left(btrim(o ->> 'name'), 60), coalesce(nullif(o ->> 'shift_days', ''), '0')::int,
      pt_co_num(coalesce(nullif(o ->> 'value_pct', ''), '0')), nullif(left(btrim(coalesce(o ->> 'note', '')), 300), ''), name_of(me));
    perform pt_co_log(pid, 'Scenario added', o ->> 'note', o);
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'Unknown action %', coalesce(kind, '');
end $$;

-- the app asks this to know v27 is in (schema-rollback-v27.sql removes it)
create or replace function cashout_features() returns jsonb language sql immutable as $$ select '{"version":27,"cashout":true}'::jsonb $$;

revoke execute on function pt_co_keeper(uuid, text), pt_co_uploader(uuid), pt_co_approver(uuid), pt_co_publisher(uuid), pt_co_log(text, text, text, jsonb), pt_co_num(text), pt_co_pay_date(jsonb),
  pt_co_ms(jsonb, numeric), cashout_act(jsonb), cashout_features() from public, anon;
revoke execute on function pt_co_log(text, text, text, jsonb), pt_co_ms(jsonb, numeric) from authenticated;
grant execute on function cashout_act(jsonb), cashout_features() to authenticated;
