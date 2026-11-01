-- Undo schema update v52: the v51 functions again, and the mapping without its invoicing weight and source.
-- Mappings stay; items then earn on the schedule weight of all their activities, as in v51.
create or replace function pt_cib_prog(pid text, su uuid, item text, r jsonb, upto date) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare w numeric; s numeric; n int; a numeric; rv record;
begin
  if r ->> 't' in ('tcc','fac') then return jsonb_build_object('p', 0, 'src', 'ms', 'n', 0); end if;
  if r ->> 't' = 'phase' then
    select coalesce(sum(coalesce((x ->> 'pct')::numeric, 0)), 0) / 100, count(*) into s, n from jsonb_array_elements(r -> 'steps') x
      where exists (select 1 from schedule_update_rows z where z.update_id = su and z.act_id = btrim(x ->> 'act') and (z.pct >= 100 or z.af <= upto));
    return jsonb_build_object('p', least(greatest(s, 0), 1), 'src', 'steps', 'n', n); end if;
  select sum(greatest(z.w, 0)), sum(greatest(z.w, 0) * z.pct), count(*), avg(z.pct) into w, s, n, a
    from schedule_update_rows z join cib_maps m on m.project_id = z.project_id and m.act_id = z.act_id where z.update_id = su and m.project_id = pid and m.item_no = item;
  if n > 0 then return jsonb_build_object('p', round(least(greatest(case when w > 0 then s / w / 100 else a / 100 end, 0), 1), 6), 'src', 'p6', 'n', n); end if;
  select * into rv from cib_map_reviews where project_id = pid and item_no = item;
  if rv.decision = 'manual' then return jsonb_build_object('p', rv.pct / 100, 'src', 'manual', 'n', 0); end if;
  if rv.decision = 'zero' then return jsonb_build_object('p', 0, 'src', 'zero', 'n', 0); end if;
  return jsonb_build_object('p', 0, 'src', 'none', 'n', 0);
end $$;
create or replace function pt_cib_compute(pid text, sch text, seq_no int, pfrom date, upto date) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare S record; it record; su uuid; dd date; tcc boolean; fac boolean; prev record; pl jsonb := '{}'::jsonb; pp jsonb := '{}'::jsonb; pt jsonb := '{}'::jsonb;
  lines jsonb := '[]'::jsonb; exc jsonb := '[]'::jsonb; r jsonb; g jsonb; v numeric; lim numeric; raw numeric; cum numeric; pv numeric; rev boolean;
  gthis numeric := 0; gprev numeric := 0; h jsonb; cv numeric; retcap numeric; retprev numeric; retthis numeric; retheld numeric; reltcc boolean; relfac boolean; relthis numeric;
  advamt numeric; advprev numeric; advthis numeric; net numeric; vat numeric; miss int := 0; missv numeric := 0; over int := 0; nrev int := 0; man int := 0; x record;
begin
  select * into S from cib_schedules where id = sch and project_id = pid; h := S.head; cv := coalesce((h ->> 'value')::numeric, 0);
  select id, data_date into su, dd from schedule_updates where project_id = pid and data_date <= upto order by data_date desc, uploaded_at desc limit 1;
  tcc := exists (select 1 from milestones where project_id = pid and ms_type = 'TCC' and actual is not null and actual <= upto);
  fac := exists (select 1 from milestones where project_id = pid and ms_type = 'FAC' and actual is not null and actual <= upto);
  select * into prev from cib_invoices where project_id = pid and status in ('Certified','Paid') and seq < seq_no order by seq desc limit 1;
  if prev.id is not null then
    select coalesce(jsonb_object_agg(l ->> 'no', coalesce(l -> 'cert_cum', l -> 'cum_pay')), '{}'::jsonb), coalesce(jsonb_object_agg(l ->> 'no', l -> 'prog'), '{}'::jsonb) into pl, pp from jsonb_array_elements(prev.data -> 'lines') l;
    pt := coalesce(prev.data -> 'tot', '{}'::jsonb); end if;
  for it in select * from cib_items where schedule_id = sch and (data ->> 'leaf')::boolean and data ->> 'st' = 'Active' and coalesce((data ->> 'value')::numeric, 0) > 0 order by seq loop
    v := (it.data ->> 'value')::numeric; r := pt_cib_rule(S.rules, it.data ->> 'comp', case when jsonb_typeof(it.data -> 'rule') = 'object' then it.data -> 'rule' else null end);
    g := case when su is null then jsonb_build_object('p', 0, 'src', 'none', 'n', 0) else pt_cib_prog(pid, su, it.item_no, r, upto) end;
    if su is null and r ->> 't' in ('tcc','fac') then g := jsonb_build_object('p', 0, 'src', 'ms', 'n', 0); end if;
    lim := v * coalesce((it.data ->> 'limit')::numeric, 100) / 100; raw := pt_cib_pay(r, v, (g ->> 'p')::numeric, tcc, fac);
    cum := round(least(raw, lim), 2); pv := round(coalesce((pl ->> it.item_no)::numeric, 0), 2); rev := cum < pv - 0.5; if rev then cum := pv; nrev := nrev + 1; end if;
    if raw > lim + 0.5 then over := over + 1; end if;
    if g ->> 'src' = 'none' and r ->> 't' in ('pct','split') then miss := miss + 1; missv := missv + v; end if;
    if g ->> 'src' = 'none' and r ->> 't' = 'phase' then miss := miss + 1; missv := missv + v; end if;
    if g ->> 'src' = 'manual' and cum - pv > 0 then man := man + 1; end if;
    lines := lines || jsonb_build_object('no', it.item_no, 'desc', it.data ->> 'desc', 'comp', it.data ->> 'comp', 'unit', coalesce(it.data ->> 'unit', ''), 'qty', coalesce((it.data ->> 'qty')::numeric, 0),
      'rate', coalesce((it.data ->> 'rate')::numeric, 0), 'value', v, 'rule', r ->> 't', 'prog', (g ->> 'p')::numeric, 'src', g ->> 'src', 'acts', (g ->> 'n')::int, 'cum_pay', cum, 'prev_pay', pv,
      'this_pay', round(cum - pv, 2), 'over', raw > lim + 0.5, 'rev', rev, 'prev_pct', case when v > 0 then pv / v else 0 end, 'prev_prog', pp -> it.item_no);
    gthis := gthis + round(cum - pv, 2); gprev := gprev + pv;
  end loop;
  -- an item a phase rule bills is Missing while one of its step activities is not in the schedule (as the browser's audit)
  for x in select i.item_no, (i.data ->> 'value')::numeric vv from cib_items i where i.schedule_id = sch and (i.data ->> 'leaf')::boolean and i.data ->> 'st' = 'Active' and (i.data ->> 'value')::numeric > 0
      and pt_cib_rule(S.rules, i.data ->> 'comp', case when jsonb_typeof(i.data -> 'rule') = 'object' then i.data -> 'rule' else null end) ->> 't' = 'phase'
      and exists (select 1 from jsonb_array_elements(pt_cib_rule(S.rules, i.data ->> 'comp', i.data -> 'rule') -> 'steps') st where su is null or not exists (select 1 from schedule_update_rows z where z.update_id = su and z.act_id = btrim(st ->> 'act')))
  loop miss := miss + 1; missv := missv + x.vv; end loop;
  gthis := round(gthis, 2); gprev := round(gprev, 2);
  retcap := cv * coalesce(nullif(h ->> 'ret_cap', '')::numeric, 100) / 100; retprev := coalesce((pt ->> 'ret_cum')::numeric, 0);
  retthis := round(least(gthis * coalesce((h ->> 'ret_pct')::numeric, 0) / 100, greatest(0, retcap - retprev)), 2); retheld := retprev + retthis;
  reltcc := tcc and not coalesce((pt ->> 'rel_tcc')::boolean, false) and coalesce((h ->> 'ret_tcc')::numeric, 0) > 0;
  relfac := fac and not coalesce((pt ->> 'rel_fac')::boolean, false) and coalesce((h ->> 'ret_fac')::numeric, 0) > 0;
  relthis := round(case when reltcc then retheld * (h ->> 'ret_tcc')::numeric / 100 else 0 end + case when relfac then retheld * (h ->> 'ret_fac')::numeric / 100 else 0 end, 2);
  advamt := cv * coalesce((h ->> 'adv_pct')::numeric, 0) / 100; advprev := coalesce((pt ->> 'adv_cum')::numeric, 0);
  advthis := round(least(gthis * coalesce((h ->> 'adv_rec')::numeric, 0) / 100, greatest(0, advamt - advprev)), 2);
  net := round(gthis - retthis + relthis - advthis, 2); vat := round(net * coalesce((h ->> 'vat')::numeric, 0) / 100, 2);
  if miss > 0 then exc := exc || jsonb_build_object('k', 'unmapped', 'sev', 'block', 'msg', miss || ' price schedule item(s) not mapped: SAR ' || to_char(missv, 'FM999,999,999,990.00') || '. Map them or record their review in the mapping audit.'); end if;
  if su is null then exc := exc || jsonb_build_object('k', 'p6', 'sev', 'block', 'msg', 'No updated P6 schedule with a data date on or before the period end');
  elsif dd < pfrom then exc := exc || jsonb_build_object('k', 'p6', 'sev', 'block', 'msg', 'The latest updated schedule (data date ' || dd || ') is older than the period start ' || pfrom || ': load this period''s update first');
  elsif upto - dd > 35 then exc := exc || jsonb_build_object('k', 'p6', 'sev', 'warn', 'msg', 'The updated schedule is ' || (upto - dd) || ' days older than the period end'); end if;
  if over > 0 then exc := exc || jsonb_build_object('k', 'over', 'sev', 'warn', 'msg', over || ' item(s) reach the invoice limit; the claim is held at the limit'); end if;
  if nrev > 0 then exc := exc || jsonb_build_object('k', 'reversal', 'sev', 'warn', 'msg', 'Schedule reversal: ' || nrev || ' item(s) earn less than already certified; nothing is claimed for them this period'); end if;
  if gprev + gthis > cv + 0.5 then exc := exc || jsonb_build_object('k', 'cv', 'sev', 'block', 'msg', 'Certified to date exceeds the contract value'); end if;
  if exists (select 1 from cib_invoices o where o.project_id = pid and o.seq < seq_no and o.status in ('Draft','Submitted','Reviewed','Approved','Issued')) then
    exc := exc || jsonb_build_object('k', 'dup', 'sev', 'block', 'msg', 'An earlier invoice is not yet certified: claim again only after its certificate'); end if;
  if exists (select 1 from cib_invoices o where o.project_id = pid and o.seq <> seq_no and o.status <> 'Cancelled' and o.kind <> 'Migrated' and o.period_from <= upto and o.period_to >= pfrom) then
    exc := exc || jsonb_build_object('k', 'dup', 'sev', 'block', 'msg', 'Duplicate claim: the period overlaps another invoice'); end if;
  if man > 0 then exc := exc || jsonb_build_object('k', 'manual', 'sev', 'warn', 'msg', man || ' item(s) are billed on a typed %, not P6 progress'); end if;
  return jsonb_build_object('su', su, 'dd', dd, 'lines', lines, 'exc', exc, 'tot', jsonb_build_object('cv', cv, 'gross_prev', gprev, 'gross_this', gthis, 'gross_cum', round(gprev + gthis, 2),
    'ret_this', retthis, 'ret_cum', round(retheld, 2), 'rel_this', relthis, 'rel_cum', round(coalesce((pt ->> 'rel_cum')::numeric, 0) + relthis, 2),
    'rel_tcc', coalesce((pt ->> 'rel_tcc')::boolean, false) or reltcc, 'rel_fac', coalesce((pt ->> 'rel_fac')::boolean, false) or relfac,
    'adv_amt', round(advamt, 2), 'adv_this', advthis, 'adv_cum', round(advprev + advthis, 2), 'net', net, 'vat', vat, 'total', round(net + vat, 2), 'balance', round(cv - gprev - gthis, 2), 'vat_pct', coalesce((h ->> 'vat')::numeric, 0)));
end $$;
create or replace function cib_features() returns jsonb language sql stable as $$ select jsonb_build_object('version', 51, 'llm_review', false) $$;
create or replace function cib_act(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); op text := p ->> 'op'; pid text := p ->> 'pid'; note text := btrim(coalesce(p ->> 'note', '')); sc record; iv record; ap record; x jsonb; k text; e text;
  rv int; nid text; n int := 0; tot numeric; c jsonb; seqn int; pfrom date; upto date; last record; ref text; d date; b jsonb; aft jsonb; reviewer uuid; amt numeric; ch boolean := false; g numeric; pt jsonb; h jsonb;
begin
  if me is null or role_of(me) is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if pid is null or not exists (select 1 from projects where id = pid) or not user_sees(me, pid) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
  if not pt_cib_can(me, null, pid) then raise exception 'Billing figures are not open to you' using errcode = '42501'; end if;
  k := case when op in ('sch_save','sch_head','sch_rules','sch_item','sch_discard','inv_migrate') then 'cib.setup' when op = 'sch_approve' then 'cib.approve'
    when op in ('map_save','map_review') then 'cib.map' when op in ('inv_save','inv_submit') then 'cib.prepare' when op = 'inv_review' then 'cib.review' when op = 'inv_approve' then 'cib.approve'
    when op in ('inv_certify','inv_pay') then 'cib.certify' else null end;
  if k is not null and not pt_cib_can(me, k, pid) then raise exception 'You do not have the right % for this project', k using errcode = '42501'; end if;

  if op = 'sch_save' then
    if exists (select 1 from cib_schedules where project_id = pid and status = 'Draft') then raise exception 'A draft revision is already waiting for approval: approve or replace it first'; end if;
    if jsonb_typeof(p -> 'items') <> 'array' or jsonb_array_length(p -> 'items') = 0 then raise exception 'The price schedule has no items'; end if;
    if jsonb_array_length(p -> 'items') > 6000 then raise exception 'The price schedule has more than 6,000 items'; end if;
    if exists (select 1 from jsonb_array_elements(p -> 'items') i where length(upper(regexp_replace(coalesce(i ->> 'no', ''), '\s', '', 'g'))) not between 1 and 60) then raise exception 'Every item needs a number of up to 60 characters'; end if;
    select upper(regexp_replace(i ->> 'no', '\s', '', 'g')) into e from jsonb_array_elements(p -> 'items') i group by 1 having count(*) > 1 limit 1;
    if e is not null then raise exception 'Item % appears twice', e; end if;
    if exists (select 1 from jsonb_array_elements(p -> 'items') i where coalesce(nullif(i ->> 'value', '')::numeric, 0) < 0) then raise exception 'An item value is negative'; end if;
    h := cib_head_clean(p -> 'head');
    select coalesce(max(rev), 0) + 1 into rv from cib_schedules where project_id = pid;
    x := coalesce(p -> 'rules', (select rules from cib_schedules where project_id = pid and status = 'Approved'), '{}'::jsonb);
    for c in select value from jsonb_each(x) loop e := pt_cib_rule_err('{"t":"pct","cap":100,"tcc":0,"fac":0}'::jsonb || c); if e is not null then raise exception '%', e; end if; end loop;
    nid := 'CS-' || pid || '-' || rv;
    insert into cib_schedules (id, project_id, rev, status, head, rules, file_name, file_hash, created_by, created_name) values (nid, pid, rv, 'Draft', h, x, left(p ->> 'file', 300), left(p ->> 'hash', 100), me, name_of(me));
    insert into cib_items (schedule_id, project_id, item_no, seq, data)
      select nid, pid, upper(regexp_replace(i ->> 'no', '\s', '', 'g')), o::int, (i - 'no') || jsonb_build_object('value', round(coalesce(nullif(i ->> 'value', '')::numeric, 0), 2),
        'parent', case when coalesce(i ->> 'parent', '') = '' then null else upper(regexp_replace(i ->> 'parent', '\s', '', 'g')) end,
        'limit', coalesce(nullif(i ->> 'limit', '')::numeric, 100), 'st', coalesce(nullif(i ->> 'st', ''), 'Active'), 'comp', coalesce(nullif(i ->> 'comp', ''), 'OTH'), 'leaf', coalesce((i ->> 'leaf')::boolean, true))
      from jsonb_array_elements(p -> 'items') with ordinality t(i, o);
    perform pt_cib_log(pid, 'Schedule-C uploaded', 'Revision ' || rv, null, jsonb_build_object('file', p ->> 'file', 'items', jsonb_array_length(p -> 'items'), 'value', h -> 'value'), note);
    return jsonb_build_object('id', nid, 'rev', rv, 'st', 'Draft');
  end if;
  if op in ('sch_head','sch_rules','sch_item','sch_approve','sch_discard') then
    select * into sc from cib_schedules where id = p ->> 'sch' and project_id = pid for update;
    if sc.id is null then raise exception 'Unknown revision'; end if;
    if op <> 'sch_approve' and sc.status <> 'Draft' then raise exception 'Only a draft revision changes; upload a new revision to change an approved one'; end if;
    if op = 'sch_head' then h := cib_head_clean(p -> 'head'); update cib_schedules set head = h where id = sc.id; perform pt_cib_log(pid, 'Schedule-C header changed', 'Revision ' || sc.rev, sc.head, h, note);
    elsif op = 'sch_rules' then
      for k, c in select key, value from jsonb_each(coalesce(p -> 'rules', '{}'::jsonb)) loop
        if k not in ('GEN','ENG','MAT','CON','INS','TC','CLO','OTH') then raise exception 'Unknown component %', k; end if;
        e := pt_cib_rule_err('{"t":"pct","cap":100,"tcc":0,"fac":0}'::jsonb || c); if e is not null then raise exception '%: %', k, e; end if; end loop;
      update cib_schedules set rules = p -> 'rules' where id = sc.id; perform pt_cib_log(pid, 'Invoicing rules changed', 'Revision ' || sc.rev, sc.rules, p -> 'rules', note);
    elsif op = 'sch_item' then
      select data into b from cib_items where schedule_id = sc.id and item_no = upper(regexp_replace(p ->> 'no', '\s', '', 'g')); if b is null then raise exception 'Unknown item'; end if;
      if jsonb_typeof(p -> 'rule') = 'object' then e := pt_cib_rule_err(pt_cib_rule(sc.rules, coalesce(nullif(p ->> 'comp', ''), b ->> 'comp'), p -> 'rule')); if e is not null then raise exception '%', e; end if; end if;
      if coalesce(nullif(p ->> 'limit', '')::numeric, 100) <= 0 or coalesce(nullif(p ->> 'limit', '')::numeric, 100) > 100 then raise exception 'The invoice limit is more than 0%% and at most 100%%'; end if;
      if coalesce(p ->> 'comp', '') <> '' and p ->> 'comp' not in ('GEN','ENG','MAT','CON','INS','TC','CLO','OTH') then raise exception 'Unknown component'; end if;
      aft := b || jsonb_build_object('rule', case when jsonb_typeof(p -> 'rule') = 'object' then p -> 'rule' else 'null'::jsonb end, 'limit', coalesce(nullif(p ->> 'limit', '')::numeric, 100), 'comp', coalesce(nullif(p ->> 'comp', ''), b ->> 'comp'));
      update cib_items set data = aft where schedule_id = sc.id and item_no = upper(regexp_replace(p ->> 'no', '\s', '', 'g'));
      perform pt_cib_log(pid, 'Item rule changed', p ->> 'no', jsonb_build_object('rule', b -> 'rule', 'limit', b -> 'limit', 'comp', b -> 'comp'), jsonb_build_object('rule', aft -> 'rule', 'limit', aft -> 'limit', 'comp', aft -> 'comp'), note);
    elsif op = 'sch_approve' then
      if sc.status <> 'Draft' then raise exception 'Only a draft revision is approved'; end if;
      if sc.created_by = me and role_of(me) <> 'sa' then raise exception 'Nobody approves a revision they uploaded'; end if;
      select coalesce(sum((data ->> 'value')::numeric), 0) into tot from cib_items where schedule_id = sc.id and (data ->> 'leaf')::boolean and data ->> 'st' = 'Active';
      if abs(tot - (sc.head ->> 'value')::numeric) > greatest(1, (sc.head ->> 'value')::numeric * 0.005) and note = '' then raise exception 'The items do not add up to the approved value: give the reason to approve it'; end if;
      for c in select value from jsonb_each(sc.rules) loop e := pt_cib_rule_err('{"t":"pct","cap":100,"tcc":0,"fac":0}'::jsonb || c); if e is not null then raise exception '%', e; end if; end loop;
      update cib_schedules set status = 'Superseded' where project_id = pid and status = 'Approved';
      update cib_schedules set status = 'Approved', approved_by = me, approved_name = name_of(me), approved_at = now() where id = sc.id;
      perform pt_cib_log(pid, 'Schedule-C approved', 'Revision ' || sc.rev, null, jsonb_build_object('value', sc.head -> 'value'), note);
    else delete from cib_schedules where id = sc.id; perform pt_cib_log(pid, 'Draft revision discarded', 'Revision ' || sc.rev, null, null, note); end if;
    return jsonb_build_object('ok', true, 'id', sc.id);
  end if;

  if op = 'map_save' then
    select * into sc from cib_schedules where project_id = pid and status <> 'Superseded' order by rev desc limit 1;
    b := '{}'::jsonb; aft := '{}'::jsonb;
    for x in select value from jsonb_array_elements(coalesce(p -> 'rows', '[]'::jsonb)) loop
      e := btrim(coalesce(x ->> 'act', '')); if e = '' or length(e) > 60 then raise exception 'Every activity needs an ID'; end if;
      k := nullif(upper(regexp_replace(coalesce(x ->> 'item', ''), '\s', '', 'g')), '');
      if k is not null and x ->> 'src' = 'manual' and not exists (select 1 from cib_items where schedule_id = sc.id and item_no = k) then raise exception 'Item % is not in the price schedule', k; end if;
      if exists (select 1 from cib_maps where project_id = pid and act_id = e and item_no is not distinct from k and src = case when x ->> 'src' = 'manual' then 'manual' else 'p6' end) then continue; end if;
      b := b || jsonb_build_object(e, (select item_no from cib_maps where project_id = pid and act_id = e)); aft := aft || jsonb_build_object(e, k); n := n + 1;
      if k is null then delete from cib_maps where project_id = pid and act_id = e;
      else insert into cib_maps (project_id, act_id, item_no, act_name, src, by_user, by_name) values (pid, e, k, left(x ->> 'name', 300), case when x ->> 'src' = 'manual' then 'manual' else 'p6' end, me, name_of(me))
        on conflict (project_id, act_id) do update set item_no = excluded.item_no, act_name = excluded.act_name, src = excluded.src, by_user = me, by_name = name_of(me), at_time = now(); end if;
    end loop;
    if coalesce((p ->> 'replace_p6')::boolean, false) then
      for e in select act_id from cib_maps where project_id = pid and src = 'p6' and act_id not in (select btrim(z ->> 'act') from jsonb_array_elements(coalesce(p -> 'rows', '[]'::jsonb)) z) loop
        b := b || jsonb_build_object(e, (select item_no from cib_maps where project_id = pid and act_id = e)); aft := aft || jsonb_build_object(e, null); n := n + 1;
        delete from cib_maps where project_id = pid and act_id = e; end loop; end if;
    if n > 0 then perform pt_cib_log(pid, case when coalesce((p ->> 'replace_p6')::boolean, false) then 'Mapping read from P6' else 'Mapping changed' end, p ->> 'file', b, aft, note); end if;
    return jsonb_build_object('changed', n);
  end if;
  if op = 'map_review' then
    k := upper(regexp_replace(coalesce(p ->> 'item', ''), '\s', '', 'g'));
    if not exists (select 1 from cib_items i join cib_schedules s on s.id = i.schedule_id where s.project_id = pid and s.status <> 'Superseded' and i.item_no = k) then raise exception 'Unknown item'; end if;
    select to_jsonb(r) into b from cib_map_reviews r where project_id = pid and item_no = k;
    if coalesce(p ->> 'd', '') = '' then delete from cib_map_reviews where project_id = pid and item_no = k; perform pt_cib_log(pid, 'Mapping review removed', k, b, null, null); return jsonb_build_object('ok', true); end if;
    if p ->> 'd' not in ('manual','zero') then raise exception 'Unknown review'; end if;
    if length(note) < 5 then raise exception 'Give the reason (at least 5 characters)'; end if;
    if p ->> 'd' = 'manual' and (nullif(p ->> 'pct', '') is null or (p ->> 'pct')::numeric not between 0 and 100) then raise exception 'The progress is between 0%% and 100%%'; end if;
    insert into cib_map_reviews (project_id, item_no, decision, pct, note, by_user, by_name) values (pid, k, p ->> 'd', case when p ->> 'd' = 'manual' then round((p ->> 'pct')::numeric, 2) else 0 end, left(note, 500), me, name_of(me))
      on conflict (project_id, item_no) do update set decision = excluded.decision, pct = excluded.pct, note = excluded.note, by_user = me, by_name = name_of(me), at_time = now();
    perform pt_cib_log(pid, 'Mapping reviewed', k, b, jsonb_build_object('d', p ->> 'd', 'pct', p -> 'pct', 'note', note), null);
    return jsonb_build_object('ok', true);
  end if;

  if op = 'inv_save' then
    select * into ap from cib_schedules where project_id = pid and status = 'Approved'; if ap.id is null then raise exception 'Approve a Schedule-C revision first'; end if;
    if p ->> 'id' is not null then select * into iv from cib_invoices where id = p ->> 'id' and project_id = pid for update; if iv.id is null then raise exception 'Unknown invoice'; end if;
      if iv.status <> 'Draft' then raise exception 'Only a draft invoice changes'; end if; seqn := iv.seq;
    else if exists (select 1 from cib_invoices where project_id = pid and status = 'Draft') then raise exception 'A draft invoice is already open: finish or cancel it first'; end if;
      select coalesce(max(seq), 0) + 1 into seqn from cib_invoices where project_id = pid and status <> 'Cancelled'; end if;
    if coalesce(p ->> 'to', '') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'The period end is not a valid date'; end if;
    upto := (p ->> 'to')::date; if upto > current_date then raise exception 'The period end is in the future'; end if;
    select * into last from cib_invoices where project_id = pid and status <> 'Cancelled' and seq < seqn order by seq desc limit 1;
    pfrom := coalesce(nullif(p ->> 'from', '')::date, last.period_to + 1, (select start_date from projects where id = pid), upto);
    if pfrom > upto then raise exception 'The period starts after it ends'; end if;
    ref := coalesce(nullif(left(btrim(coalesce(p ->> 'ref', '')), 60), ''), pid || '-INV-' || lpad(seqn::text, 2, '0'));
    c := pt_cib_compute(pid, ap.id, seqn, pfrom, upto);
    x := jsonb_build_object('ref', ref, 'rev', ap.rev, 'su', c -> 'su', 'dd', c -> 'dd', 'lines', c -> 'lines', 'tot', c -> 'tot', 'exc', c -> 'exc');
    if p ->> 'id' is null then
      nid := 'CI-' || pid || '-' || seqn || '-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS');
      insert into cib_invoices (id, project_id, seq, status, kind, schedule_id, period_from, period_to, data, prepared_by, prepared_name, hist)
        values (nid, pid, seqn, 'Draft', 'Progress', ap.id, pfrom, upto, x || '{"docs":{}}'::jsonb, me, name_of(me), jsonb_build_array(jsonb_build_object('st', 'Draft', 'by', name_of(me), 'at', now(), 'note', 'Prepared from P6 progress')));
      perform pt_cib_log(pid, 'Invoice prepared', '#' || seqn || ' ' || ref, null, jsonb_build_object('gross_this', c #> '{tot,gross_this}', 'to', upto), null);
    else
      nid := iv.id;
      update cib_invoices set schedule_id = ap.id, period_from = pfrom, period_to = upto, updated_at = now(),
        data = (iv.data - 'ai') || x || case when iv.data ? 'ai' and jsonb_typeof(iv.data -> 'ai') = 'object' then jsonb_build_object('ai', (iv.data -> 'ai') || '{"stale":true}'::jsonb) else '{}'::jsonb end where id = iv.id;
      perform pt_cib_log(pid, 'Invoice recalculated', '#' || seqn || ' ' || ref, jsonb_build_object('gross_this', iv.data #> '{tot,gross_this}', 'to', iv.period_to), jsonb_build_object('gross_this', c #> '{tot,gross_this}', 'to', upto), null);
    end if;
    return jsonb_build_object('id', nid, 'seq', seqn, 'tot', c -> 'tot', 'exc', c -> 'exc');
  end if;
  if op = 'inv_migrate' then
    select * into ap from cib_schedules where project_id = pid and status = 'Approved'; if ap.id is null then raise exception 'Approve a Schedule-C revision first'; end if;
    if exists (select 1 from cib_invoices where project_id = pid and kind <> 'Migrated' and status <> 'Cancelled') then raise exception 'Invoices are already prepared here: the history is loaded before the first invoice'; end if;
    seqn := nullif(p ->> 'seq', '')::int; if seqn is null or seqn not between 1 and 999 then raise exception 'The invoice number is a whole number from 1 to 999'; end if;
    if exists (select 1 from cib_invoices where project_id = pid and seq >= seqn and status <> 'Cancelled') then raise exception 'Invoice #% or a later one is already recorded', seqn; end if;
    if coalesce(p ->> 'to', '') !~ '^\d{4}-\d{2}-\d{2}$' or (p ->> 'to')::date > current_date then raise exception 'The certified-to date is not valid'; end if;
    c := '[]'::jsonb; tot := 0;
    for x in select value from jsonb_array_elements(coalesce(p -> 'lines', '[]'::jsonb)) loop
      k := upper(regexp_replace(coalesce(x ->> 'no', ''), '\s', '', 'g')); select data into b from cib_items where schedule_id = ap.id and item_no = k and (data ->> 'leaf')::boolean and data ->> 'st' = 'Active';
      if b is null then raise exception 'Item % is not a billable item of the approved revision', k; end if;
      g := round(coalesce(nullif(x ->> 'cum', '')::numeric, 0), 2); if g < 0 then raise exception 'Item %: negative amount', k; end if;
      if g > (b ->> 'value')::numeric + 0.5 then raise exception 'Item %: certified to date is more than its value', k; end if;
      c := c || jsonb_build_object('no', k, 'desc', b ->> 'desc', 'comp', b ->> 'comp', 'unit', coalesce(b ->> 'unit', ''), 'qty', coalesce((b ->> 'qty')::numeric, 0), 'rate', coalesce((b ->> 'rate')::numeric, 0), 'value', (b ->> 'value')::numeric,
        'rule', pt_cib_rule(ap.rules, b ->> 'comp', case when jsonb_typeof(b -> 'rule') = 'object' then b -> 'rule' else null end) ->> 't', 'prog', null, 'src', 'history', 'acts', 0, 'cum_pay', g, 'prev_pay', 0, 'this_pay', g, 'cert_cum', g);
      tot := tot + g; end loop;
    if jsonb_array_length(c) = 0 then raise exception 'No certified amounts to load'; end if;
    if tot > (ap.head ->> 'value')::numeric + 0.5 then raise exception 'Certified to date is more than the contract value'; end if;
    if least(coalesce(nullif(p ->> 'ret_cum', '')::numeric, 0), coalesce(nullif(p ->> 'adv_cum', '')::numeric, 0), coalesce(nullif(p ->> 'rel_cum', '')::numeric, 0)) < 0 then raise exception 'Amounts are not negative'; end if;
    if coalesce(nullif(p ->> 'adv_cum', '')::numeric, 0) > (ap.head ->> 'value')::numeric * coalesce((ap.head ->> 'adv_pct')::numeric, 0) / 100 + 0.5 then raise exception 'The advance recovered is more than the advance'; end if;
    nid := 'CI-' || pid || '-' || seqn || '-H';
    insert into cib_invoices (id, project_id, seq, status, kind, schedule_id, period_from, period_to, data, prepared_by, prepared_name, hist)
      values (nid, pid, seqn, 'Certified', 'Migrated', ap.id, nullif(p ->> 'from', '')::date, (p ->> 'to')::date,
        jsonb_build_object('ref', coalesce(nullif(left(p ->> 'ref', 60), ''), 'Invoice #' || lpad(seqn::text, 2, '0')), 'rev', ap.rev, 'lines', c, 'exc', '[]'::jsonb, 'docs', '{}'::jsonb, 'file', left(p ->> 'file', 300),
          'tot', jsonb_build_object('cv', (ap.head ->> 'value')::numeric, 'gross_prev', 0, 'gross_this', round(tot, 2), 'gross_cum', round(tot, 2), 'ret_this', round(coalesce(nullif(p ->> 'ret_cum', '')::numeric, 0), 2),
            'ret_cum', round(coalesce(nullif(p ->> 'ret_cum', '')::numeric, 0), 2), 'rel_this', 0, 'rel_cum', round(coalesce(nullif(p ->> 'rel_cum', '')::numeric, 0), 2), 'rel_tcc', coalesce((p ->> 'rel_tcc')::boolean, false),
            'rel_fac', coalesce((p ->> 'rel_fac')::boolean, false), 'adv_amt', round((ap.head ->> 'value')::numeric * coalesce((ap.head ->> 'adv_pct')::numeric, 0) / 100, 2), 'adv_this', round(coalesce(nullif(p ->> 'adv_cum', '')::numeric, 0), 2),
            'adv_cum', round(coalesce(nullif(p ->> 'adv_cum', '')::numeric, 0), 2), 'net', 0, 'vat', 0, 'total', 0, 'balance', round((ap.head ->> 'value')::numeric - tot, 2), 'vat_pct', coalesce((ap.head ->> 'vat')::numeric, 0)),
          'cert', jsonb_build_object('amt', round(tot, 2), 'date', p ->> 'to', 'ref', left(p ->> 'ref', 60), 'by', name_of(me), 'changed', false)),
        me, name_of(me), jsonb_build_array(jsonb_build_object('st', 'Certified', 'by', name_of(me), 'at', now(), 'note', 'Loaded from ' || coalesce(left(p ->> 'file', 200), 'the latest client invoice'))));
    perform pt_cib_log(pid, 'Invoice history loaded', '#' || seqn, null, jsonb_build_object('file', p ->> 'file', 'items', jsonb_array_length(c), 'certified', round(tot, 2)), null);
    return jsonb_build_object('id', nid, 'seq', seqn);
  end if;

  select * into iv from cib_invoices where id = p ->> 'id' and project_id = pid for update;
  if iv.id is null then raise exception 'Unknown invoice'; end if;
  select (hh ->> 'by_id')::uuid into reviewer from jsonb_array_elements(iv.hist) hh where hh ->> 'st' = 'Reviewed' order by (hh ->> 'at') desc limit 1;
  if op = 'inv_ai' then
    if not (pt_cib_can(me, 'cib.prepare', pid) or pt_cib_can(me, 'cib.review', pid) or pt_cib_can(me, 'cib.approve', pid)) then raise exception 'Only those who prepare, review or approve client invoices run the review' using errcode = '42501'; end if;
    update cib_invoices set data = data || jsonb_build_object('ai', jsonb_build_object('at', now(), 'by', name_of(me), 'score', least(greatest(coalesce((p ->> 'score')::int, 0), 0), 100),
      'find', coalesce((select jsonb_agg(f) from (select f from jsonb_array_elements(coalesce(p -> 'find', '[]'::jsonb)) f limit 80) z), '[]'::jsonb))) where id = iv.id;
    perform pt_cib_log(pid, 'Invoice reviewed (rules)', '#' || iv.seq, null, jsonb_build_object('score', p -> 'score'), null);
    return jsonb_build_object('ok', true);
  end if;
  if op = 'inv_docs' then
    if not (pt_cib_can(me, 'cib.prepare', pid) or pt_cib_can(me, 'cib.approve', pid)) then raise exception 'Only those who prepare or approve client invoices keep its documents' using errcode = '42501'; end if;
    if iv.status in ('Certified','Paid','Cancelled') then raise exception 'This invoice is closed'; end if;
    if p ->> 'k' not in ('appr','sum','mat','prog','spare','train','cont','ins','cert') then raise exception 'Unknown document'; end if;
    if coalesce(p ->> 'v', '') not in ('yes','na','') then raise exception 'Attached, not applicable or missing'; end if;
    update cib_invoices set data = jsonb_set(data, '{docs}', coalesce(data -> 'docs', '{}'::jsonb) || jsonb_build_object(p ->> 'k', p ->> 'v')) where id = iv.id;
    perform pt_cib_log(pid, 'Invoice document', '#' || iv.seq || ' ' || (p ->> 'k'), iv.data #> array['docs', p ->> 'k'], to_jsonb(p ->> 'v'), null);
    return jsonb_build_object('ok', true);
  end if;
  if op = 'inv_submit' then
    if iv.status <> 'Draft' then raise exception 'Only a draft is submitted'; end if;
    c := pt_cib_compute(pid, iv.schedule_id, iv.seq, iv.period_from, iv.period_to);
    if abs((c #>> '{tot,gross_this}')::numeric - (iv.data #>> '{tot,gross_this}')::numeric) > 0.5 then raise exception 'Progress, mapping or rules changed since this draft was calculated: recalculate it first'; end if;
    select string_agg(z ->> 'msg', ' · ') into e from jsonb_array_elements(c -> 'exc') z where z ->> 'sev' = 'block';
    if e is not null then raise exception 'Not submitted: %', e; end if;
    if jsonb_typeof(iv.data -> 'ai') is distinct from 'object' or coalesce((iv.data #>> '{ai,stale}')::boolean, false) or (iv.data #>> '{ai,at}')::timestamptz < iv.updated_at then raise exception 'Run "Review invoice" on the current figures first'; end if;
  elsif op = 'inv_review' then
    if iv.status <> 'Submitted' then raise exception 'Only a submitted invoice is reviewed'; end if;
    if iv.prepared_by = me and role_of(me) <> 'sa' then raise exception 'Nobody reviews an invoice they prepared'; end if;
  elsif op = 'inv_approve' then
    if iv.status <> 'Reviewed' then raise exception 'Only a reviewed invoice is approved'; end if;
    if (iv.prepared_by = me or reviewer = me) and role_of(me) <> 'sa' then raise exception 'Nobody approves an invoice they prepared or reviewed'; end if;
    if exists (select 1 from unnest(array['appr','sum','mat','prog','spare','train','cont','ins','cert']) dk where coalesce(iv.data #>> array['docs', dk], '') = '') then raise exception 'Mark every supporting document attached or not applicable first'; end if;
  elsif op = 'inv_return' then
    if not (pt_cib_can(me, 'cib.review', pid) or pt_cib_can(me, 'cib.approve', pid)) then raise exception 'Only a reviewer or approver returns an invoice' using errcode = '42501'; end if;
    if iv.status not in ('Submitted','Reviewed','Approved') then raise exception 'Only an invoice under review or approved is returned'; end if;
    if length(note) < 5 then raise exception 'Say why it is returned'; end if;
  elsif op = 'inv_issue' then
    if not (pt_cib_can(me, 'cib.prepare', pid) or pt_cib_can(me, 'cib.approve', pid)) then raise exception 'Only those who prepare or approve client invoices issue them' using errcode = '42501'; end if;
    if iv.status <> 'Approved' then raise exception 'Only an approved invoice is issued'; end if;
    if coalesce(p ->> 'date', '') !~ '^\d{4}-\d{2}-\d{2}$' or (p ->> 'date')::date > current_date then raise exception 'The issue date is not valid'; end if;
    if (p ->> 'date')::date < iv.period_to then raise exception 'An invoice is issued after its period ends'; end if;
  elsif op = 'inv_certify' then
    if iv.status <> 'Issued' then raise exception 'Only an issued invoice is certified'; end if;
    if coalesce(p ->> 'date', '') !~ '^\d{4}-\d{2}-\d{2}$' or (p ->> 'date')::date > current_date then raise exception 'The certificate date is not valid'; end if;
    if (p ->> 'date')::date < (iv.data #>> '{issued,date}')::date then raise exception 'Certified before it was issued'; end if;
  elsif op = 'inv_pay' then
    if iv.status <> 'Certified' then raise exception 'Only a certified invoice is marked paid'; end if;
    if coalesce(p ->> 'date', '') !~ '^\d{4}-\d{2}-\d{2}$' or (p ->> 'date')::date > current_date then raise exception 'The payment date is not valid'; end if;
    if (p ->> 'date')::date < (iv.data #>> '{cert,date}')::date then raise exception 'Paid before it was certified'; end if;
    amt := nullif(p ->> 'amt', '')::numeric; if amt is null or amt <= 0 then raise exception 'The amount paid is more than 0'; end if;
    if amt > (iv.data #>> '{tot,total}')::numeric + 0.5 then raise exception 'Paid more than the invoice total with VAT'; end if;
  elsif op = 'inv_cancel' then
    if iv.status = 'Draft' then if not pt_cib_can(me, 'cib.prepare', pid) then raise exception 'Only those who prepare client invoices cancel a draft' using errcode = '42501'; end if;
    else if not pt_cib_can(me, 'cib.approve', pid) then raise exception 'You do not have the right cib.approve for this project' using errcode = '42501'; end if;
      if iv.status not in ('Submitted','Reviewed','Approved') then raise exception 'An issued invoice is not cancelled: the client certifies it or rejects it with a credit note'; end if; end if;
    if length(note) < 5 then raise exception 'Say why it is cancelled'; end if;
  else raise exception 'Unknown action'; end if;

  -- the state change
  b := iv.data;
  if op = 'inv_certify' then
    tot := 0;
    select jsonb_agg(l || jsonb_build_object('cert_this', cc, 'cert_cum', round((l ->> 'prev_pay')::numeric + cc, 2))), sum(cc), bool_or(abs(cc - (l ->> 'this_pay')::numeric) > 0.005)
      into c, tot, ch from (select l, round(case when p -> 'lines' ? (l ->> 'no') and nullif(p #>> array['lines', l ->> 'no'], '') is not null then (p #>> array['lines', l ->> 'no'])::numeric else (l ->> 'this_pay')::numeric end, 2) cc
        from jsonb_array_elements(iv.data -> 'lines') l) z;
    if exists (select 1 from jsonb_array_elements(c) l where (l ->> 'cert_this')::numeric < 0 or (l ->> 'cert_this')::numeric > (l ->> 'this_pay')::numeric + 0.5) then raise exception 'A certified amount is negative or more than claimed'; end if;
    g := round(coalesce(tot, 0), 2); x := iv.data -> 'tot';
    if ch then
      select data -> 'tot' into pt from cib_invoices where project_id = pid and status in ('Certified','Paid') and seq < iv.seq order by seq desc limit 1; pt := coalesce(pt, '{}'::jsonb);
      select head into h from cib_schedules where id = iv.schedule_id;
      x := x || jsonb_build_object('gross_this', g, 'gross_cum', round((x ->> 'gross_prev')::numeric + g, 2),
        'ret_this', round(least(g * coalesce((h ->> 'ret_pct')::numeric, 0) / 100, greatest(0, (h ->> 'value')::numeric * coalesce(nullif(h ->> 'ret_cap', '')::numeric, 100) / 100 - coalesce((pt ->> 'ret_cum')::numeric, 0))), 2),
        'adv_this', round(least(g * coalesce((h ->> 'adv_rec')::numeric, 0) / 100, greatest(0, (x ->> 'adv_amt')::numeric - coalesce((pt ->> 'adv_cum')::numeric, 0))), 2));
      x := x || jsonb_build_object('ret_cum', round(coalesce((pt ->> 'ret_cum')::numeric, 0) + (x ->> 'ret_this')::numeric, 2), 'adv_cum', round(coalesce((pt ->> 'adv_cum')::numeric, 0) + (x ->> 'adv_this')::numeric, 2),
        'net', round(g - (x ->> 'ret_this')::numeric + (x ->> 'rel_this')::numeric - (x ->> 'adv_this')::numeric, 2), 'balance', round((x ->> 'cv')::numeric - (x ->> 'gross_prev')::numeric - g, 2));
      x := x || jsonb_build_object('vat', round((x ->> 'net')::numeric * (x ->> 'vat_pct')::numeric / 100, 2));
      x := x || jsonb_build_object('total', round((x ->> 'net')::numeric + (x ->> 'vat')::numeric, 2));
    end if;
    update cib_invoices set data = data || jsonb_build_object('lines', c, 'tot', x, 'cert', jsonb_build_object('amt', g, 'date', p ->> 'date', 'ref', left(p ->> 'ref', 60), 'by', name_of(me), 'at', now(), 'changed', coalesce(ch, false))) where id = iv.id;
  elsif op = 'inv_issue' then
    update cib_invoices set data = data || jsonb_build_object('issued', jsonb_build_object('date', p ->> 'date', 'ref', coalesce(nullif(left(p ->> 'ref', 60), ''), iv.data ->> 'ref'), 'by', name_of(me)),
      'ref', coalesce(nullif(left(p ->> 'ref', 60), ''), iv.data ->> 'ref')) where id = iv.id;
  elsif op = 'inv_pay' then
    update cib_invoices set data = data || jsonb_build_object('paid', jsonb_build_object('amt', round(amt, 2), 'date', p ->> 'date', 'ref', left(p ->> 'ref', 60), 'by', name_of(me))) where id = iv.id;
  elsif op = 'inv_return' then
    update cib_invoices set data = case when jsonb_typeof(data -> 'ai') = 'object' then jsonb_set(data, '{ai,stale}', 'true') else data end where id = iv.id;
  end if;
  k := case op when 'inv_submit' then 'Submitted' when 'inv_review' then 'Reviewed' when 'inv_approve' then 'Approved' when 'inv_return' then 'Draft' when 'inv_issue' then 'Issued'
    when 'inv_certify' then 'Certified' when 'inv_pay' then 'Paid' else 'Cancelled' end;
  update cib_invoices set status = k, updated_at = case when op = 'inv_return' then now() else updated_at end,
    hist = hist || jsonb_build_array(jsonb_build_object('st', k, 'by', name_of(me), 'by_id', me, 'at', now(), 'note', case when op = 'inv_return' then 'Returned: ' || note when op = 'inv_certify' and ch then 'Certified with changes' else nullif(note, '') end))
    where id = iv.id;
  perform pt_cib_log(pid, 'Invoice ' || lower(case when k = 'Draft' then 'returned' else k end), '#' || iv.seq || ' ' || (iv.data ->> 'ref'), jsonb_build_object('st', iv.status), jsonb_build_object('st', k), nullif(note, ''));
  return jsonb_build_object('ok', true, 'st', k);
end $$;
alter table cib_maps drop constraint if exists cib_maps_w_check; alter table cib_maps drop constraint if exists cib_maps_via_check;
alter table cib_maps drop column if exists w; alter table cib_maps drop column if exists via;
