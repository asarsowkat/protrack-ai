-- ProTrack rollback of schema update v40 (ProTrackAI v3.36): back to the v39 checks of the WBS master.
-- The order, SAP WBS segment and user field stay in the records (unused by the checks); proposals made by v40 stay
-- waiting and can be rejected in WBS Mapping Master. Safe to run even if v40 was never applied.
drop function if exists pt_bcm_seed_upd(text, jsonb, jsonb);
create or replace function pt_bcm_check(e text, d jsonb, self text) returns void language plpgsql stable security definer set search_path = public as $$
declare c text; par text; n int := 0; v jsonb;
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


create or replace function bcm_features() returns jsonb language sql stable as $$ select '{"version": 39, "stages": [1, 2]}'::jsonb $$;
revoke execute on function pt_bcm_check(text, jsonb, text) from public, anon, authenticated;
grant execute on function bcm_master_act(jsonb), bcm_features() to authenticated;
