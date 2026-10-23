-- ProTrack schema update v43 (ProTrackAI v3.39): budget supplement and change request forms, approved through Approval Hub.
-- 1. Rights: wf.initiate (prepare and submit the forms; planning and costing engineers) and wf.record (record an Approval Hub
--    decision by hand while the link is not connected, and move the version of a posted supplement; the costing
--    coordinator by position).
-- 2. The forms (wf_forms), started in ProTrack:
--    - BRF, Budget Supplement / Returns Request, as the company form AP/Planning-BRF: general information, the lines
--      (description, category, user field, WBS, supplement or saving), the budget summary by user field, the impact on
--      margin and milestones, the category details and the approval chain (VP when contingency is used, EVP when the
--      management reserve is used);
--    - CRF, Change Request, as the change request log: CRF number, submission date, description, client reference, prices
--      submitted, approved by the client and considered internally, cost (Rev 00, current budget), client status.
--    Draft → Submitted (queued for Approval Hub) → In approval (the hub's WF number) → Approved, Rejected, or Returned for
--    correction (a draft again). Every step is kept in wf_events (append only).
-- 3. Approval Hub: submissions wait in wf_outbox; the hub, or IT's connector, takes them with wf_hub_next and reports each
--    step with wf_hub_update, both with the secret token the super admin creates (wf_hub_setup). Until it is connected,
--    the costing coordinator records the hub's decision by hand (wf_form_act record), said so on the form.
-- 4. An approved BRF is posted at once to the budget supplement log of the project (one row per line, BR-07/1 …, with
--    the WF number); its version is the month of the approval, and can be moved to the month before it or any month up to
--    the current one, with a reason. Rows posted from a WF keep their amounts: only their version and remarks change on
--    the log screen, and they are not removed there. An approved CRF is posted to the change order and claim log.
-- Needs schema-update-v36.sql (the version of the supplement log) and v20 (the change order log). Additive. Safe to run
-- twice. Undo: schema-rollback-v43.sql.

do $$ begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'budget_supplements' and column_name = 'version')
     or not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'co_log' and column_name = 'wf_no') then
    raise exception 'Run schema-update-v36.sql (STAGE-30-SETUP) and v20 first, then this update'; end if;
end $$;

-- ------------------------------------------------------------------ 1. rights
do $$
declare cur text[] := pt_rights(); src text; k text;
begin
  foreach k in array array['wf.initiate','wf.record'] loop if not (k = any(cur)) then cur := cur || k; end if; end loop;
  execute format('create or replace function pt_rights() returns text[] language sql immutable as $f$ select %L::text[] $f$', cur::text);
  select prosrc into src from pg_proc where proname = 'pt_right_default' and pronamespace = 'public'::regnamespace and pronargs = 2;
  if position('wf.initiate' in src) = 0 then
    if position('else false end' in src) = 0 then raise exception 'pt_right_default does not have the expected shape; add the wf rights by hand'; end if;
    src := regexp_replace(src, 'else false end', E'when ''wf.initiate''             then base in (''plan'', ''costing'')\n    when ''wf.record''               then false\n    else false end');
    execute format('create or replace function pt_right_default(base text, k text) returns boolean language sql immutable as $f$%s$f$', src);
  end if;
end $$;
create or replace function pt_wf(u uuid, pid text, k text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) is not null and (pid is null or user_sees(u, pid)) and pt_right(u, 'money.view', false) and pt_right(u, k, k = 'wf.record' and pt_is_coord(u)), false) $$;

-- ------------------------------------------------------------------ 2. tables
create table if not exists wf_forms (
  id text primary key, project_id text not null references projects(id) on delete cascade, kind text not null check (kind in ('BRF','CRF')), ref_no text not null,
  title text, status text not null default 'Draft' check (status in ('Draft','Submitted','In approval','Approved','Rejected','Returned','Cancelled')),
  data jsonb not null default '{}'::jsonb, lines jsonb not null default '[]'::jsonb, totals jsonb, approvers jsonb, version_pref text,
  wf_no text, hub_status text, hub_step text, hub_comment text, decided_on date, decided_by_name text, decision_source text check (decision_source in ('hub','manual')),
  version text, posted jsonb, posted_at timestamptz,
  prepared_by uuid, prepared_by_name text, prepared_at timestamptz not null default now(), submitted_by uuid, submitted_by_name text, submitted_at timestamptz,
  recorded_by uuid, recorded_by_name text, updated_at timestamptz not null default now(), unique (project_id, kind, ref_no));
create table if not exists wf_events (
  id bigserial primary key, form_id text not null references wf_forms(id) on delete cascade, project_id text not null, action text not null, status text,
  detail jsonb, source text not null default 'app', by_user uuid, by_name text, at_time timestamptz not null default now());
create table if not exists wf_outbox (
  id bigserial primary key, form_id text not null references wf_forms(id) on delete cascade, action text not null check (action in ('submit','cancel')),
  payload jsonb not null, status text not null default 'Queued' check (status in ('Queued','Taken','Done','Failed')), attempts int not null default 0,
  taken_at timestamptz, done_at timestamptz, error text, at_time timestamptz not null default now());
create table if not exists wf_hub_cfg (id boolean primary key default true check (id), token_hash text, active boolean not null default false, note text,
  set_by uuid, set_by_name text, set_at timestamptz, last_seen timestamptz);
alter table budget_supplements add column if not exists wf_form text;
alter table budget_supplements add column if not exists wf_no text;

drop trigger if exists wf_events_frozen on wf_events;
create trigger wf_events_frozen before update or delete on wf_events for each row execute function pt_append_only();
do $$
declare t text;
begin
  foreach t in array array['wf_forms','wf_events','wf_outbox','wf_hub_cfg'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists %I on %I', t || '_read', t);
    execute format('revoke all on %I from anon', t);
    execute format('revoke insert, update, delete, truncate on %I from authenticated', t);
  end loop;
end $$;
grant select on wf_forms, wf_events, wf_outbox to authenticated;
create policy wf_forms_read on wf_forms for select using (can_see(project_id) and pt_money_ok());
create policy wf_events_read on wf_events for select using (can_see(project_id) and pt_money_ok());
create or replace function pt_wf_is_sa() returns boolean language sql stable security definer set search_path = public as $$ select coalesce(role_of(auth.uid()) = 'sa', false) $$;
revoke execute on function pt_wf_is_sa() from public, anon;
grant execute on function pt_wf_is_sa() to authenticated;
create policy wf_outbox_read on wf_outbox for select using (pt_wf_is_sa());
-- wf_hub_cfg is read through wf_hub_status only (the token hash never leaves the server)

-- rows posted from an approved WF keep their amounts: on the log screen only their version and remarks change, and they
-- are not removed there; a copy of the log (a new version, an upload with the same supplement number) keeps the link
create or replace function pt_bsu_guard() returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('protrack.wf_post', true), '') = 'on' then return case when tg_op = 'DELETE' then old else new end; end if;
  if coalesce(current_setting('protrack.supp_update', true), '') = 'on' then
    if old.wf_form is not null then
      if tg_op = 'DELETE' then raise exception 'Supplement % was posted from the approved WF %; it is not removed here', old.supp_no, coalesce(old.wf_no, old.wf_form); end if;
      if (to_jsonb(new) - array['version','remarks']) <> (to_jsonb(old) - array['version','remarks']) then
        raise exception 'Supplement % was posted from the approved WF %; only its version and remarks change here', old.supp_no, coalesce(old.wf_no, old.wf_form); end if;
    end if;
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end $$;
create or replace function pt_bsu_wf_keep() returns trigger language plpgsql as $$
declare o budget_supplements;
begin
  if new.wf_form is null then
    select * into o from budget_supplements where project_id = new.project_id and supp_no = new.supp_no and wf_form is not null and batch_id <> new.batch_id order by id desc limit 1;
    if o.id is not null then new.wf_form := o.wf_form; new.wf_no := o.wf_no; end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_bsu_wf_keep on budget_supplements;
create trigger trg_bsu_wf_keep before insert on budget_supplements for each row execute function pt_bsu_wf_keep();

-- the checks of a supplement row use the date in Saudi Arabia, as the app and Approval Hub do (the database's own date is
-- UTC: a WF approved after midnight in Riyadh was "in the future" until 03:00)
do $$
declare src text;
begin
  select prosrc into src from pg_proc where proname = 'pt_supp_row' and pronamespace = 'public'::regnamespace and pronargs = 1;
  if src is not null and position('current_date' in src) > 0 then
    execute format('create or replace function pt_supp_row(x jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $f$%s$f$', replace(src, 'current_date', 'pt_today_sa()'));
  end if;
end $$;

-- ------------------------------------------------------------------ 3. helpers
create or replace function pt_wf_month(d date) returns text language sql immutable as $$ select to_char(d, 'YYYY-MM') $$;
create or replace function pt_wf_prev(m text) returns text language sql immutable as $$ select to_char((m || '-01')::date - interval '1 month', 'YYYY-MM') $$;
create or replace function pt_wf_event(f text, pid text, act text, st text, d jsonb, src text, u uuid, who text) returns void language sql security definer set search_path = public as $$
  insert into wf_events (form_id, project_id, action, status, detail, source, by_user, by_name) values (f, pid, act, st, d, src, u, who) $$;
-- the approvers of a BRF, as the company's approval box: VP for contingency, EVP for the management reserve
create or replace function pt_wf_chain(k text, lines jsonb) returns jsonb language sql immutable as $$
  select case when k = 'CRF' then '["Project Manager","Costing Manager","Portfolio Manager","Regional Manager"]'::jsonb
    else '["Project Manager","Costing Manager","Portfolio Manager","Planning Manager","Regional Manager"]'::jsonb
      || case when exists (select 1 from jsonb_array_elements(lines) l where upper(coalesce(l ->> 'user_field', '')) = 'CONT' or coalesce(l ->> 'category', '') ~* '^cont-|contingency') then '["Vice President"]'::jsonb else '[]'::jsonb end
      || case when exists (select 1 from jsonb_array_elements(lines) l where upper(coalesce(l ->> 'user_field', '')) = 'MGT.RES' or coalesce(l ->> 'category', '') ~* 'mgmt res|mgt\.? ?res|management reserve') then '["Executive Vice President"]'::jsonb else '[]'::jsonb end end $$;
-- the checks of a form before it is submitted; returns the totals, or raises
create or replace function pt_wf_check(f wf_forms) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare x jsonb; sr jsonb; n int := 0; s numeric := 0; v numeric := 0; a numeric; d jsonb := f.data; e text;
begin
  if f.kind = 'BRF' then
    if jsonb_array_length(f.lines) = 0 then raise exception 'Add at least one line'; end if;
    if jsonb_array_length(f.lines) > 200 then raise exception 'A form has at most 200 lines'; end if;
    for x in select * from jsonb_array_elements(f.lines) loop
      n := n + 1;
      if length(btrim(coalesce(x ->> 'description', ''))) < 3 then raise exception 'Line %: give the short description', n; end if;
      sr := pt_supp_row(jsonb_build_object('supp_no', f.ref_no || '/' || n, 'supp_date', current_date::text, 'user_field', x ->> 'user_field', 'category', x ->> 'category',
              'description', x ->> 'description', 'amount', x ->> 'amount', 'wbs_id', x ->> 'wbs_id', 'wbs_description', x ->> 'wbs_description', 'linked_ref', x ->> 'linked_ref', 'remarks', x ->> 'remarks'));
      if sr ->> 'error' is not null then raise exception 'Line %: %', n, sr ->> 'error'; end if;
      a := pt_num(x ->> 'amount'); if a = 0 then raise exception 'Line %: the amount is zero', n; end if;
      if a < 0 then s := s + a; else v := v + a; end if;
    end loop;
    return jsonb_build_object('supplement', s, 'savings', v, 'net', s + v, 'lines', n);
  end if;
  if length(btrim(coalesce(d ->> 'description', ''))) < 5 then raise exception 'Give the detailed description of the change'; end if;
  if nullif(d ->> 'sub_date', '') is not null and pt_bad_date(d ->> 'sub_date') then raise exception 'The submission date is not a date'; end if;
  if pt_date(d ->> 'sub_date') > pt_today_sa() then raise exception 'The submission date is in the future'; end if;
  foreach e in array array['price_submitted','price_client','price_internal','cost_rev0','cost_current'] loop
    if nullif(d ->> e, '') is not null and pt_num(d ->> e) is null then raise exception 'The % is not a number', replace(e, '_', ' '); end if;
  end loop;
  e := pt_vo_check(d ->> 'client_status', pt_num(d ->> 'price_client'), null, pt_num(d ->> 'price_submitted'), null, null);
  if e is not null then raise exception '%', upper(left(e, 1)) || substr(e, 2); end if;
  return jsonb_build_object('price_submitted', pt_num(d ->> 'price_submitted'), 'cost_current', pt_num(d ->> 'cost_current'));
end $$;
-- what Approval Hub receives for a form
create or replace function pt_wf_payload(f wf_forms) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('form_id', f.id, 'kind', f.kind, 'form', case when f.kind = 'BRF' then 'Budget Supplement / Returns Request (AP/Planning-BRF)' else 'Change Request' end,
    'ref_no', f.ref_no, 'project', jsonb_build_object('id', p.id, 'pe_number', coalesce(p.pe_number, p.id), 'name', p.name, 'region', p.region),
    'title', f.title, 'totals', f.totals, 'lines', f.lines, 'data', f.data, 'approvers', f.approvers, 'prepared_by', f.prepared_by_name,
    'submitted_by', f.submitted_by_name, 'submitted_at', f.submitted_at, 'link', 'live.html#wf=' || f.id)
  from projects p where p.id = f.project_id $$;

-- ------------------------------------------------------------------ 4. posting an approved form to the logs
create or replace function pt_wf_post(fid text, u uuid, who text) returns jsonb language plpgsql security definer set search_path = public as $$
declare f wf_forms; lb import_batches; x jsonb; n int := 0; sr jsonb; r jsonb; sn text; done jsonb := '[]'::jsonb; skip jsonb := '[]'::jsonb; nb uuid; per text := pt_wf_month(pt_today_sa());
        c co_log; d jsonb; st text;
begin
  select * into f from wf_forms where id = fid for update;
  if f.status <> 'Approved' or f.posted is not null then return f.posted; end if;
  if f.kind = 'BRF' then
    perform pg_advisory_xact_lock(hashtext('protrack:log:' || f.project_id || ':supplements'));
    select * into lb from import_batches where project_id = f.project_id and kind = 'supplements' and status = 'committed' order by source_period desc, at_time desc limit 1;
    if lb.id is null then
      insert into import_batches (project_id, kind, file_name, file_hash, source_period, rows_total, rows_accepted, rows_rejected, total_source, total_accepted, recon_status, detail, by_user)
      values (f.project_id, 'supplements', 'Started by the approved WF ' || coalesce(f.wf_no, f.ref_no), 'wf-' || f.id, per, 0, 0, 0, 0, 0, 'Matched', jsonb_build_object('wf_form', f.id), u)
      returning * into lb;
    end if;
    perform set_config('protrack.wf_post', 'on', true);
    for x in select * from jsonb_array_elements(f.lines) loop
      n := n + 1; sn := upper(f.ref_no) || case when jsonb_array_length(f.lines) > 1 then '/' || n else '' end;
      if exists (select 1 from budget_supplements where batch_id = lb.id and supp_no = sn) then skip := skip || to_jsonb(sn); continue; end if;
      sr := pt_supp_row(jsonb_build_object('supp_no', sn, 'supp_date', f.decided_on::text, 'user_field', x ->> 'user_field', 'category', x ->> 'category', 'description', x ->> 'description',
              'amount', x ->> 'amount', 'wbs_id', x ->> 'wbs_id', 'wbs_description', x ->> 'wbs_description', 'linked_ref', x ->> 'linked_ref', 'remarks', x ->> 'remarks', 'version', f.version));
      r := sr -> 'row';
      insert into budget_supplements (batch_id, project_id, period, supp_no, supp_date, description, amount, category, linked_ref, approval_status, remarks,
                                      user_field, unified_category, wbs_group, wbs_id, wbs_description, version, wf_form, wf_no)
      values (lb.id, f.project_id, lb.source_period, sn, f.decided_on, r ->> 'description', pt_num(x ->> 'amount'), coalesce(r ->> 'category', x ->> 'category'), r ->> 'linked_ref', 'Approved',
              r ->> 'remarks', coalesce(r ->> 'user_field', x ->> 'user_field'), r ->> 'unified_category', x ->> 'wbs_group', r ->> 'wbs_id', r ->> 'wbs_description', f.version, f.id, f.wf_no);
      done := done || to_jsonb(sn);
      insert into supp_audit (row_id, project_id, supp_no, period, action, changes, reason, by_user, by_name)
        values (currval('budget_supplements_id_seq'), f.project_id, sn, lb.source_period, 'added', jsonb_build_array(jsonb_build_array('amount', null, x -> 'amount')), 'Approved WF ' || coalesce(f.wf_no, ''), u, who);
    end loop;
    perform set_config('protrack.wf_post', '', true);
    insert into change_log (text, by_user) values ((select short from projects where id = f.project_id) || ': ' || f.ref_no || ' (WF ' || coalesce(f.wf_no, '') || ') posted to the budget supplement log, version ' || f.version, u);
    update wf_forms set posted = jsonb_build_object('log', 'supplements', 'batch_id', lb.id, 'rows', done, 'skipped', skip), posted_at = now() where id = f.id;
    perform pt_wf_event(f.id, f.project_id, 'Posted to the budget supplement log', 'Approved', jsonb_build_object('rows', done, 'skipped', skip, 'version', f.version), 'app', u, who);
    return jsonb_build_object('rows', done, 'skipped', skip);
  end if;
  -- a change request: the change order and claim log
  d := f.data;
  select * into lb from import_batches where project_id = f.project_id and kind = 'volog' and status = 'committed' order by source_period desc, at_time desc limit 1;
  if lb.id is null then
    insert into import_batches (project_id, kind, file_name, file_hash, source_period, rows_total, rows_accepted, rows_rejected, total_source, total_accepted, recon_status, detail, by_user)
    values (f.project_id, 'volog', 'Started by the approved WF ' || coalesce(f.wf_no, f.ref_no), 'wf-' || f.id, per, 0, 0, 0, 0, 0, 'Matched', jsonb_build_object('wf_form', f.id), u)
    returning * into lb;
  end if;
  select * into c from co_log where batch_id = lb.id and upper(ref_no) = upper(f.ref_no) limit 1;
  if c.id is not null then
    perform set_config('protrack.co_log_update', 'on', true);
    update co_log set wf_no = f.wf_no, wf_date = f.decided_on, remarks = coalesce(nullif(d ->> 'remarks', ''), remarks) where id = c.id;
    perform set_config('protrack.co_log_update', '', true);
    insert into co_log_updates (row_id, batch_id, project_id, ref_no, period, changes, by_user, by_name)
      values (c.id, lb.id, f.project_id, c.ref_no, lb.source_period, jsonb_build_array(jsonb_build_array('wf_no', c.wf_no, f.wf_no), jsonb_build_array('wf_date', c.wf_date, f.decided_on)), u, who);
    st := 'updated';
  else
    insert into co_log (batch_id, project_id, period, ref_no, kind, description, submission_status, submitted_on, client_status, est_price, est_cost, rev0_change,
                        internal_wf, overall_status, remarks, client_price, internal_price, wf_no, wf_date)
    values (lb.id, f.project_id, lb.source_period, upper(f.ref_no), 'VO', left(d ->> 'description', 2000), case when nullif(d ->> 'sub_date', '') is not null then 'Submitted' end,
            pt_date(d ->> 'sub_date'), nullif(d ->> 'client_status', ''), pt_num(d ->> 'price_submitted'), pt_num(d ->> 'cost_current'), pt_num(d ->> 'cost_rev0'),
            'Approved', 'Approved internally (WF ' || coalesce(f.wf_no, '') || ')', nullif(concat_ws(' · ', nullif(d ->> 'client_ref', ''), nullif(d ->> 'remarks', '')), ''),
            pt_num(d ->> 'price_client'), pt_num(d ->> 'price_internal'), f.wf_no, f.decided_on)
    returning * into c;
    st := 'added';
  end if;
  insert into change_log (text, by_user) values ((select short from projects where id = f.project_id) || ': ' || f.ref_no || ' (WF ' || coalesce(f.wf_no, '') || ') ' || st || ' in the change order and claim log', u);
  update wf_forms set posted = jsonb_build_object('log', 'volog', 'batch_id', lb.id, 'row', c.id, 'how', st), posted_at = now() where id = f.id;
  perform pt_wf_event(f.id, f.project_id, 'Posted to the change order and claim log (' || st || ')', 'Approved', jsonb_build_object('ref', f.ref_no), 'app', u, who);
  return jsonb_build_object('row', c.id, 'how', st);
end $$;
-- a decision on a form, from the hub or recorded by hand
create or replace function pt_wf_decide(f wf_forms, decn text, wfno text, d date, approver text, cm text, src text, u uuid, who text) returns jsonb language plpgsql security definer set search_path = public as $$
declare ns text; ver text; res jsonb := null;
begin
  if f.status not in ('Submitted','In approval') then raise exception 'The form is % (only a submitted form is decided)', f.status; end if;
  if decn not in ('approved','rejected','returned') then raise exception 'The decision is approved, rejected or returned'; end if;
  if coalesce(btrim(wfno), '') = '' or length(wfno) > 40 then raise exception 'Give the Approval Hub WF number (up to 40 characters)'; end if;
  if d is null then raise exception 'Give the date of the decision'; end if;
  if d > pt_today_sa() then raise exception 'The decision date % is in the future', d; end if;
  if d < (f.submitted_at at time zone 'Asia/Riyadh')::date then raise exception 'The decision date % is before the form was submitted', d; end if;
  if decn <> 'approved' and length(btrim(coalesce(cm, ''))) < 5 then raise exception 'Give the reason of the rejection or return (at least 5 characters)'; end if;
  ns := case decn when 'approved' then 'Approved' when 'rejected' then 'Rejected' else 'Returned' end;
  ver := case when ns = 'Approved' then coalesce(case when f.version_pref ~ '^[0-9]{4}-[0-9]{2}$' and f.version_pref between pt_wf_prev(pt_wf_month(d)) and pt_wf_month(pt_today_sa()) then f.version_pref end, pt_wf_month(d)) end;
  update wf_forms set status = ns, wf_no = btrim(wfno), decided_on = d, decided_by_name = nullif(btrim(coalesce(approver, '')), ''), hub_comment = nullif(btrim(coalesce(cm, '')), ''),
         hub_status = ns, decision_source = src, version = ver, recorded_by = case when src = 'manual' then u end, recorded_by_name = case when src = 'manual' then who end, updated_at = now()
   where id = f.id;
  perform pt_wf_event(f.id, f.project_id, case when src = 'manual' then 'Approval Hub decision recorded by hand: ' else 'Approval Hub: ' end || lower(ns), ns,
    jsonb_build_object('wf_no', wfno, 'date', d, 'approver', approver, 'comment', cm, 'version', ver), src, u, who);
  update wf_outbox set status = 'Done', done_at = now() where form_id = f.id and status in ('Queued','Taken');
  if ns = 'Approved' then res := pt_wf_post(f.id, u, who); end if;
  return jsonb_build_object('status', ns, 'version', ver, 'posted', res);
end $$;

-- ------------------------------------------------------------------ 5. the forms in ProTrack
create or replace function wf_form_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); who text := name_of(auth.uid()); f wf_forms; pid text := p ->> 'project_id'; k text := p ->> 'kind'; rn text; nxt int; fid text; vp text := nullif(p ->> 'version_pref', '');
begin
  if me is null or role_of(me) is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if jsonb_typeof(coalesce(p -> 'lines', '[]'::jsonb)) <> 'array' or jsonb_typeof(coalesce(p -> 'data', '{}'::jsonb)) <> 'object' then raise exception 'The form is not well formed'; end if;
  if vp is not null and vp !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'The version must be a month such as 2026-10'; end if;
  if p ->> 'id' is not null then
    select * into f from wf_forms where id = p ->> 'id' for update;
    if f.id is null then raise exception 'Unknown form'; end if;
    if not pt_wf(me, f.project_id, 'wf.initiate') then raise exception 'You cannot prepare these forms on this project (the wf.initiate right)' using errcode = '42501'; end if;
    if f.status not in ('Draft','Returned') then raise exception 'The form is % and is not changed any more', f.status; end if;
    update wf_forms set title = left(p ->> 'title', 200), data = coalesce(p -> 'data', data), lines = coalesce(p -> 'lines', lines), version_pref = vp,
           approvers = pt_wf_chain(f.kind, coalesce(p -> 'lines', lines)), updated_at = now() where id = f.id;
    return jsonb_build_object('id', f.id, 'ref_no', f.ref_no);
  end if;
  if not exists (select 1 from projects where id = pid) then raise exception 'Choose the project'; end if;
  if not pt_wf(me, pid, 'wf.initiate') then raise exception 'You cannot prepare these forms on this project (the wf.initiate right)' using errcode = '42501'; end if;
  if k not in ('BRF','CRF') then raise exception 'Choose the form'; end if;
  perform pg_advisory_xact_lock(hashtext('protrack:wf:' || pid || ':' || k));
  rn := upper(btrim(coalesce(p ->> 'ref_no', '')));
  if rn = '' then
    select coalesce(max(nullif(regexp_replace(ref_no, '^.*-', ''), '')::int), 0) + 1 into nxt from wf_forms where project_id = pid and kind = k and ref_no ~ '-[0-9]+$';
    rn := case k when 'BRF' then 'BR-' else 'CR-' end || lpad(nxt::text, 2, '0');
  end if;
  if rn !~ '^[A-Z0-9][A-Z0-9/._-]{1,30}$' then raise exception 'The reference % is not a reference (letters, digits, - / . _)', rn; end if;
  if exists (select 1 from wf_forms where project_id = pid and kind = k and ref_no = rn) then raise exception '% is already used on this project', rn; end if;
  fid := 'WF-' || to_char(now(), 'YYMMDD') || '-' || substr(md5(random()::text || clock_timestamp()::text), 1, 6);
  insert into wf_forms (id, project_id, kind, ref_no, title, data, lines, approvers, version_pref, prepared_by, prepared_by_name)
    values (fid, pid, k, rn, left(p ->> 'title', 200), coalesce(p -> 'data', '{}'::jsonb), coalesce(p -> 'lines', '[]'::jsonb), pt_wf_chain(k, coalesce(p -> 'lines', '[]'::jsonb)), vp, me, who);
  perform pt_wf_event(fid, pid, 'Prepared', 'Draft', jsonb_build_object('ref_no', rn), 'app', me, who);
  return jsonb_build_object('id', fid, 'ref_no', rn);
end $$;

create or replace function wf_form_act(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); who text := name_of(auth.uid()); f wf_forms; a text := p ->> 'action'; t jsonb; rs text := btrim(coalesce(p ->> 'reason', '')); m text; lo text; cnt int;
begin
  if me is null or role_of(me) is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  select * into f from wf_forms where id = p ->> 'id' for update;
  if f.id is null then raise exception 'Unknown form'; end if;
  if a = 'submit' then
    if not pt_wf(me, f.project_id, 'wf.initiate') then raise exception 'You cannot submit these forms on this project (the wf.initiate right)' using errcode = '42501'; end if;
    if f.status not in ('Draft','Returned') then raise exception 'The form is % (only a draft or a returned form is submitted)', f.status; end if;
    t := pt_wf_check(f);
    update wf_forms set status = 'Submitted', totals = t, approvers = pt_wf_chain(f.kind, f.lines), submitted_by = me, submitted_by_name = who, submitted_at = now(),
           hub_status = 'Queued for Approval Hub', wf_no = case when f.status = 'Returned' then f.wf_no end, updated_at = now() where id = f.id returning * into f;
    insert into wf_outbox (form_id, action, payload) values (f.id, 'submit', pt_wf_payload(f));
    perform pt_wf_event(f.id, f.project_id, 'Submitted to Approval Hub', 'Submitted', jsonb_build_object('totals', t, 'approvers', f.approvers), 'app', me, who);
    return jsonb_build_object('status', 'Submitted', 'totals', t);
  elsif a = 'cancel' then
    if not (pt_wf(me, f.project_id, 'wf.initiate') or pt_wf(me, f.project_id, 'wf.record')) then raise exception 'You cannot cancel this form' using errcode = '42501'; end if;
    if f.status not in ('Draft','Returned','Submitted') then raise exception 'The form is % (a draft, a returned or a submitted form is cancelled)', f.status; end if;
    if length(rs) < 5 then raise exception 'Give the reason (at least 5 characters)'; end if;
    if f.status = 'Submitted' then insert into wf_outbox (form_id, action, payload) values (f.id, 'cancel', jsonb_build_object('form_id', f.id, 'ref_no', f.ref_no, 'wf_no', f.wf_no, 'reason', rs)); end if;
    update wf_outbox set status = 'Done', done_at = now() where form_id = f.id and action = 'submit' and status = 'Queued';
    update wf_forms set status = 'Cancelled', hub_comment = rs, updated_at = now() where id = f.id;
    perform pt_wf_event(f.id, f.project_id, 'Cancelled', 'Cancelled', jsonb_build_object('reason', rs), 'app', me, who);
    return jsonb_build_object('status', 'Cancelled');
  elsif a = 'record' then
    if not pt_wf(me, f.project_id, 'wf.record') then raise exception 'Only the costing coordinator (wf.record) records an Approval Hub decision by hand' using errcode = '42501'; end if;
    if (select active from wf_hub_cfg) is true and coalesce((p ->> 'confirm_hub_down')::boolean, false) is not true then
      raise exception 'Approval Hub is connected: its decision comes by itself. Record by hand only if the link is down (tick the box)'; end if;
    return pt_wf_decide(f, lower(p ->> 'decision'), p ->> 'wf_no', pt_date(p ->> 'date'), p ->> 'approver', p ->> 'comment', 'manual', me, who);
  elsif a = 'set_version' then
    if not (pt_wf(me, f.project_id, 'wf.record') or pt_right(me, 'logs.upload', pt_is_coord(me)) and user_sees(me, f.project_id)) then
      raise exception 'Only the costing engineer or the costing coordinator moves the version' using errcode = '42501'; end if;
    if f.status <> 'Approved' or f.kind <> 'BRF' then raise exception 'Only an approved budget supplement request has a version'; end if;
    m := p ->> 'version';
    if coalesce(m, '') !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'The version must be a month such as 2026-10'; end if;
    lo := pt_wf_prev(pt_wf_month(f.decided_on));
    if m < lo or m > pt_wf_month(pt_today_sa()) then raise exception 'The version is from % (the month before the approval) to % (this month)', lo, pt_wf_month(pt_today_sa()); end if;
    if m = f.version then return jsonb_build_object('version', m, 'changed', false); end if;
    if length(rs) < 5 then raise exception 'Give the reason for moving the version (at least 5 characters)'; end if;
    perform set_config('protrack.wf_post', 'on', true);
    update budget_supplements s set version = m where s.wf_form = f.id and s.batch_id = (select b.id from import_batches b where b.project_id = f.project_id and b.kind = 'supplements' and b.status = 'committed' order by b.source_period desc, b.at_time desc limit 1);
    get diagnostics cnt = row_count;
    perform set_config('protrack.wf_post', '', true);
    insert into supp_audit (row_id, project_id, supp_no, period, action, changes, reason, by_user, by_name)
      values (null, f.project_id, f.ref_no, m, 'changed', jsonb_build_array(jsonb_build_array('version', f.version, m)), left(rs, 300), me, who);
    update wf_forms set version = m, updated_at = now() where id = f.id;
    perform pt_wf_event(f.id, f.project_id, 'Version moved from ' || coalesce(f.version, '—') || ' to ' || m, f.status, jsonb_build_object('reason', rs, 'rows', cnt), 'app', me, who);
    return jsonb_build_object('version', m, 'changed', true, 'rows', cnt);
  end if;
  raise exception 'Unknown action %', a;
end $$;

-- ------------------------------------------------------------------ 6. Approval Hub (the hub or IT's connector, with the secret token)
create or replace function pt_wf_hub_ok(tok text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select active and token_hash is not null and token_hash = encode(sha256(convert_to(coalesce(tok, ''), 'UTF8')), 'hex') from wf_hub_cfg where id), false) $$;
create or replace function wf_hub_next(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare lim int := least(greatest(coalesce((p ->> 'limit')::int, 20), 1), 100); out jsonb;
begin
  if not pt_wf_hub_ok(p ->> 'token') then raise exception 'Not authorised' using errcode = '42501'; end if;
  update wf_hub_cfg set last_seen = now() where id;
  with q as (select id from wf_outbox where status = 'Queued' or (status = 'Taken' and taken_at < now() - interval '15 minutes' and attempts < 10) order by id limit lim for update skip locked),
       u as (update wf_outbox o set status = 'Taken', taken_at = now(), attempts = attempts + 1 from q where o.id = q.id returning o.*)
  select coalesce(jsonb_agg(jsonb_build_object('message_id', id, 'action', action, 'payload', payload) order by id), '[]'::jsonb) into out from u;
  return jsonb_build_object('items', out);
end $$;
-- p: {token, message_id (to acknowledge a message) | form_id or ref (project + ref_no), status: received | in_approval | approved | rejected | returned,
--     wf_no, step, approver, date (YYYY-MM-DD), comment, error}
create or replace function wf_hub_update(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare f wf_forms; st text := lower(coalesce(p ->> 'status', '')); hub uuid := null;
begin
  if not pt_wf_hub_ok(p ->> 'token') then raise exception 'Not authorised' using errcode = '42501'; end if;
  update wf_hub_cfg set last_seen = now() where id;
  if p ->> 'message_id' is not null and st in ('received','failed') then
    update wf_outbox set status = case when st = 'failed' then 'Failed' else 'Done' end, done_at = now(), error = left(p ->> 'error', 500) where id = (p ->> 'message_id')::bigint;
    if st = 'failed' then return jsonb_build_object('ok', true); end if;
  end if;
  select * into f from wf_forms where id = coalesce(p ->> 'form_id', (select form_id from wf_outbox where id = nullif(p ->> 'message_id', '')::bigint)) for update;
  if f.id is null and p ->> 'ref_no' is not null then select * into f from wf_forms where project_id = p ->> 'project_id' and ref_no = upper(p ->> 'ref_no') for update; end if;
  if f.id is null then raise exception 'Unknown form'; end if;
  if st in ('received','in_approval') then
    if f.status not in ('Submitted','In approval') then return jsonb_build_object('ok', true, 'status', f.status); end if;
    update wf_forms set status = 'In approval', wf_no = coalesce(nullif(btrim(p ->> 'wf_no'), ''), wf_no), hub_status = coalesce(nullif(p ->> 'step', ''), 'In approval'),
           hub_step = nullif(p ->> 'step', ''), updated_at = now() where id = f.id;
    perform pt_wf_event(f.id, f.project_id, 'Approval Hub: ' || coalesce(nullif(p ->> 'step', ''), 'in approval'), 'In approval',
      jsonb_build_object('wf_no', p ->> 'wf_no', 'approver', p ->> 'approver', 'comment', p ->> 'comment'), 'hub', hub, 'Approval Hub');
    return jsonb_build_object('ok', true, 'status', 'In approval');
  elsif st in ('approved','rejected','returned') then
    return pt_wf_decide(f, st, coalesce(nullif(btrim(p ->> 'wf_no'), ''), f.wf_no), coalesce(pt_date(p ->> 'date'), pt_today_sa()), p ->> 'approver', p ->> 'comment', 'hub', null, 'Approval Hub');
  end if;
  raise exception 'Unknown status %', st;
end $$;
-- the super admin connects or disconnects the link; a new token is shown once
create or replace function wf_hub_setup(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); tok text;
begin
  if me is null or role_of(me) <> 'sa' then raise exception 'Only a super admin sets the Approval Hub link' using errcode = '42501'; end if;
  insert into wf_hub_cfg (id) values (true) on conflict (id) do nothing;
  if p ->> 'action' = 'new_token' then
    tok := 'pthub_' || replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
    update wf_hub_cfg set token_hash = encode(sha256(convert_to(tok, 'UTF8')), 'hex'), active = true, note = left(p ->> 'note', 200), set_by = me, set_by_name = name_of(me), set_at = now() where id;
    insert into change_log (text, by_user) values ('Approval Hub link: a new token was made (the previous one stops working)', me);
    return jsonb_build_object('token', tok, 'active', true);
  elsif p ->> 'action' = 'off' then
    update wf_hub_cfg set active = false, set_by = me, set_by_name = name_of(me), set_at = now() where id;
    insert into change_log (text, by_user) values ('Approval Hub link switched off', me);
    return jsonb_build_object('active', false);
  end if;
  raise exception 'Unknown action';
end $$;
create or replace function wf_hub_status() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('version', 43, 'active', coalesce((select active and token_hash is not null from wf_hub_cfg where id), false),
    'set_by', (select set_by_name from wf_hub_cfg where id), 'set_at', (select set_at from wf_hub_cfg where id), 'last_seen', (select last_seen from wf_hub_cfg where id),
    'queued', (select count(*) from wf_outbox where status in ('Queued','Taken')), 'failed', (select count(*) from wf_outbox where status = 'Failed')) $$;

revoke execute on function pt_wf(uuid, text, text), pt_wf_month(date), pt_wf_prev(text), pt_wf_event(text, text, text, text, jsonb, text, uuid, text), pt_wf_chain(text, jsonb), pt_wf_check(wf_forms),
  pt_wf_payload(wf_forms), pt_wf_post(text, uuid, text), pt_wf_decide(wf_forms, text, text, date, text, text, text, uuid, text), pt_wf_hub_ok(text), pt_bsu_wf_keep() from public, anon, authenticated;
revoke execute on function wf_form_save(jsonb), wf_form_act(jsonb), wf_hub_setup(jsonb), wf_hub_status() from public, anon;
grant execute on function wf_form_save(jsonb), wf_form_act(jsonb), wf_hub_setup(jsonb), wf_hub_status() to authenticated;
-- the hub calls these two with the anon key and its token
revoke execute on function wf_hub_next(jsonb), wf_hub_update(jsonb) from public;
grant execute on function wf_hub_next(jsonb), wf_hub_update(jsonb) to anon, authenticated;
