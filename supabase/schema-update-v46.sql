-- ProTrack schema update v46 (ProTrackAI v3.42): the cost plans in bulk from Excel, and the actual POC of each month.
-- 1. cost_plans.plan_act: the actual POC % reached in each month of the year, uploaded with the cost plans. The app uses it for
--    a month without a released cost report (a released cost report of the month always comes first).
-- 2. cost_plan_save also takes the part 'act', with the same checks as the forecast (twelve months, each -100 to 100 or empty).
-- 3. cost_plan_import(p): the rows of an uploaded workbook (COST PLAN (I), COST PLAN (F), ACTUAL POC) saved together, by a super
--    admin or the costing coordinator (Planning and Cost Control position "coordinator"). Each row is one cost_plan_save, with its
--    rights (the project must be one the user sees) and checks, and the history note "Bulk upload: <file>". All or nothing:
--    a refused row refuses the upload, naming the row. At most 2000 rows.
-- 4. cost_plan_features() says version 46.
-- Needs schema-update-v45.sql. Additive. Safe to run twice. Undo: schema-rollback-v46.sql.

do $$ begin
  if to_regclass('public.cost_plans') is null or to_regprocedure('public.cp_months(jsonb,numeric,numeric,text)') is null then
    raise exception 'Run the cost plan update (schema-update-v45.sql, STAGE-39-SETUP) first, then this update'; end if;
end $$;

alter table cost_plans add column if not exists plan_act jsonb;

-- p: {project_id, year, part: 'int' | 'fin' | 'fc' | 'base' | 'act', data: {...}, note}
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
  if part is null or part not in ('int','fin','fc','base','act') then raise exception 'Unknown part of the cost plan'; end if;
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
  elsif part = 'act' then
    v := jsonb_build_object('months', cp_months(d -> 'months', -100, 100, 'Actual POC %'));
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
    plan_act = case when part = 'act' then v else plan_act end,
    hist = hist || h, updated_at = now()
  where id = r.id;
  return jsonb_build_object('id', r.id);
end $$;

-- p: {year, file_name, note, rows: [{project_id, part, data}]}
create or replace function cost_plan_import(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); x jsonb; i int := 0; f text := left(btrim(coalesce(p ->> 'file_name', '')), 120); note text := nullif(btrim(coalesce(p ->> 'note', '')), '');
begin
  if me is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if not (role_of(me) = 'sa' or pt_is_coord(me)) then raise exception 'Only a super admin or the costing coordinator uploads cost plans in bulk' using errcode = '42501'; end if;
  if coalesce(p ->> 'year', '') !~ '^\d{4}$' then raise exception 'Give the year'; end if;
  if jsonb_typeof(p -> 'rows') is distinct from 'array' or jsonb_array_length(p -> 'rows') = 0 then raise exception 'Nothing to save'; end if;
  if jsonb_array_length(p -> 'rows') > 2000 then raise exception 'At most 2000 rows in one upload'; end if;
  if length(coalesce(note, '')) > 200 then raise exception 'A comment is 200 characters at most'; end if;
  for x in select * from jsonb_array_elements(p -> 'rows') loop
    i := i + 1;
    begin
      perform cost_plan_save(jsonb_build_object('project_id', x ->> 'project_id', 'year', p ->> 'year', 'part', x ->> 'part', 'data', x -> 'data',
        'note', left('Bulk upload: ' || coalesce(nullif(f, ''), 'workbook') || coalesce(' · ' || note, ''), 300)));
    exception when others then
      raise exception 'Row % (%, %): %', i, x ->> 'project_id', x ->> 'part', sqlerrm using errcode = sqlstate;
    end;
  end loop;
  return jsonb_build_object('saved', i);
end $$;

create or replace function cost_plan_features() returns jsonb language sql stable as $$ select jsonb_build_object('version', 46, 'cost_plans', true, 'bulk_import', true, 'actual_poc', true) $$;
revoke execute on function cost_plan_import(jsonb) from public, anon;
grant execute on function cost_plan_import(jsonb), cost_plan_save(jsonb), cost_plan_features() to authenticated;
