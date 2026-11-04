-- ProTrack schema update v56 (ProTrackAI v3.57): the invoicing phase of an activity from a P6 activity code.
-- 1. activities.inv_phase: ENG, PRC, CON or TC, or empty (the phase then follows the WBS wording, as before).
-- 2. project_inv_phase: the activity code type chosen for the project and the phase of each of its values, read by those
--    who see the project.
-- 3. act_inv_phase_set(p): {project_id, code_type, map: {value: phase}, rows: [{id, phase}]}. Planning engineers and super
--    admins of the project (can_plan, the rule of import_baseline), right after a baseline import. Sets the phase of the
--    activities listed (empty clears it), keeps the code type and map, and logs the change. An empty code type clears the
--    project's choice.
-- 4. media_features() reports version 56.
-- Needs schema-update-v55.sql. Additive. Safe to run twice. Undo: schema-rollback-v56.sql.

do $$ begin
  if to_regprocedure('public.dpr_notes_set(jsonb)') is null then
    raise exception 'Run schema-update-v55.sql (STAGE-49-SETUP) first, then this update'; end if;
end $$;

alter table activities add column if not exists inv_phase text;
alter table activities drop constraint if exists activities_inv_phase_ok;
alter table activities add constraint activities_inv_phase_ok check (inv_phase is null or inv_phase in ('ENG', 'PRC', 'CON', 'TC'));

create table if not exists project_inv_phase (
  project_id text primary key references projects(id) on delete cascade,
  code_type text,                                 -- the P6 activity code type that carries the invoicing phase
  map jsonb not null default '{}'::jsonb,         -- {"<activity code value>":"ENG",...}
  updated_by uuid references profiles(id), updated_at timestamptz not null default now());
alter table project_inv_phase enable row level security;
drop policy if exists pip_read on project_inv_phase;
create policy pip_read on project_inv_phase for select using (can_see(project_id));
grant select on project_inv_phase to authenticated;

-- p: {project_id, code_type, map, rows: [{id, phase}]}
create or replace function act_inv_phase_set(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); pid text := p ->> 'project_id'; ct text := nullif(btrim(coalesce(p ->> 'code_type', '')), '');
  mp jsonb := coalesce(p -> 'map', '{}'::jsonb); rows jsonb := coalesce(p -> 'rows', '[]'::jsonb); bad text; n int; unknown int;
begin
  if me is null or pid is null or not can_plan(pid) then
    raise exception 'Only planning engineers and super admins of this project set the invoicing phase' using errcode = '42501'; end if;
  if length(coalesce(ct, '')) > 100 then raise exception 'The activity code type is 100 characters at most'; end if;
  if jsonb_typeof(mp) <> 'object' or jsonb_typeof(rows) <> 'array' then raise exception 'The map is an object and the rows a list'; end if;
  if jsonb_array_length(rows) > 30000 then raise exception 'At most 30,000 activities at a time'; end if;
  select string_agg(k, ', ') into bad from (select k from jsonb_each_text(mp) e(k, v) where v not in ('ENG', 'PRC', 'CON', 'TC') or length(k) > 200 limit 5) d;
  if bad is not null then raise exception 'Unknown phase for the code values %: use ENG, PRC, CON or TC', bad; end if;
  if exists (select 1 from jsonb_array_elements(rows) x where coalesce(x ->> 'id', '') = '') then
    raise exception 'Each activity needs its ID; nothing was set'; end if;
  select string_agg(x ->> 'id', ', ') into bad from (select x from jsonb_array_elements(rows) x
    where coalesce(x ->> 'phase', '') not in ('', 'ENG', 'PRC', 'CON', 'TC') limit 5) d;
  if bad is not null then raise exception 'Each activity needs a phase of ENG, PRC, CON or TC, or none (%)', bad; end if;
  update activities a set inv_phase = nullif(x ->> 'phase', '')
    from jsonb_array_elements(rows) x where a.project_id = pid and a.id = x ->> 'id';
  get diagnostics n = row_count;
  select count(*) into unknown from jsonb_array_elements(rows) x where not exists (select 1 from activities a where a.project_id = pid and a.id = x ->> 'id');
  if ct is null then delete from project_inv_phase where project_id = pid;
  else insert into project_inv_phase (project_id, code_type, map, updated_by, updated_at) values (pid, ct, mp, me, now())
    on conflict (project_id) do update set code_type = excluded.code_type, map = excluded.map, updated_by = excluded.updated_by, updated_at = excluded.updated_at; end if;
  insert into change_log (project_id, text, by_user) values (pid,
    case when ct is null then format('Invoicing phase from the WBS wording (%s activities)', n)
      else format('Invoicing phase from the P6 activity code "%s": %s activities', ct, n) end, me);
  return jsonb_build_object('updated', n, 'unknown', unknown);
end $$;
revoke execute on function act_inv_phase_set(jsonb) from public, anon;
grant execute on function act_inv_phase_set(jsonb) to authenticated;

create or replace function media_features() returns jsonb language sql stable as $$ select jsonb_build_object('version', 56, 'logos', true, 'report_media', true, 'dpr_media', true, 'dpr_notes', true, 'inv_phase', true) $$;
revoke execute on function media_features() from public, anon;
grant execute on function media_features() to authenticated;
