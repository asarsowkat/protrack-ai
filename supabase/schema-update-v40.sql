-- ProTrack schema update v40 (ProTrackAI v3.36): the WBS master's order, SAP WBS ID and user field.
-- 1. Each WBS element can carry:
--    - its display order among its siblings;
--    - its SAP WBS segment (digits per level, 2-3-2 by default); a project's SAP WBS ID is the project's PE number and
--      the segments down the tree: PE-XXX-01 Site Management, PE-XXX-01-001 SM1 Salaries, PE-XXX-01-001-01 Salaries -
--      Project office team;
--    - its user field, from the user field list kept by the super admin (Settings → Supplement lists: SM, DE, TEC,
--      MTRL.ELC, MAN.ELC, INSTL.ELC, MTRL.MECH, MAN.MECH, INSTL.MECH, MTRL.CVL, MAN.CVL, INSTL.CVL, SAD, FNE, PC ITEMS,
--      PROV. SUM, CONT, MGT.RES …).
--    pt_bcm_check validates them; an approval refuses a SAP WBS segment already used under the same parent.
-- 2. The starting master follows the company user field list. The order and SAP segments are 01 SM … 16 MGT.RES, and
--    there are new elements: SM1-01 and SM1-02 (Salaries - Project office team, Site office team), Mechanical Material,
--    Mechanical Manpower, Mechanical inst, Prime Cost and Provisional Sum. Saudization, Financing, Contingency and
--    Management Reserve move to the top level, and "Other approved categories" is switched off.
--    These arrive as proposals of System seed:
--    - an element still waiting gets the change in its proposal;
--    - an approved element gets a new proposal (its approved version stays in force until approved);
--    - an element with a change waiting from a person is left alone, and the audit log says so.
--    Nothing is approved by this update.
-- Needs schema-update-v39.sql (and v35 for the user field list). Additive. Safe to run twice. Undo: schema-rollback-v40.sql.

do $$ begin
  if to_regprocedure('public.bcm_master_act(jsonb)') is null then raise exception 'Run schema-update-v39.sql (STAGE-33-SETUP) first, then this update'; end if;
end $$;

-- ------------------------------------------------------------------ validation and approval
create or replace function pt_bcm_check(e text, d jsonb, self text) returns void language plpgsql stable security definer set search_path = public as $$
declare c text; par text; n int := 0; v jsonb; lvl int := 1; dg jsonb; need int; seg text; uf text; pick text;
begin
  if jsonb_typeof(d) <> 'object' then raise exception 'Nothing to save'; end if;
  if length(d::text) > 60000 then raise exception 'The record is too large'; end if;
  if e = 'wbs' then
    c := d ->> 'code';
    if c is null or c !~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,29}$' then raise exception 'A WBS code is 1 to 30 letters, digits, dots, dashes or slashes (got "%")', coalesce(c, ''); end if;
    if length(coalesce(d ->> 'desc', '')) not between 2 and 200 then raise exception 'Give the WBS element a description of 2 to 200 characters'; end if;
    if exists (select 1 from bcm_master m where m.ent = 'wbs' and m.id <> coalesce(self, '') and (lower(m.cur ->> 'code') = lower(c) or lower(m.pend -> 'data' ->> 'code') = lower(c))) then
      raise exception 'The WBS code % is already used by another element', c; end if;
    par := d ->> 'parent';
    if par is not null then
      if not exists (select 1 from bcm_master where id = par and ent = 'wbs') then raise exception 'The parent element % does not exist', par; end if;
      -- no element may become its own ancestor
      while par is not null and n < 20 loop
        if par = self then raise exception 'An element cannot sit under itself'; end if;
        select coalesce(cur ->> 'parent', pend -> 'data' ->> 'parent') into par from bcm_master where id = par; n := n + 1; end loop; end if;
    if d ->> 'eff_from' is not null and d ->> 'eff_to' is not null and (d ->> 'eff_to')::date < (d ->> 'eff_from')::date then raise exception 'Effective-to is before effective-from'; end if;
    -- v3.36: display order, SAP WBS segment (digits per level, as the settings say) and user field (from the user field list)
    if d ->> 'order' is not null and (d ->> 'order') !~ '^[0-9]{1,5}$' then raise exception 'The order is a whole number from 0 to 99999'; end if;
    seg := nullif(btrim(coalesce(d ->> 'sap_seg', '')), '');
    if seg is not null then
      if seg !~ '^[0-9]{1,6}$' then raise exception 'A SAP WBS segment is 1 to 6 digits (got "%")', seg; end if;
      par := d ->> 'parent'; n := 0;
      while par is not null and n < 20 loop lvl := lvl + 1; select coalesce(pend -> 'data' ->> 'parent', cur ->> 'parent') into par from bcm_master where id = par; n := n + 1; end loop;
      dg := coalesce(pt_bcm_cfg() -> 'sap' -> 'digits', '[2,3,2]'::jsonb);
      need := (dg ->> (least(lvl, jsonb_array_length(dg)) - 1))::int;
      if length(seg) <> need then raise exception 'At level % the SAP WBS segment has % digits (got "%")', lvl, need, seg; end if;
    end if;
    uf := nullif(btrim(coalesce(d ->> 'user_field', '')), '');
    if uf is not null then
      if length(uf) > 40 then raise exception 'A user field is up to 40 characters'; end if;
      if to_regprocedure('public.pt_supp_lists()') is not null then
        execute 'select x ->> 0 from jsonb_array_elements(pt_supp_lists() -> ''uf'') x where lower(x ->> 0) = lower($1) limit 1' into pick using uf;
        if pick is null then raise exception 'The user field % is not in the user field list (Settings → Supplement lists)', uf; end if;
      end if;
    end if;
  elsif e in ('rule','map') then
    if not pt_bcm_wbs_ok(d ->> 'wbs_id') then raise exception 'Choose an approved, active, postable WBS element (got %)', coalesce(d ->> 'wbs_id', 'none'); end if;
    if d ->> 'cost_type' is not null and not (d ->> 'cost_type' = any(array['Material','Manpower','Equipment','Subcontract','Services','Overhead','Financing','Reserve','Other'])) then raise exception 'Unknown cost type %', d ->> 'cost_type'; end if;
    if e = 'rule' then
      if length(coalesce(d ->> 'name', '')) not between 2 and 120 then raise exception 'Give the rule a name'; end if;
      if coalesce(jsonb_array_length(d -> 'any'), 0) + coalesce(jsonb_array_length(d -> 'all'), 0) = 0 then raise exception 'A rule needs at least one phrase to match'; end if;
      if coalesce((d ->> 'strength')::numeric, 0.96) not between 0 and 1 then raise exception 'A rule strength is from 0 to 1'; end if;
      if coalesce((d ->> 'priority')::int, 0) not between 0 and 100 then raise exception 'A rule priority is from 0 to 100'; end if;
    else
      if not (d ->> 'scope' = any(array['project','ptype','global'])) then raise exception 'A mapping is for a project, a project type or global'; end if;
      if coalesce(d ->> 'key', d ->> 'item_code', '') = '' then raise exception 'A mapping needs a description or an item code'; end if;
      if d ->> 'scope' = 'project' and not exists (select 1 from projects where id = d ->> 'project_id') then raise exception 'Choose the project of a project mapping'; end if;
      if d ->> 'scope' = 'ptype' and coalesce(d ->> 'ptype', '') = '' then raise exception 'Choose the project type of a project-type mapping'; end if;
    end if;
  elsif e = 'cfg' then
    if coalesce((d ->> 'auto')::numeric, -1) not between 0.5 and 1 then raise exception 'The automatic threshold is from 50%% to 100%%'; end if;
    if coalesce((d ->> 'review')::numeric, -1) not between 0 and (d ->> 'auto')::numeric then raise exception 'The review threshold is from 0 to the automatic threshold'; end if;
    for v in select * from jsonb_array_elements(coalesce(d -> 'values', '[]'::jsonb)) loop
      if coalesce(v ->> 'cur', '') !~ '^[A-Z]{3}$' or (v ->> 'amount') is null or (v ->> 'amount')::numeric < 0 then raise exception 'Each value limit needs a currency and an amount of 0 or more'; end if; end loop;
  end if;
end $$;
create or replace function bcm_master_act(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; who text; rl text; act text := p ->> 'action'; e text := p ->> 'ent'; rid text := p ->> 'id'; d jsonb := p -> 'data'; m bcm_master; ids text[]; res jsonb := '[]'::jsonb; x text;
begin
  select * into u, who, rl from pt_bcm_me();
  if act = 'approve_many' then
    ids := array(select jsonb_array_elements_text(coalesce(p -> 'ids', '[]'::jsonb)));
    if array_length(ids, 1) > 300 then raise exception 'At most 300 at a time'; end if;
    foreach x in array coalesce(ids, '{}') loop
      begin perform bcm_master_act(jsonb_build_object('action', 'approve', 'id', x, 'note', p ->> 'note')); res := res || jsonb_build_object('id', x, 'ok', true);
      exception when others then res := res || jsonb_build_object('id', x, 'ok', false, 'error', sqlerrm); end; end loop;
    return jsonb_build_object('results', res);
  end if;
  if act = 'propose' then
    -- a reviewer may propose a mapping from a decision (approval is still someone else's); everything else needs bcm.master
    if not (pt_bcm(u, null, 'bcm.master') or (e = 'map' and pt_bcm(u, case when d ->> 'scope' = 'project' then d ->> 'project_id' end, 'bcm.review'))) then
      raise exception 'You cannot propose master-data changes (the bcm.master right)' using errcode = '42501'; end if;
    if not (e = any(array['wbs','rule','map','cfg'])) then raise exception 'Unknown record type %', e; end if;
    if e = 'cfg' then rid := 'cfg'; end if;
    if rid is null then rid := case e when 'wbs' then 'W-' when 'rule' then 'R-' else 'M-' end || substr(md5(random()::text || clock_timestamp()::text), 1, 8); end if;
    select * into m from bcm_master where id = rid;
    if m.id is not null and m.ent <> e then raise exception 'That record is not a %', e; end if;
    if e = 'map' and d ->> 'scope' = 'project' and not user_sees(u, d ->> 'project_id') then raise exception 'You do not have access to that project' using errcode = '42501'; end if;
    perform pt_bcm_check(e, d, rid);
    insert into bcm_master (id, ent, ver, cur, pend, status, updated_by) values (rid, e, 0, null, null, 'Proposed', u) on conflict (id) do nothing;
    update bcm_master set pend = jsonb_build_object('data', d, 'by', u::text, 'by_name', who, 'at', now(), 'note', left(p ->> 'note', 500)),
      status = case when cur is null then 'Proposed' else status end, updated_by = u, updated_at = now() where id = rid;
    insert into bcm_master_hist (ref, ent, action, ver, data, proposed_by, proposed_by_name, proposed_at, decided_by, decided_by_name, note) values (rid, e, 'Proposed', null, d, u::text, who, now(), u, who, left(p ->> 'note', 500));
    perform pt_bcm_log(u, who, rl, 'Change proposed', e, rid, case when e = 'map' then d ->> 'project_id' end, jsonb_build_object('note', p ->> 'note'));
    return jsonb_build_object('ok', true, 'id', rid);
  end if;
  select * into m from bcm_master where id = rid for update;
  if m.id is null then raise exception 'Unknown record %', rid; end if;
  if m.pend is null then raise exception 'Nothing is waiting for approval on %', rid; end if;
  if act = 'approve' then
    if not pt_bcm(u, null, 'bcm.approve') then raise exception 'You cannot approve master-data changes (the bcm.approve right)' using errcode = '42501'; end if;
    if m.pend ->> 'by' = u::text then raise exception 'You proposed this change, so someone else approves it'; end if;
    perform pt_bcm_check(m.ent, m.pend -> 'data', m.id);
    if m.ent = 'wbs' and exists (select 1 from bcm_master o where o.ent = 'wbs' and o.id <> m.id and lower(o.cur ->> 'code') = lower(m.pend -> 'data' ->> 'code')) then raise exception 'Another approved element already has the code %', m.pend -> 'data' ->> 'code'; end if;
    if m.ent = 'wbs' and m.pend -> 'data' ->> 'parent' is not null and not exists (select 1 from bcm_master where id = m.pend -> 'data' ->> 'parent' and cur is not null) then raise exception 'Approve the parent element % first', m.pend -> 'data' ->> 'parent'; end if;
    -- v3.36: a SAP WBS segment is used once under a parent (siblings moving away in a waiting change do not count)
    if m.ent = 'wbs' and nullif(m.pend -> 'data' ->> 'sap_seg', '') is not null and exists (select 1 from bcm_master o where o.ent = 'wbs' and o.id <> m.id and o.cur is not null
        and coalesce((o.cur ->> 'active')::boolean, true) and coalesce(o.cur ->> 'parent', '') = coalesce(m.pend -> 'data' ->> 'parent', '') and o.cur ->> 'sap_seg' = m.pend -> 'data' ->> 'sap_seg'
        and (o.pend is null or (o.pend -> 'data' ->> 'sap_seg' is not distinct from o.cur ->> 'sap_seg' and coalesce(o.pend -> 'data' ->> 'parent', '') = coalesce(o.cur ->> 'parent', '')))) then
      raise exception 'The SAP WBS segment % is already used under the same parent; give one of them another segment', m.pend -> 'data' ->> 'sap_seg'; end if;
    update bcm_master set cur = m.pend -> 'data', ver = m.ver + 1, pend = null, status = 'Approved', updated_by = u, updated_at = now() where id = m.id;
    insert into bcm_master_hist (ref, ent, action, ver, data, proposed_by, proposed_by_name, proposed_at, decided_by, decided_by_name, note)
      values (m.id, m.ent, 'Approved', m.ver + 1, m.pend -> 'data', m.pend ->> 'by', m.pend ->> 'by_name', (m.pend ->> 'at')::timestamptz, u, who, left(p ->> 'note', 500));
    perform pt_bcm_log(u, who, rl, 'Change approved', m.ent, m.id, case when m.ent = 'map' then m.pend -> 'data' ->> 'project_id' end, jsonb_build_object('version', m.ver + 1));
    return jsonb_build_object('ok', true, 'id', m.id, 'ver', m.ver + 1);
  elsif act = 'reject' then
    if not (pt_bcm(u, null, 'bcm.approve') or m.pend ->> 'by' = u::text) then raise exception 'Only an approver rejects a change (or its proposer withdraws it)' using errcode = '42501'; end if;
    if length(coalesce(p ->> 'note', '')) < 3 then raise exception 'Give the reason'; end if;
    update bcm_master set pend = null, status = case when cur is null then 'Rejected' else 'Approved' end, updated_by = u, updated_at = now() where id = m.id;
    insert into bcm_master_hist (ref, ent, action, ver, data, proposed_by, proposed_by_name, proposed_at, decided_by, decided_by_name, note)
      values (m.id, m.ent, case when m.pend ->> 'by' = u::text then 'Withdrawn' else 'Rejected' end, null, m.pend -> 'data', m.pend ->> 'by', m.pend ->> 'by_name', (m.pend ->> 'at')::timestamptz, u, who, left(p ->> 'note', 500));
    perform pt_bcm_log(u, who, rl, 'Change rejected', m.ent, m.id, null, jsonb_build_object('note', p ->> 'note'));
    return jsonb_build_object('ok', true, 'id', m.id);
  end if;
  raise exception 'Unknown action %', act;
end $$;


-- ------------------------------------------------------------------ the starting master in the company's layout (proposals only)
create or replace function pt_bcm_seed_upd(rid text, ch jsonb, full_ jsonb) returns text language plpgsql security definer set search_path = public as $$
declare m bcm_master; base jsonb; nd jsonb; nt text := 'System seed (v3.36): order, SAP WBS segment and user field from the company user field list. Check before approving.';
begin
  select * into m from bcm_master where id = rid;
  if m.id is null then
    if full_ is null then return 'not found'; end if;
    insert into bcm_master (id, ent, ver, cur, pend, status) values (rid, 'wbs', 0, null, jsonb_build_object('data', full_, 'by', 'system', 'by_name', 'System seed (working definition)', 'at', now(), 'note', nt), 'Proposed');
    insert into bcm_master_hist (ref, ent, action, data, proposed_by, proposed_by_name, proposed_at, decided_by_name, note) values (rid, 'wbs', 'Proposed', full_, 'system', 'System seed (working definition)', now(), 'System seed', nt);
    return 'added';
  end if;
  if full_ is not null then return 'exists'; end if;
  if m.pend is not null and m.pend ->> 'by' <> 'system' then
    insert into bcm_audit (by_name, action, ent, ref, detail) values ('System seed', 'Seed update not applied: a change from a person is waiting', 'wbs', rid, jsonb_build_object('change', ch));
    return 'left (a change from a person is waiting)';
  end if;
  base := coalesce(m.pend -> 'data', m.cur); nd := base || ch;
  if nd = base or (m.pend is null and nd = m.cur) then return 'already'; end if;
  update bcm_master set pend = jsonb_build_object('data', nd, 'by', 'system', 'by_name', 'System seed (v3.36 structure)', 'at', now(), 'note', nt),
    status = case when cur is null then 'Proposed' else status end, updated_at = now() where id = rid;
  insert into bcm_master_hist (ref, ent, action, data, proposed_by, proposed_by_name, proposed_at, decided_by_name, note) values (rid, 'wbs', 'Proposed', nd, 'system', 'System seed (v3.36 structure)', now(), 'System seed', nt);
  return case when m.cur is null then 'proposal updated' else 'proposed (approved version stays until approved)' end;
end $$;
revoke execute on function pt_bcm_seed_upd(text, jsonb, jsonb) from public, anon, authenticated;
do $$
declare r jsonb := '{}'::jsonb;
begin
  r := r || jsonb_build_object('W-SM', pt_bcm_seed_upd('W-SM', '{"order": 10, "sap_seg": "01", "user_field": "SM"}'::jsonb, null));
  r := r || jsonb_build_object('W-SM1', pt_bcm_seed_upd('W-SM1', '{"order": 10, "sap_seg": "001", "user_field": "SM"}'::jsonb, null));
  r := r || jsonb_build_object('W-SM2', pt_bcm_seed_upd('W-SM2', '{"order": 20, "sap_seg": "002", "user_field": "SM"}'::jsonb, null));
  r := r || jsonb_build_object('W-SM3', pt_bcm_seed_upd('W-SM3', '{"order": 30, "sap_seg": "003", "user_field": "SM"}'::jsonb, null));
  r := r || jsonb_build_object('W-SM4', pt_bcm_seed_upd('W-SM4', '{"order": 40, "sap_seg": "004", "user_field": "SM"}'::jsonb, null));
  r := r || jsonb_build_object('W-SM5', pt_bcm_seed_upd('W-SM5', '{"order": 50, "sap_seg": "005", "user_field": "SM"}'::jsonb, null));
  r := r || jsonb_build_object('W-SM6', pt_bcm_seed_upd('W-SM6', '{"order": 60, "sap_seg": "006", "user_field": "SM"}'::jsonb, null));
  r := r || jsonb_build_object('W-SM7', pt_bcm_seed_upd('W-SM7', '{"order": 70, "sap_seg": "007", "user_field": "SM"}'::jsonb, null));
  r := r || jsonb_build_object('W-SM8', pt_bcm_seed_upd('W-SM8', '{"order": 80, "sap_seg": "008", "user_field": "SM"}'::jsonb, null));
  r := r || jsonb_build_object('W-SM9', pt_bcm_seed_upd('W-SM9', '{"order": 90, "sap_seg": "009", "user_field": "SM"}'::jsonb, null));
  r := r || jsonb_build_object('W-DES', pt_bcm_seed_upd('W-DES', '{"order": 20, "sap_seg": "02", "user_field": "DE"}'::jsonb, null));
  r := r || jsonb_build_object('W-DES-01', pt_bcm_seed_upd('W-DES-01', '{"order": 10, "sap_seg": "001", "user_field": "DE"}'::jsonb, null));
  r := r || jsonb_build_object('W-DES-02', pt_bcm_seed_upd('W-DES-02', '{"order": 20, "sap_seg": "002", "user_field": "DE"}'::jsonb, null));
  r := r || jsonb_build_object('W-DES-03', pt_bcm_seed_upd('W-DES-03', '{"order": 30, "sap_seg": "003", "user_field": "DE"}'::jsonb, null));
  r := r || jsonb_build_object('W-DES-09', pt_bcm_seed_upd('W-DES-09', '{"order": 90, "sap_seg": "009", "user_field": "DE"}'::jsonb, null));
  r := r || jsonb_build_object('W-ELM', pt_bcm_seed_upd('W-ELM', '{"order": 40, "sap_seg": "04", "user_field": "MTRL.ELC"}'::jsonb, null));
  r := r || jsonb_build_object('W-ELM-01', pt_bcm_seed_upd('W-ELM-01', '{"order": 10, "sap_seg": "001", "user_field": "MTRL.ELC"}'::jsonb, null));
  r := r || jsonb_build_object('W-ELM-02', pt_bcm_seed_upd('W-ELM-02', '{"order": 20, "sap_seg": "002", "user_field": "MTRL.ELC"}'::jsonb, null));
  r := r || jsonb_build_object('W-ELM-03', pt_bcm_seed_upd('W-ELM-03', '{"order": 30, "sap_seg": "003", "user_field": "MTRL.ELC"}'::jsonb, null));
  r := r || jsonb_build_object('W-ELM-04', pt_bcm_seed_upd('W-ELM-04', '{"order": 40, "sap_seg": "004", "user_field": "MTRL.ELC"}'::jsonb, null));
  r := r || jsonb_build_object('W-ELM-05', pt_bcm_seed_upd('W-ELM-05', '{"order": 50, "sap_seg": "005", "user_field": "MTRL.ELC"}'::jsonb, null));
  r := r || jsonb_build_object('W-ELM-09', pt_bcm_seed_upd('W-ELM-09', '{"order": 90, "sap_seg": "009", "user_field": "MTRL.ELC"}'::jsonb, null));
  r := r || jsonb_build_object('W-ELP', pt_bcm_seed_upd('W-ELP', '{"order": 50, "sap_seg": "05", "user_field": "MAN.ELC"}'::jsonb, null));
  r := r || jsonb_build_object('W-ELP-01', pt_bcm_seed_upd('W-ELP-01', '{"order": 10, "sap_seg": "001", "user_field": "MAN.ELC"}'::jsonb, null));
  r := r || jsonb_build_object('W-ELP-02', pt_bcm_seed_upd('W-ELP-02', '{"order": 20, "sap_seg": "002", "user_field": "MAN.ELC"}'::jsonb, null));
  r := r || jsonb_build_object('W-ELP-03', pt_bcm_seed_upd('W-ELP-03', '{"order": 30, "sap_seg": "003", "user_field": "MAN.ELC"}'::jsonb, null));
  r := r || jsonb_build_object('W-ELP-04', pt_bcm_seed_upd('W-ELP-04', '{"order": 40, "sap_seg": "004", "user_field": "MAN.ELC"}'::jsonb, null));
  r := r || jsonb_build_object('W-ELE', pt_bcm_seed_upd('W-ELE', '{"order": 60, "sap_seg": "06", "user_field": "INSTL.ELC"}'::jsonb, null));
  r := r || jsonb_build_object('W-TC', pt_bcm_seed_upd('W-TC', '{"order": 30, "sap_seg": "03", "user_field": "TEC"}'::jsonb, null));
  r := r || jsonb_build_object('W-TC-01', pt_bcm_seed_upd('W-TC-01', '{"order": 10, "sap_seg": "001", "user_field": "TEC"}'::jsonb, null));
  r := r || jsonb_build_object('W-TC-02', pt_bcm_seed_upd('W-TC-02', '{"order": 20, "sap_seg": "002", "user_field": "TEC"}'::jsonb, null));
  r := r || jsonb_build_object('W-TC-03', pt_bcm_seed_upd('W-TC-03', '{"order": 30, "sap_seg": "003", "user_field": "TEC"}'::jsonb, null));
  r := r || jsonb_build_object('W-TC-04', pt_bcm_seed_upd('W-TC-04', '{"order": 40, "sap_seg": "004", "user_field": "TEC"}'::jsonb, null));
  r := r || jsonb_build_object('W-TC-05', pt_bcm_seed_upd('W-TC-05', '{"order": 50, "sap_seg": "005", "user_field": "TEC"}'::jsonb, null));
  r := r || jsonb_build_object('W-CIV', pt_bcm_seed_upd('W-CIV', '{"order": 100, "sap_seg": "10", "user_field": null}'::jsonb, null));
  r := r || jsonb_build_object('W-CIV-01', pt_bcm_seed_upd('W-CIV-01', '{"order": 10, "sap_seg": "001", "user_field": null}'::jsonb, null));
  r := r || jsonb_build_object('W-CIV-02', pt_bcm_seed_upd('W-CIV-02', '{"order": 20, "sap_seg": "002", "user_field": null}'::jsonb, null));
  r := r || jsonb_build_object('W-CIV-03', pt_bcm_seed_upd('W-CIV-03', '{"order": 30, "sap_seg": "003", "user_field": null}'::jsonb, null));
  r := r || jsonb_build_object('W-CIV-04', pt_bcm_seed_upd('W-CIV-04', '{"order": 40, "sap_seg": "004", "user_field": null}'::jsonb, null));
  r := r || jsonb_build_object('W-CIV-05', pt_bcm_seed_upd('W-CIV-05', '{"order": 50, "sap_seg": "005", "user_field": "MTRL.CVL"}'::jsonb, null));
  r := r || jsonb_build_object('W-CIV-06', pt_bcm_seed_upd('W-CIV-06', '{"order": 60, "sap_seg": "006", "user_field": "MTRL.CVL"}'::jsonb, null));
  r := r || jsonb_build_object('W-CIV-07', pt_bcm_seed_upd('W-CIV-07', '{"order": 70, "sap_seg": "007", "user_field": "MTRL.CVL"}'::jsonb, null));
  r := r || jsonb_build_object('W-CIV-08', pt_bcm_seed_upd('W-CIV-08', '{"order": 80, "sap_seg": "008", "user_field": "MAN.CVL"}'::jsonb, null));
  r := r || jsonb_build_object('W-CIV-09', pt_bcm_seed_upd('W-CIV-09', '{"order": 90, "sap_seg": "009", "user_field": "INSTL.CVL"}'::jsonb, null));
  r := r || jsonb_build_object('W-CIV-10', pt_bcm_seed_upd('W-CIV-10', '{"order": 100, "sap_seg": "010", "user_field": null}'::jsonb, null));
  r := r || jsonb_build_object('W-SAU', pt_bcm_seed_upd('W-SAU', '{"order": 110, "sap_seg": "11", "user_field": "SAD", "parent": null}'::jsonb, null));
  r := r || jsonb_build_object('W-FIN', pt_bcm_seed_upd('W-FIN', '{"order": 120, "sap_seg": "12", "user_field": "FNE", "parent": null}'::jsonb, null));
  r := r || jsonb_build_object('W-CON', pt_bcm_seed_upd('W-CON', '{"order": 150, "sap_seg": "15", "user_field": "CONT", "parent": null}'::jsonb, null));
  r := r || jsonb_build_object('W-MR', pt_bcm_seed_upd('W-MR', '{"order": 160, "sap_seg": "16", "user_field": "MGT.RES", "parent": null}'::jsonb, null));
  r := r || jsonb_build_object('W-OTH', pt_bcm_seed_upd('W-OTH', '{"active": false, "postable": false, "order": 990, "sap_seg": null, "user_field": null}'::jsonb, null));
  r := r || jsonb_build_object('W-SM1-01', pt_bcm_seed_upd('W-SM1-01', null, '{"code": "SM1-01", "parent": "W-SM1", "desc": "Salaries - Project office team", "aliases": ["project office team", "head office staff"], "keywords": ["project office", "salaries", "staff"], "cost_category": "Overhead", "ptypes": [], "eff_from": null, "eff_to": null, "active": true, "postable": true, "mandatory_review": false, "order": 10, "sap_seg": "01", "user_field": "SM"}'::jsonb));
  r := r || jsonb_build_object('W-SM1-02', pt_bcm_seed_upd('W-SM1-02', null, '{"code": "SM1-02", "parent": "W-SM1", "desc": "Salaries - Site office team", "aliases": ["site office team", "site staff salaries"], "keywords": ["site office", "salaries", "staff"], "cost_category": "Overhead", "ptypes": [], "eff_from": null, "eff_to": null, "active": true, "postable": true, "mandatory_review": false, "order": 20, "sap_seg": "02", "user_field": "SM"}'::jsonb));
  r := r || jsonb_build_object('W-MEM', pt_bcm_seed_upd('W-MEM', null, '{"code": "MEM", "parent": null, "desc": "Mechanical Material", "aliases": ["mechanical material", "HVAC material", "piping material"], "keywords": ["mechanical", "hvac", "piping", "pumps", "valves", "ducts"], "cost_category": "Material", "ptypes": [], "eff_from": null, "eff_to": null, "active": true, "postable": true, "mandatory_review": false, "order": 70, "sap_seg": "07", "user_field": "MTRL.MECH"}'::jsonb));
  r := r || jsonb_build_object('W-MEP', pt_bcm_seed_upd('W-MEP', null, '{"code": "MEP", "parent": null, "desc": "Mechanical Manpower", "aliases": ["mechanical manpower", "mechanical crew"], "keywords": ["mechanical", "fitters", "plumbers", "hvac technicians", "crew"], "cost_category": "Manpower", "ptypes": [], "eff_from": null, "eff_to": null, "active": true, "postable": true, "mandatory_review": false, "order": 80, "sap_seg": "08", "user_field": "MAN.MECH"}'::jsonb));
  r := r || jsonb_build_object('W-MEI', pt_bcm_seed_upd('W-MEI', null, '{"code": "MEI", "parent": null, "desc": "Mechanical inst", "aliases": ["mechanical installation", "mechanical equipment"], "keywords": ["mechanical", "installation", "equipment"], "cost_category": "Equipment", "ptypes": [], "eff_from": null, "eff_to": null, "active": true, "postable": true, "mandatory_review": false, "order": 90, "sap_seg": "09", "user_field": "INSTL.MECH"}'::jsonb));
  r := r || jsonb_build_object('W-PC', pt_bcm_seed_upd('W-PC', null, '{"code": "PC", "parent": null, "desc": "Prime Cost", "aliases": ["prime cost", "PC items", "PC sum"], "keywords": ["prime cost", "pc sum", "pc items"], "cost_category": "Other", "ptypes": [], "eff_from": null, "eff_to": null, "active": true, "postable": true, "mandatory_review": true, "order": 130, "sap_seg": "13", "user_field": "PC ITEMS"}'::jsonb));
  r := r || jsonb_build_object('W-PS', pt_bcm_seed_upd('W-PS', null, '{"code": "PS", "parent": null, "desc": "Provisional Sum", "aliases": ["provisional sum", "PS items"], "keywords": ["provisional sum", "provisional"], "cost_category": "Other", "ptypes": [], "eff_from": null, "eff_to": null, "active": true, "postable": true, "mandatory_review": true, "order": 140, "sap_seg": "14", "user_field": "PROV. SUM"}'::jsonb));
  insert into bcm_audit (by_name, action, ent, detail) values ('System seed', 'Starting master updated to the company layout (v3.36)', 'wbs', r);
end $$;
create or replace function bcm_features() returns jsonb language sql stable as $$ select '{"version": 40, "stages": [1, 2], "sap_wbs": true}'::jsonb $$;
grant execute on function bcm_features() to authenticated;
