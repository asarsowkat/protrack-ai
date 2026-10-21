-- ProTrack schema rollback v21: back to the v3.11 Tender register rules on the server (schema-update-v7.sql).
-- tender_act no longer takes the bid position or the 'noa' action: the award date is typed into the Tender details
-- again, and the finance WBS date is no longer set. The right tender.noa leaves the list in Settings -> Roles and
-- rights, and tender_features() is removed, so live.html goes back to its v3.12 fallback (the NOA saved as the award
-- date). New stages take the v2.8 wording of stages 1 and 3 again.
-- Everything is kept: the columns bid_rank, rank_note, fwbs_on and noa_by with their values, every register and stage
-- history entry, the reworded checklists and any setting of tender.noa a super admin made. Run schema-update-v21.sql
-- again to use them again. Safe to run twice.

drop function if exists tender_features();

-- the right tender.noa leaves the list (the rest stays as it is)
do $$
declare cur text[] := pt_rights();
begin
  if 'tender.noa' = any(cur) then
    execute format('create or replace function pt_rights() returns text[] language sql immutable as $f$ select %L::text[] $f$',
                   array_remove(cur, 'tender.noa')::text);
  end if;
end $$;

-- pt_proj_guard: as in schema-update-v7.sql
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


-- pt_lc_template: as in schema-update-v7.sql
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


-- tender_act: as in schema-update-v7.sql
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


revoke execute on function pt_proj_guard(), pt_lc_template(int), tender_act(jsonb) from public, anon, authenticated;
grant execute on function tender_act(jsonb) to authenticated;
