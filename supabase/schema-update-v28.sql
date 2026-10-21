-- ProTrack schema update v28 (ProTrackAI v3.21): the cash-out forecast from the material POs and the cost report heads.
-- 1. co_mat_po: the value, currency, payment terms and milestones of each PO number of Material tracking
--    (material_items.po_number), as the app's coMatPoSaveLocal(). A milestone is tied to a Material tracking stage
--    (PR, PO, BD, GAFM, MFG, FAT, RFS, DEL, CIV), the P6 TCC or final acceptance milestone, or a fixed date, with its
--    contractual payment days. The page works the dates out from the latest updated schedule; at approval it sends each
--    milestone's date, which the server keeps as its baseline. A changed PO value needs its revision reference and reason;
--    a paid milestone keeps what was paid unless an approver changes it with a reason.
-- 2. co_heads: how each WBS head of the monthly cost report enters the forecast (material POs, subcontract POs, cost
--    report, excluded), when it differs from the default, and whether the ETC of the PO heads is included.
-- 3. cashout_act gains the kinds 'matpo', 'matpoapprove' and 'heads'; every other kind goes to the v27 function, kept as
--    cashout_act_v27. Same rights: the keepers (cashout.keep) change, the approvers (coordinator, Head, super admin) approve.
-- Needs schema-update-v27.sql (STAGE-23-SETUP) and schema-update-v17.sql (material tracking). Safe to run twice.
-- Undo: schema-rollback-v28.sql.

do $$ begin
  if to_regprocedure('public.cashout_act(jsonb)') is null or to_regclass('public.co_actuals') is null or to_regclass('public.material_items') is null then
    raise exception 'Run schema-update-v17.sql (STAGE-14-SETUP) and schema-update-v27.sql (STAGE-23-SETUP) first, then this update'; end if;
end $$;

create table if not exists co_mat_po (project_id text not null references projects(id) on delete cascade, po_key text not null, po_no text not null, state jsonb not null,
  updated_by uuid references profiles(id), updated_at timestamptz not null default now(), primary key (project_id, po_key));
create table if not exists co_heads (project_id text primary key references projects(id) on delete cascade, map jsonb not null default '{}'::jsonb, unordered boolean not null default true,
  updated_by uuid references profiles(id), updated_at timestamptz not null default now());
do $$
declare t text;
begin
  foreach t in array array['co_mat_po','co_heads'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists %I on %I', t || '_read', t);
    execute format('create policy %I on %I for select using (can_see(project_id) and pt_money_ok())', t || '_read', t);
    execute format('revoke all on %I from anon', t);
    execute format('revoke insert, update, delete, truncate on %I from authenticated', t);
    execute format('grant select on %I to authenticated', t);
  end loop;
end $$;

-- the v27 dispatcher keeps every v27 kind
do $$ begin
  if to_regprocedure('public.cashout_act_v27(jsonb)') is null then alter function cashout_act(jsonb) rename to cashout_act_v27; end if;
end $$;
revoke execute on function cashout_act_v27(jsonb) from public, anon, authenticated;

-- one material PO milestone, cleaned and checked (the app's coMatMsClean)
create or replace function pt_co_mat_ms(m jsonb, value numeric) returns jsonb language plpgsql stable as $$
declare nm text := left(btrim(coalesce(m ->> 'name', '')), 120); stage text := coalesce(nullif(m ->> 'stage', ''), 'DEL'); basis text := case when m ->> 'basis' = 'fixed' then 'fixed' else 'pct' end;
        pct numeric := pt_co_num(m ->> 'pct'); amt numeric := pt_co_num(m ->> 'amount'); ded numeric := pt_co_num(m ->> 'deduction'); gross numeric; st text := coalesce(nullif(m ->> 'status', ''), 'Planned'); days int;
begin
  if nm = '' then raise exception 'Every milestone needs a name'; end if;
  if stage not in ('PR','PO','BD','GAFM','MFG','FAT','RFS','DEL','CIV','TCC','FAC','DATE') then raise exception '%: choose its stage', nm; end if;
  if st not in ('Planned','Invoiced','Paid','On hold','Cancelled') then raise exception '%: unknown status', nm; end if;
  if basis = 'pct' and (pct is null or not (pct > 0 and pct <= 100)) then raise exception '%: the percentage of the PO value is between 0 and 100', nm; end if;
  if basis = 'fixed' and (amt is null or not (amt > 0)) then raise exception '%: the fixed amount must be more than 0', nm; end if;
  if stage = 'DATE' and pt_date(m ->> 'fixed_date') is null then raise exception '%: a fixed-date milestone needs its date', nm; end if;
  if coalesce(m ->> 'pay_days', '') !~ '^\d{0,3}$' or coalesce(nullif(m ->> 'pay_days', '')::int, 0) > 365 then raise exception '%: contractual payment days are a whole number from 0 to 365', nm; end if;
  days := coalesce(nullif(m ->> 'pay_days', '')::int, 0);
  gross := case when basis = 'fixed' then amt else round(value * pct / 100, 2) end;
  if ded is not null and (ded < 0 or ded >= gross) then raise exception '%: the retention or deduction must be positive and less than the amount', nm; end if;
  if st = 'Paid' then
    if pt_date(m ->> 'paid_date') is null then raise exception '%: a paid milestone needs its payment date', nm; end if;
    if pt_date(m ->> 'paid_date') > current_date then raise exception '%: the payment date cannot be in the future', nm; end if;
    if nullif(btrim(coalesce(m ->> 'evidence', '')), '') is null then raise exception '%: a paid milestone needs its evidence (Finance payment reference)', nm; end if;
  end if;
  return jsonb_build_object('id', coalesce(nullif(m ->> 'id', ''), 'MM' || replace(uuid_generate_v4()::text, '-', '')), 'name', nm, 'stage', stage, 'basis', basis,
    'pct', case when basis = 'pct' then pct end, 'amount', case when basis = 'fixed' then amt end, 'pay_days', days, 'fixed_date', case when stage = 'DATE' then m ->> 'fixed_date' end,
    'deduction', ded, 'status', st, 'paid_date', case when st = 'Paid' then m ->> 'paid_date' end,
    'paid_amount', case when st = 'Paid' then coalesce(pt_co_num(m ->> 'paid_amount'), gross - coalesce(ded, 0)) end,
    'evidence', nullif(left(btrim(coalesce(m ->> 'evidence', '')), 200), ''), 'notes', nullif(left(btrim(coalesce(m ->> 'notes', '')), 1000), ''),
    'approval', 'Draft', 'approved_by', null, 'approved_at', null, 'base_pay_date', null);   -- v3.26.1: approval comes from the stored milestone
end $$;

create or replace function cashout_act(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); kind text := p ->> 'kind'; a jsonb := coalesce(p -> 'args', '[]'::jsonb); pid text := a ->> 0; k text; no text; old jsonb; s jsonb; f jsonb; ms jsonb := '[]'::jsonb;
        m jsonb; om jsonb; val numeric; note text; revs jsonb; n int := 0; key text; v text;
begin
  if kind is null or kind not in ('matpo','matpoapprove','heads') then return cashout_act_v27(p); end if;
  if me is null or role_of(me) is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if kind = 'heads' then
    if not pt_co_keeper(me, pid) then raise exception 'Only the people who keep this project''s cash-out forecast change the head treatments' using errcode = '42501'; end if;
    for key, v in select * from jsonb_each_text(coalesce(a -> 1, '{}'::jsonb)) loop
      if key not in ('SM','DE','TEC','MTRL.ELC','MAN.ELC','INSTL.ELC','MTRL.MECH','MAN.MECH','INSTL.MECH','MTRL.CVL','MAN.CVL','INSTL.CVL','SAD','FNE','PC ITEMS','PROV. SUM','CONT','MGT.RES') then raise exception 'Unknown WBS head %', key; end if;
      if v not in ('mat','sub','nonpo','excl') then raise exception 'Unknown treatment %', v; end if;
    end loop;
    insert into co_heads (project_id, map, unordered, updated_by) values (pid, coalesce(a -> 1, '{}'::jsonb), coalesce((a ->> 2)::boolean, true), me)
    on conflict (project_id) do update set map = excluded.map, unordered = excluded.unordered, updated_by = excluded.updated_by, updated_at = now();
    perform pt_co_log(pid, 'Head treatments changed', nullif(a ->> 3, ''), jsonb_build_object('map', a -> 1, 'unordered', a -> 2));
    return jsonb_build_object('ok', true);
  end if;
  no := btrim(coalesce(a ->> 1, '')); key := upper(no);
  if not exists (select 1 from material_items where project_id = pid and upper(btrim(coalesce(po_number, ''))) = key) then raise exception 'This PO number is not in Material tracking for this project'; end if;
  select state into old from co_mat_po where project_id = pid and po_key = key;
  old := coalesce(old, jsonb_build_object('value', null, 'currency', 'SAR', 'status', 'Open', 'milestones', '[]'::jsonb, 'revisions', '[]'::jsonb));
  if kind = 'matpoapprove' then
    if not (pt_co_approver(me) and user_sees(me, pid)) then raise exception 'Only the costing coordinator, the Head of Planning and Cost Control or a super admin approves payment terms' using errcode = '42501'; end if;
    if (old ->> 'value') is null then raise exception 'Fix these first: no PO value'; end if;
    if (select coalesce(sum(case when m2 ->> 'basis' = 'fixed' then (m2 ->> 'amount')::numeric else round((old ->> 'value')::numeric * (m2 ->> 'pct')::numeric / 100, 2) end), 0)
          from jsonb_array_elements(old -> 'milestones') m2 where m2 ->> 'status' <> 'Cancelled') - (old ->> 'value')::numeric not between -0.01 and 0.01 and coalesce(old ->> 'status', 'Open') <> 'Cancelled' then raise exception 'Fix these first: the milestones must total 100%% of the PO value'; end if;
    for m in select * from jsonb_array_elements(old -> 'milestones') loop
      if coalesce(m ->> 'approval', 'Draft') <> 'Approved' then n := n + 1;
        if nullif(a -> 3 ->> (m ->> 'id'), '') is null then raise exception 'Fix these first: % has no date in the schedule', m ->> 'name'; end if;
        m := m || jsonb_build_object('approval', 'Approved', 'approved_by', name_of(me), 'approved_at', now(), 'base_pay_date', coalesce(m ->> 'base_pay_date', a -> 3 ->> (m ->> 'id'))); end if;
      ms := ms || jsonb_build_array(m); end loop;
    if n = 0 then raise exception 'Nothing is waiting for approval'; end if;
    s := old || jsonb_build_object('milestones', ms);
    perform pt_co_log(pid, 'Material PO terms approved', nullif(a ->> 2, ''), jsonb_build_object('po', no, 'milestones', n));
  else
    if not pt_co_keeper(me, pid) then raise exception 'Only the costing engineers of this project, the costing coordinator, the Head of Planning and Cost Control or a super admin change its payment terms' using errcode = '42501'; end if;
    f := a -> 2; note := btrim(coalesce(a ->> 3, '')); val := pt_co_num(f ->> 'value'); revs := coalesce(old -> 'revisions', '[]'::jsonb);
    if not (val > 0) then raise exception 'Enter the PO value (SAR)'; end if;
    if coalesce(f ->> 'status', 'Open') not in ('Open','Completed','Cancelled') then raise exception 'Unknown PO status'; end if;
    if f ->> 'status' = 'Cancelled' and coalesce(old ->> 'status', 'Open') <> 'Cancelled' and length(btrim(coalesce(f ->> 'cancel_reason', ''))) < 5 then raise exception 'Say why the PO is cancelled'; end if;
    if (old ->> 'value') is not null and (old ->> 'value')::numeric <> val then
      if nullif(btrim(coalesce(f ->> 'rev_ref', '')), '') is null or length(btrim(coalesce(f ->> 'rev_reason', ''))) < 5 then raise exception 'The PO value changed: give the revision reference and the reason'; end if;
      revs := revs || jsonb_build_array(jsonb_build_object('from', (old ->> 'value')::numeric, 'to', val, 'ref', btrim(f ->> 'rev_ref'), 'reason', btrim(f ->> 'rev_reason'), 'date', current_date, 'by', name_of(me), 'at', now()));
    end if;
    for m in select * from jsonb_array_elements(coalesce(f -> 'milestones', '[]'::jsonb)) loop
      m := pt_co_mat_ms(m, val);
      select y into om from jsonb_array_elements(old -> 'milestones') y where y ->> 'id' = m ->> 'id';
      if om is not null and om ->> 'base_pay_date' is not null then m := m || jsonb_build_object('base_pay_date', om ->> 'base_pay_date'); end if;
      if om is null or exists (select 1 from unnest(array['name','stage','basis','pct','amount','pay_days','fixed_date','deduction']) k2 where (m -> k2) is distinct from (om -> k2))
         or (m ->> 'basis' = 'pct' and (old ->> 'value') is not null and (old ->> 'value')::numeric <> val and coalesce(m ->> 'status', '') <> 'Paid') then
        m := m || jsonb_build_object('approval', 'Draft', 'approved_by', null, 'approved_at', null);
      else m := m || jsonb_build_object('approval', coalesce(om ->> 'approval', 'Draft'), 'approved_by', om -> 'approved_by', 'approved_at', om -> 'approved_at'); end if;
      ms := ms || jsonb_build_array(m); om := null;
    end loop;
    for om in select * from jsonb_array_elements(old -> 'milestones') loop
      if om ->> 'status' = 'Paid' then
        select y into m from jsonb_array_elements(ms) y where y ->> 'id' = om ->> 'id';
        if m is null then raise exception '% is paid and cannot be removed', om ->> 'name'; end if;
        if exists (select 1 from unnest(array['basis','pct','amount','deduction','paid_date','paid_amount','status']) k2 where (m -> k2) is distinct from (om -> k2)) then
          if not pt_co_approver(me) then raise exception '% is paid: what was paid cannot be changed. Ask the costing coordinator, the Head of Planning and Cost Control or a super admin', om ->> 'name'; end if;
          if length(note) < 5 then raise exception 'Say why the paid milestone % is changed', om ->> 'name'; end if; end if;
        m := null; end if;
    end loop;
    s := jsonb_build_object('value', val, 'orig_value', coalesce(old -> 'orig_value', old -> 'value', to_jsonb(val)), 'currency', 'SAR', 'status', coalesce(f ->> 'status', 'Open'),
      'terms', nullif(left(btrim(coalesce(f ->> 'terms', '')), 500), ''), 'cancel_reason', case when f ->> 'status' = 'Cancelled' then coalesce(nullif(btrim(f ->> 'cancel_reason'), ''), old ->> 'cancel_reason') end,
      'milestones', ms, 'revisions', revs, 'updated_by', name_of(me), 'updated_at', now());
    perform pt_co_log(pid, 'Material PO terms changed', nullif(note, ''), jsonb_build_object('po', no, 'value', val, 'milestones', jsonb_array_length(ms)));
  end if;
  insert into co_mat_po (project_id, po_key, po_no, state, updated_by) values (pid, key, no, s, me)
  on conflict (project_id, po_key) do update set state = excluded.state, po_no = excluded.po_no, updated_by = excluded.updated_by, updated_at = now();
  return s;
end $$;

create or replace function cashout_features() returns jsonb language sql immutable as $$ select '{"version":28,"cashout":true,"material_po":true,"cost_heads":true}'::jsonb $$;
revoke execute on function pt_co_mat_ms(jsonb, numeric), cashout_act(jsonb) from public, anon;
revoke execute on function pt_co_mat_ms(jsonb, numeric) from authenticated;
grant execute on function cashout_act(jsonb), cashout_features() to authenticated;
