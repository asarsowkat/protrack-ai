-- ProTrack schema rollback v46 (ProTrackAI v3.42): undo schema-update-v46.sql.
-- The bulk upload of cost plans is refused, and cost_plan_save no longer takes the actual POC (the v45 function comes back).
-- The column plan_act and what it holds are kept: the MER still uses the actual POC uploaded before, and running v46 again
-- brings the upload back. Safe to run when v46 was never applied.

drop function if exists cost_plan_import(jsonb);
do $$ begin
  if to_regclass('public.cost_plans') is null then raise exception 'Nothing to undo: the v45 cost plan update is not on this database'; end if;
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

create or replace function cost_plan_features() returns jsonb language sql stable as $$ select jsonb_build_object('version', 45, 'cost_plans', true) $$;
grant execute on function cost_plan_save(jsonb), cost_plan_features() to authenticated;
