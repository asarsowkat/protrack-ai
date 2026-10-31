-- ProTrack schema update v45 (ProTrackAI v3.41): the cost plan and the MER (Monthly Executive Report), in Cost Control.
-- 1. cost_plans: one row per project and year, kept by the project's costing engineer (the right report.cost.prepare, with
--    access to the project) or a super admin:
--    - plan_int: the internal plan, the planned cost of each month (SAR) on a budget, agreed with the project manager;
--    - plan_fin: the finance plan, the conservative POC target given to Finance with management's approval: the target POC at
--      year end (cumulative from the project's start), the planned POC % of each month and the approval reference;
--    - plan_fc: the forecast POC % of each month after the last released cost report;
--    - plan_base: the year start (POC, budget and contract value at December of last year), when December has no released
--      cost report;
--    - hist: every save and decision (who, when, what), appended by the functions only.
--    Read by those who see cost figures (pt_money_ok) on the projects they see (user_sees). Changed only through
--    cost_plan_save(p) and cost_plan_act(p), with the app's checks (cpCheck). Saving the internal or finance plan returns it to
--    Draft. cost_plan_act: 'agree' (the internal plan) by the project manager of the project or a super admin; 'approve' (the
--    finance plan) by the head of planning and cost control, an executive or a super admin.
-- 2. The screens 'cplan' (Cost Control -> Cost plan) and 'mer' (Cost Control -> MER – Monthly Executive Report) join
--    pt_screens(), so the super admin can show or hide them for a role in Settings -> Role access.
-- 3. Nothing else changes on the server. The MER is worked out in the browser from what the server already gives: the released
--    monthly cost reports (by WBS head; the new optional figure stock_value, "Actual stock value", is kept in figures as every
--    other header figure is; the app refuses a negative one and the MER reads a negative one as 0), the released monthly internal reports (the areas of concern are kept in narrative.concerns,
--    which release_save already stores whole since v14), the change order and claim log, the invoice register and payment
--    terms, the cash-out forecast and the cost plans.
-- 4. cost_plan_features() tells the app this update is in.
-- Needs schema-update-v16.sql (pt_screens, pt_money_ok, pt_right) and v7 (pt_is_head, pt_is_coord). Additive. Safe to run twice.
-- Undo: schema-rollback-v45.sql.

do $$
declare scr text[]; s text;
begin
  if to_regprocedure('public.pt_screens()') is null or to_regprocedure('public.pt_money_ok()') is null
     or to_regprocedure('public.pt_right(uuid,text,boolean)') is null or to_regprocedure('public.pt_is_head(uuid)') is null then
    raise exception 'Run the Roles and rights update (schema-update-v16.sql, STAGE-13-SETUP) first, then this update'; end if;
  scr := pt_screens();
  foreach s in array array['cplan','mer'] loop
    if not (s = any(scr)) then scr := scr || s; end if;
  end loop;
  execute format('create or replace function pt_screens() returns text[] language sql immutable as $f$ select %L::text[] $f$', scr::text);
end $$;

create table if not exists cost_plans (
  id bigserial primary key,
  project_id text not null references projects(id) on delete cascade,
  year int not null check (year between 2000 and 2100),
  plan_int jsonb, plan_fin jsonb, plan_fc jsonb, plan_base jsonb,
  hist jsonb not null default '[]'::jsonb check (jsonb_typeof(hist) = 'array'),
  updated_at timestamptz not null default now(),
  unique (project_id, year));
alter table cost_plans enable row level security;
drop policy if exists cp_read on cost_plans;
create policy cp_read on cost_plans for select using (pt_money_ok() and user_sees(auth.uid(), project_id));
revoke all on cost_plans from anon;
revoke insert, update, delete, truncate on cost_plans from authenticated;
grant select on cost_plans to authenticated;

-- twelve months, each a number from lo to hi or null
create or replace function cp_months(a jsonb, lo numeric, hi numeric, what text) returns jsonb language plpgsql immutable as $$
declare i int; v jsonb; res jsonb := '[]'::jsonb; n numeric;
begin
  if jsonb_typeof(a) is distinct from 'array' or jsonb_array_length(a) <> 12 then raise exception '%: give the twelve months', what; end if;
  for i in 0..11 loop
    v := a -> i;
    if v is null or jsonb_typeof(v) = 'null' then res := res || 'null'::jsonb;
    elsif jsonb_typeof(v) = 'number' then
      n := (v #>> '{}')::numeric;
      if n < lo or n > hi then raise exception '%, %: a number from % to %', what, (array['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'])[i+1], lo, hi; end if;
      res := res || to_jsonb(n);
    else raise exception '%, %: a number from % to %', what, (array['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'])[i+1], lo, hi; end if;
  end loop;
  return res;
end $$;
create or replace function cp_num(d jsonb, k text) returns numeric language plpgsql immutable as $$
begin
  if d -> k is null or jsonb_typeof(d -> k) = 'null' then return null; end if;
  if jsonb_typeof(d -> k) <> 'number' then raise exception 'The figure % must be a number', k; end if;
  return (d ->> k)::numeric;
end $$;

-- p: {project_id, year, part: 'int' | 'fin' | 'fc' | 'base', data: {...}, note}
create or replace function cost_plan_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); pid text := p ->> 'project_id'; y int; part text := p ->> 'part'; d jsonb := coalesce(p -> 'data', '{}'::jsonb);
  r cost_plans; v jsonb; now_t text := to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'); h jsonb := '[]'::jsonb; b numeric; t numeric; note text := nullif(btrim(coalesce(p ->> 'note', '')), '');
begin
  if me is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if pid is null or not exists (select 1 from projects where id = pid) then raise exception 'Unknown project'; end if;
  if coalesce(p ->> 'year', '') !~ '^\d{4}$' then raise exception 'Give the year'; end if;
  y := (p ->> 'year')::int;
  if not (user_sees(me, pid) and (role_of(me) = 'sa' or pt_right(me, 'report.cost.prepare', pt_is_coord(me)))) then
    raise exception 'Only the costing engineer of the project keeps its cost plan' using errcode = '42501'; end if;
  if part is null or part not in ('int','fin','fc','base') then raise exception 'Unknown part of the cost plan'; end if;
  if length(coalesce(note, '')) > 300 then raise exception 'A comment is 300 characters at most'; end if;
  if part = 'int' then
    b := cp_num(d, 'budget'); if b is null or b <= 0 then raise exception 'Give the budget the plan is made on (more than 0)'; end if;
    t := cp_num(d, 'cv'); if t is not null and t < 0 then raise exception 'The contract value cannot be negative'; end if;
    v := jsonb_build_object('budget', b, 'cv', t, 'months', cp_months(d -> 'months', 0, 1e12, 'Planned cost'), 'status', 'Draft');
  elsif part = 'fin' then
    t := cp_num(d, 'target'); if t is null or t < 0 or t > 100 then raise exception 'Give the target POC at year end, from 0 to 100 %%'; end if;
    if length(coalesce(d ->> 'ref', '')) > 120 then raise exception 'The approval reference is 120 characters at most'; end if;
    v := jsonb_build_object('target', t, 'ref', nullif(btrim(coalesce(d ->> 'ref', '')), ''), 'months', cp_months(d -> 'months', -100, 100, 'Monthly POC %'), 'status', 'Draft');
  elsif part = 'fc' then
    v := jsonb_build_object('months', cp_months(d -> 'months', -100, 100, 'Forecast POC %'));
  else
    t := cp_num(d, 'poc'); if t is not null and (t < 0 or t > 100) then raise exception 'The POC at the end of last year is from 0 to 100 %%'; end if;
    b := cp_num(d, 'budget'); if b is not null and b < 0 then raise exception 'The budget cannot be negative'; end if;
    if cp_num(d, 'cv') < 0 then raise exception 'The contract value cannot be negative'; end if;
    v := jsonb_build_object('poc', t, 'budget', b, 'cv', cp_num(d, 'cv'));
  end if;
  v := v || jsonb_build_object('saved_by', me, 'saved_by_name', name_of(me), 'saved_at', now_t);
  insert into cost_plans (project_id, year) values (pid, y) on conflict (project_id, year) do nothing;
  select * into r from cost_plans where project_id = pid and year = y for update;
  if part = 'int' and r.plan_int ->> 'status' = 'Agreed' then h := h || jsonb_build_object('at', now_t, 'by', name_of(me), 'part', part, 'action', 'Back to draft (changed after agreement)'); end if;
  if part = 'fin' and r.plan_fin ->> 'status' = 'Approved' then h := h || jsonb_build_object('at', now_t, 'by', name_of(me), 'part', part, 'action', 'Back to draft (changed after approval)'); end if;
  h := h || jsonb_build_object('at', now_t, 'by', name_of(me), 'part', part, 'action', 'Saved', 'note', note);
  update cost_plans set
    plan_int = case when part = 'int' then v else plan_int end, plan_fin = case when part = 'fin' then v else plan_fin end,
    plan_fc = case when part = 'fc' then v else plan_fc end, plan_base = case when part = 'base' then v else plan_base end,
    hist = hist || h, updated_at = now()
  where id = r.id;
  return jsonb_build_object('id', r.id);
end $$;

-- p: {project_id, year, action: 'agree' | 'approve', note}
create or replace function cost_plan_act(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); pid text := p ->> 'project_id'; a text := p ->> 'action'; r cost_plans; now_t text := to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
  note text := nullif(btrim(coalesce(p ->> 'note', '')), '');
begin
  if me is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if coalesce(p ->> 'year', '') !~ '^\d{4}$' then raise exception 'Give the year'; end if;
  if length(coalesce(note, '')) > 300 then raise exception 'A comment is 300 characters at most'; end if;
  select * into r from cost_plans where project_id = pid and year = (p ->> 'year')::int for update;
  if r.id is null then raise exception 'Save the cost plan first'; end if;
  if a = 'agree' then
    if not (role_of(me) = 'sa' or (role_of(me) = 'pm' and user_sees(me, pid))) then raise exception 'The project manager of the project marks the internal plan agreed' using errcode = '42501'; end if;
    if r.plan_int is null then raise exception 'Save the internal plan first'; end if;
    if r.plan_int ->> 'status' = 'Agreed' then raise exception 'Already agreed'; end if;
    update cost_plans set plan_int = plan_int || jsonb_build_object('status', 'Agreed', 'agreed_by', me, 'agreed_by_name', name_of(me), 'agreed_at', now_t),
      hist = hist || jsonb_build_object('at', now_t, 'by', name_of(me), 'part', 'int', 'action', 'Agreed with the project manager', 'note', note), updated_at = now() where id = r.id;
  elsif a = 'approve' then
    if not (role_of(me) in ('sa','exec') or pt_is_head(me)) then raise exception 'The head of planning and cost control, or an executive, approves the finance plan' using errcode = '42501'; end if;
    if r.plan_fin is null then raise exception 'Save the finance plan first'; end if;
    if r.plan_fin ->> 'status' = 'Approved' then raise exception 'Already approved'; end if;
    update cost_plans set plan_fin = plan_fin || jsonb_build_object('status', 'Approved', 'approved_by', me, 'approved_by_name', name_of(me), 'approved_at', now_t),
      hist = hist || jsonb_build_object('at', now_t, 'by', name_of(me), 'part', 'fin', 'action', 'Approved by management', 'note', note), updated_at = now() where id = r.id;
  else raise exception 'Unknown action'; end if;
  return jsonb_build_object('id', r.id);
end $$;

create or replace function cost_plan_features() returns jsonb language sql stable as $$ select jsonb_build_object('version', 45, 'cost_plans', true) $$;
revoke execute on function cost_plan_save(jsonb), cost_plan_act(jsonb), cost_plan_features(), cp_months(jsonb, numeric, numeric, text), cp_num(jsonb, text) from public, anon;
grant execute on function cost_plan_save(jsonb), cost_plan_act(jsonb), cost_plan_features() to authenticated;
