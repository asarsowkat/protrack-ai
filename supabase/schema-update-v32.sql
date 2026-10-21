-- ProTrack schema update v32 (ProTrackAI v3.25): BOQ Engine, drawing-based quantity take-off and the Estimated BOQ.
-- 1. Rights: boq.upload (project engineer), boq.estimate (quantity surveyor or estimator), boq.review (lead engineer),
--    boq.approve (estimation manager), boq.rate (estimated unit rates). The Head of Planning and Cost Control holds
--    boq.review and boq.approve by position. Defaults as the app's RIGHTS.
-- 2. Tables, one per record type, each row holding the record as the app keeps it (doc) with its keys in columns:
--    boq_packages, boq_structures, boq_drawings (one row per drawing revision), boq_dimensions, boq_calculations,
--    boq_specifications (with their requirements), boq_assumptions, boq_estimates (revisions with their frozen lines),
--    boq_handoffs, boq_master (master data, one row) and boq_audit (append only). Project isolation: a row is read only by
--    people who see its project (can_see). Nothing is written directly: every change goes through boq_save.
-- 3. boq_save(p) = {ent, row} checks, on the server, the rules the app applies:
--    - the person sees the project and holds the right for that record type;
--    - a drawing revision's number, revision, file and fingerprint never change once registered; an eligible status is
--      confirmed only by a reviewer who did not register it; superseding needs a reviewer; the estimation basis changes
--      only with the estimator or reviewer right;
--    - an assumption is reviewed (boq.review) and approved (boq.approve) by someone other than its author;
--    - an estimate revision moves only along Draft → In Progress → Ready for Review → Under Review → Approved for Internal
--      Use → Released (→ Superseded), or back to Returned for Correction; whoever prepared or submitted it cannot review,
--      approve or release it; approved, released and superseded lines never change; approval needs every quantity verified;
--    - a hand-off needs boq.approve and a released revision, and is recorded only.
--    It writes the row and an audit entry. It never touches budgets, cost reports, purchase orders, commitments, actual
--    costs, forecasts or earned value: BOQ Engine has no write path to them.
-- 4. Storage: private bucket boq-drawings (path boq/<project>/<record>/<file>), read by people who see the project and
--    BOQ Engine, written by boq.upload, boq.estimate; never replaced or deleted by a rule.
-- Not on the server in this update: quantities are worked out in the app (exact decimals, engine version recorded with
-- each calculation) and stored; a server-side recalculation service is a remaining task.
-- Needs schema-update-v16.sql (rights) and v31 (the screen). Additive. Safe to run twice. Undo: schema-rollback-v32.sql.

do $$ begin
  if to_regprocedure('public.pt_right(uuid,text,boolean)') is null then raise exception 'Run schema-update-v16.sql (STAGE-13-SETUP) first, then this update'; end if;
  if not ('boq' = any(pt_screens())) then raise exception 'Run schema-update-v31.sql (the BOQ Engine screen) first, then this update'; end if;
end $$;

-- ------------------------------------------------------------------ 1. rights
do $$
declare cur text[] := pt_rights(); src text; k text;
begin
  foreach k in array array['boq.upload','boq.estimate','boq.review','boq.approve','boq.rate'] loop
    if not (k = any(cur)) then cur := cur || k; end if; end loop;
  execute format('create or replace function pt_rights() returns text[] language sql immutable as $f$ select %L::text[] $f$', cur::text);
  select prosrc into src from pg_proc where proname = 'pt_right_default' and pronamespace = 'public'::regnamespace and pronargs = 2;
  if position('boq.upload' in src) = 0 then
    if position('else false end' in src) = 0 then raise exception 'pt_right_default does not have the expected shape; add the boq rights by hand'; end if;
    src := regexp_replace(src, 'else false end', E'when ''boq.upload''              then base in (''plan'',''pm'',''costing'')\n    when ''boq.estimate''            then base in (''costing'',''plan'')\n    when ''boq.review''              then false\n    when ''boq.approve''             then false\n    when ''boq.rate''                then base = ''costing''\n    else false end');
    execute format('create or replace function pt_right_default(base text, k text) returns boolean language sql immutable as $f$%s$f$', src);
  end if;
end $$;
create or replace function pt_boq(u uuid, pid text, k text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(user_sees(u, pid) and pt_right(u, k, k in ('boq.review','boq.approve') and pt_is_head(u)), false) $$;

-- ------------------------------------------------------------------ 2. tables
do $$
declare t text;
begin
  foreach t in array array['boq_packages','boq_structures','boq_drawings','boq_dimensions','boq_calculations','boq_specifications','boq_assumptions','boq_estimates','boq_handoffs'] loop
    execute format('create table if not exists %I (id text primary key, project_id text not null references projects(id) on delete cascade, doc jsonb not null,
      updated_by uuid references profiles(id), updated_at timestamptz not null default now())', t);
    execute format('create index if not exists %I on %I (project_id)', t || '_proj', t);
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists %I on %I', t || '_read', t);
    execute format('create policy %I on %I for select using (can_see(project_id))', t || '_read', t);
    execute format('revoke all on %I from anon', t);
    execute format('revoke insert, update, delete, truncate on %I from authenticated', t);
    execute format('grant select on %I to authenticated', t);
  end loop;
end $$;
create unique index if not exists boq_drawings_rev on boq_drawings (project_id, lower(doc ->> 'no'), lower(doc ->> 'rev')) where (doc ->> 'reg')::boolean and not coalesce((doc ->> 'discarded')::boolean, false);
create unique index if not exists boq_drawings_sha on boq_drawings (project_id, (doc ->> 'sha')) where not coalesce((doc ->> 'discarded')::boolean, false);
create table if not exists boq_master (id int primary key default 1 check (id = 1), doc jsonb not null, updated_by uuid references profiles(id), updated_at timestamptz not null default now());
alter table boq_master enable row level security;
drop policy if exists boq_master_read on boq_master;
create policy boq_master_read on boq_master for select using (auth.uid() is not null);
revoke all on boq_master from anon;
revoke insert, update, delete, truncate on boq_master from authenticated;
grant select on boq_master to authenticated;
create table if not exists boq_audit (id bigserial primary key, at_time timestamptz not null default now(), by_user uuid references profiles(id), by_name text, by_role text,
  action text not null, ent text not null, ref text, project_id text, detail jsonb);
create index if not exists boq_audit_proj on boq_audit (project_id, id);
alter table boq_audit enable row level security;
drop policy if exists boq_audit_read on boq_audit;
create policy boq_audit_read on boq_audit for select using (project_id is null or can_see(project_id));
revoke all on boq_audit from anon;
revoke insert, update, delete, truncate on boq_audit from authenticated;
grant select on boq_audit to authenticated;

-- ------------------------------------------------------------------ 3. saving, with the governance rules
create or replace function boq_save(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); ent text := p ->> 'ent'; r jsonb := p -> 'row'; pid text := r ->> 'project_id'; id_ text := r ->> 'id';
        tbl text; old jsonb; os text; ns text; who text; rl text; act text := 'Saved'; elig boolean;
        flow jsonb := '{"Draft":["Draft","In Progress"],"In Progress":["In Progress","Ready for Review"],"Returned for Correction":["Returned for Correction","In Progress","Ready for Review"],
                        "Ready for Review":["Ready for Review","Under Review","Returned for Correction"],"Under Review":["Under Review","Approved for Internal Use","Returned for Correction"],
                        "Approved for Internal Use":["Approved for Internal Use","Released"],"Released":["Released","Superseded"],"Superseded":["Superseded"]}';
begin
  if me is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  select name into who from profiles where id = me; rl := role_of(me);
  if rl is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if jsonb_typeof(r) <> 'object' then raise exception 'Nothing to save'; end if;
  if length(r::text) > 5000000 then raise exception 'The record is too large'; end if;
  if ent = 'master' then
    if rl <> 'sa' then raise exception 'Only a super admin changes the BOQ Engine master data' using errcode = '42501'; end if;
    insert into boq_master (id, doc, updated_by) values (1, r, me) on conflict (id) do update set doc = excluded.doc, updated_by = me, updated_at = now();
    insert into boq_audit (by_user, by_name, by_role, action, ent) values (me, who, rl, 'Master data changed', 'master');
    return jsonb_build_object('ok', true);
  end if;
  tbl := case ent when 'package' then 'boq_packages' when 'structure' then 'boq_structures' when 'drawing' then 'boq_drawings' when 'dimension' then 'boq_dimensions'
    when 'calculation' then 'boq_calculations' when 'specification' then 'boq_specifications' when 'assumption' then 'boq_assumptions' when 'estimate' then 'boq_estimates' when 'handoff' then 'boq_handoffs' end;
  if tbl is null then raise exception 'Unknown record type %', ent; end if;
  if pid is null or id_ is null or length(id_) > 80 then raise exception 'The record needs its id and project'; end if;
  if not user_sees(me, pid) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
  execute format('select doc from %I where id = $1', tbl) into old using id_;
  if old is not null and old ->> 'project_id' <> pid then raise exception 'A record cannot move to another project'; end if;
  if ent in ('package','structure') and not (pt_boq(me, pid, 'boq.estimate') or pt_boq(me, pid, 'boq.upload')) then raise exception 'You cannot set up packages or structures on this project' using errcode = '42501'; end if;
  if ent = 'drawing' then
    if not (pt_boq(me, pid, 'boq.upload') or pt_boq(me, pid, 'boq.review') or pt_boq(me, pid, 'boq.estimate')) then raise exception 'You cannot change drawings on this project' using errcode = '42501'; end if;
    if old is not null and coalesce((old ->> 'reg')::boolean, false) then
      if (old ->> 'no', old ->> 'rev', old ->> 'sha', old ->> 'file') is distinct from (r ->> 'no', r ->> 'rev', r ->> 'sha', r ->> 'file') then raise exception 'A registered drawing revision keeps its number, revision and file; register a new revision instead'; end if;
      null;
      if not coalesce((old ->> 'superseded')::boolean, false) and coalesce((r ->> 'superseded')::boolean, false) and not pt_boq(me, pid, 'boq.review') then raise exception 'Only a lead engineer marks a drawing superseded' using errcode = '42501'; end if;
      if coalesce((old ->> 'superseded')::boolean, false) and not coalesce((r ->> 'superseded')::boolean, false) then raise exception 'A superseded drawing stays superseded'; end if;
      if coalesce((old ->> 'basis')::boolean, false) is distinct from coalesce((r ->> 'basis')::boolean, false) and not (pt_boq(me, pid, 'boq.estimate') or pt_boq(me, pid, 'boq.review')) then raise exception 'Only an estimator or a reviewer changes the estimation basis' using errcode = '42501'; end if;
    end if;
    -- v3.26.1: an approved, IFC or as-built status counts only when confirmed by a reviewer who neither registered the drawing nor set the status
    elig := coalesce((select (e ->> 'eligible')::boolean from boq_master m, jsonb_array_elements(m.doc -> 'dstatus') e where e ->> 'name' = r ->> 'doc_status'), false);
    if elig and coalesce((r ->> 'reg')::boolean, false) and coalesce((r ->> 'status_ok')::boolean, false)
       and (old is null or not coalesce((old ->> 'status_ok')::boolean, false) or (old ->> 'doc_status') is distinct from (r ->> 'doc_status')) then
      if not pt_boq(me, pid, 'boq.review') then raise exception 'Only a lead engineer (BOQ Engine reviewer) confirms a drawing status' using errcode = '42501'; end if;
      if rl <> 'sa' and (old is null or me::text in (coalesce(old ->> 'reg_by_id', ''), coalesce(old ->> 'status_set_by', '')) or (old ->> 'doc_status') is distinct from (r ->> 'doc_status')) then
        raise exception 'The person who registered the drawing or set its status does not confirm it; someone else confirms it'; end if;
      act := 'Drawing status confirmed'; end if;
  end if;
  if ent = 'dimension' and not pt_boq(me, pid, 'boq.upload') then raise exception 'Only a project engineer of this project changes dimensions' using errcode = '42501'; end if;
  if ent = 'calculation' then
    -- v3.26.1: a new calculation needs the estimator right; a recalculation follows from a change by anyone working on the project's estimate
    if not (pt_boq(me, pid, 'boq.estimate') or (old is not null and (pt_boq(me, pid, 'boq.review') or pt_boq(me, pid, 'boq.upload') or pt_boq(me, pid, 'boq.approve')))) then raise exception 'Only an estimator of this project prepares calculations' using errcode = '42501'; end if;
    if old is not null and (old ->> 'by_id') is distinct from (r ->> 'by_id') then raise exception 'A calculation keeps its author'; end if;
  end if;
  if ent = 'specification' and not (pt_boq(me, pid, 'boq.estimate') or pt_boq(me, pid, 'boq.upload') or pt_boq(me, pid, 'boq.review')) then raise exception 'You cannot change specifications on this project' using errcode = '42501'; end if;
  if ent = 'assumption' then
    if old is not null and (old ->> 'by_id') is distinct from (r ->> 'by_id') then raise exception 'An assumption keeps its author'; end if;
    if (old ->> 'review') is distinct from (r ->> 'review') and (r ->> 'review') <> 'Not reviewed' then
      if not pt_boq(me, pid, 'boq.review') then raise exception 'Only a lead engineer reviews assumptions' using errcode = '42501'; end if;
      if coalesce(old ->> 'by_id', r ->> 'by_id') = me::text and rl <> 'sa' then raise exception 'Someone other than its author reviews an assumption'; end if; act := 'Assumption reviewed'; end if;
    if (old ->> 'approval') is distinct from (r ->> 'approval') and (r ->> 'approval') in ('Approved','Rejected') then
      if not pt_boq(me, pid, 'boq.approve') then raise exception 'Only an estimation manager approves assumptions' using errcode = '42501'; end if;
      if coalesce(old ->> 'by_id', r ->> 'by_id') = me::text and rl <> 'sa' then raise exception 'Someone other than its author approves an assumption'; end if;
      if (r ->> 'review') <> 'Reviewed' then raise exception 'The assumption must be reviewed first'; end if; act := 'Assumption ' || lower(r ->> 'approval'); end if;
    if act = 'Saved' and not pt_boq(me, pid, 'boq.estimate') then raise exception 'Only an estimator records assumptions' using errcode = '42501'; end if;
  end if;
  if ent = 'estimate' then
    os := coalesce(old ->> 'status', 'Draft'); ns := r ->> 'status';
    if old is null and ns <> 'Draft' then raise exception 'A new estimate revision starts as a draft'; end if;
    if not (flow -> os) ? ns then raise exception 'An estimate cannot go from % to %', os, ns; end if;
    if os in ('Approved for Internal Use','Released','Superseded') and (old -> 'lines') is distinct from (r -> 'lines') then raise exception 'The lines of an approved or released revision never change; start a new revision'; end if;
    if old is null and not pt_boq(me, pid, 'boq.estimate') then raise exception 'Only an estimator starts an estimate revision' using errcode = '42501'; end if;
    -- v3.26.1: who prepared and submitted comes from the stored revision; nobody rewrites it
    if old is not null and (old ->> 'prepared_by') is distinct from (r ->> 'prepared_by') and (r ->> 'prepared_by') is distinct from me::text then raise exception 'The preparer of a revision is the person who generates it'; end if;
    if old is not null and (old ->> 'submitted_by') is distinct from (r ->> 'submitted_by') and not (ns = 'Ready for Review' and (r ->> 'submitted_by') = me::text) then raise exception 'The submitter is the person submitting'; end if;
    if old is not null and exists (select 1 from jsonb_array_elements_text(coalesce(old -> 'preparers', '[]'::jsonb)) x where not coalesce(r -> 'preparers', '[]'::jsonb) ? x) then raise exception 'A revision keeps the list of everyone who prepared it'; end if;
    if (old -> 'rates') is distinct from (r -> 'rates') then
      if os not in ('Draft','In Progress','Returned for Correction') then raise exception 'Rates are entered on a revision being prepared'; end if;
      if not pt_boq(me, pid, 'boq.rate') then raise exception 'Only a person with the rate right enters estimated rates' using errcode = '42501'; end if; end if;
    if ns in ('Draft','In Progress','Ready for Review') and ns <> os and not pt_boq(me, pid, 'boq.estimate')
       and not (os = 'Draft' and ns = 'In Progress' and (old -> 'lines') is not distinct from (r -> 'lines') and pt_boq(me, pid, 'boq.rate')) then raise exception 'Only an estimator prepares and submits estimates' using errcode = '42501'; end if;
    if ns = 'Ready for Review' and ns <> os and (r ->> 'submitted_by') is distinct from me::text then raise exception 'The submitter is the person submitting'; end if;
    if ns in ('Under Review','Approved for Internal Use','Released') and ns <> os and old is not null
       and (me::text in (coalesce(old ->> 'prepared_by',''), coalesce(old ->> 'submitted_by','')) or coalesce(old -> 'preparers', '[]'::jsonb) ? me::text) then
      raise exception 'You prepared or submitted this revision, so someone else reviews, approves or releases it'; end if;
    if ns = 'Under Review' and ns <> os and not pt_boq(me, pid, 'boq.review') then raise exception 'Only a lead engineer reviews estimates' using errcode = '42501'; end if;
    if ns = 'Returned for Correction' and ns <> os and not (pt_boq(me, pid, 'boq.review') or pt_boq(me, pid, 'boq.approve')) then raise exception 'Only a reviewer or an estimation manager returns an estimate' using errcode = '42501'; end if;
    if ns in ('Approved for Internal Use','Released') and ns <> os then
      if not pt_boq(me, pid, 'boq.approve') then raise exception 'Only an estimation manager approves and releases estimates' using errcode = '42501'; end if;
      if exists (select 1 from jsonb_array_elements(coalesce(r -> 'lines', '[]'::jsonb)) l where l ->> 'qty' is not null and l ->> 'qstat' <> 'Verified') then raise exception 'Every quantity must be verified before approval'; end if; end if;
    if ns = 'Superseded' and ns <> os and not (pt_boq(me, pid, 'boq.approve') and exists (select 1 from boq_estimates x where x.project_id = pid and x.doc ->> 'pkg_id' = r ->> 'pkg_id' and x.id <> id_ and x.doc ->> 'status' in ('Approved for Internal Use','Released'))) then
      raise exception 'A released revision is superseded only by the release of a newer one'; end if;
    act := case when ns <> os then 'Estimate ' || lower(ns) else 'Estimate saved' end;
  end if;
  if ent = 'handoff' then
    if old is not null then raise exception 'A hand-off is recorded once'; end if;
    if not pt_boq(me, pid, 'boq.approve') then raise exception 'Only an estimation manager hands an estimate to another module' using errcode = '42501'; end if;
    if not exists (select 1 from boq_estimates x where x.id = r ->> 'est_id' and x.project_id = pid and x.doc ->> 'status' = 'Released') then raise exception 'Only a released estimate can be handed over'; end if;
    r := jsonb_set(r, '{status}', '"Awaiting cost-control interface"'); act := 'Hand-off requested';
  end if;
  execute format('insert into %I (id, project_id, doc, updated_by) values ($1, $2, $3, $4) on conflict (id) do update set doc = excluded.doc, updated_by = excluded.updated_by, updated_at = now()', tbl) using id_, pid, r, me;
  -- v3.26.1: releasing a revision supersedes the package's earlier released one, in the same transaction
  if ent = 'estimate' and ns = 'Released' and os is distinct from 'Released' then
    update boq_estimates set doc = jsonb_set(doc, '{status}', '"Superseded"'), updated_by = me, updated_at = now()
     where project_id = pid and doc ->> 'pkg_id' = r ->> 'pkg_id' and id <> id_ and doc ->> 'status' = 'Released'; end if;
  insert into boq_audit (by_user, by_name, by_role, action, ent, ref, project_id, detail) values (me, who, rl, act, ent, id_, pid, jsonb_build_object('status', coalesce(r ->> 'status', r ->> 'doc_status')));
  return jsonb_build_object('ok', true, 'id', id_);
end $$;
revoke execute on function boq_save(jsonb), pt_boq(uuid, text, text) from public, anon;
grant execute on function boq_save(jsonb) to authenticated;

-- ------------------------------------------------------------------ 4. drawing files
insert into storage.buckets (id, name, public, file_size_limit)
values ('boq-drawings', 'boq-drawings', false, 52428800)
on conflict (id) do update set public = false, file_size_limit = 52428800;
-- path: boq/<project>/<record>/<file name>
create or replace function pt_boq_file_can(u uuid, path text, w boolean) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(split_part(path, '/', 1) = 'boq' and case when w then pt_boq(u, split_part(path, '/', 2), 'boq.upload') or pt_boq(u, split_part(path, '/', 2), 'boq.estimate')
    else user_sees(u, split_part(path, '/', 2)) end, false) $$;
drop policy if exists protrack_boq_read on storage.objects;
create policy protrack_boq_read on storage.objects for select to authenticated using (bucket_id = 'boq-drawings' and public.pt_boq_file_can(auth.uid(), name, false));
drop policy if exists protrack_boq_add on storage.objects;
create policy protrack_boq_add on storage.objects for insert to authenticated
  with check (bucket_id = 'boq-drawings' and array_length(string_to_array(name, '/'), 1) = 4 and name ~* '\.pdf$' and public.pt_boq_file_can(auth.uid(), name, true));
revoke execute on function pt_boq_file_can(uuid, text, boolean) from public, anon;
grant execute on function pt_boq_file_can(uuid, text, boolean) to authenticated;
