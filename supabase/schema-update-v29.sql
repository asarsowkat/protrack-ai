-- ProTrack schema update v29 (ProTrackAI v3.22): Home → Reporting status.
-- 1. rs_config: the super admin's reporting rules: the day of the next month monthly deliverables are due (1–28), the days
--    after the week ends weekly ones are due (0–14), and the deliverables required before the executive report of a
--    period is released (the internal report always; by default the monthly cost report too; the change order and claim
--    log, the budget supplement log and the invoice register update can be added).
-- 2. rs_exemptions: a project exempted for one period, with its reason, by the super admin or the Head of Planning and Cost
--    Control; it can be withdrawn (kept, marked withdrawn).
-- 3. rs_reminders: every reminder sent, with its deliverables, recipients, text, sender and time. A reminder is sent by a
--    super admin, the Head, a regional or portfolio manager or the section planning manager of the project's region
--    (release_approvers, v14), on a project in their access, at most once a day for the same deliverables. The recipients
--    must be planning or costing engineers or project managers with access to the project.
-- 4. reporting_act(p) = {kind: 'remind' | 'exempt' | 'cfg', args}, as the app's rsAct().
-- The statuses come from the releases (report_releases) and the uploads (import_batches) the server already holds; the
-- page holds the executive report of a period until every active project has released the required deliverables.
-- Needs schema-update-v14.sql (release_approvers). Additive. Safe to run twice. Undo: schema-rollback-v29.sql.

do $$ begin
  if to_regclass('public.release_approvers') is null then raise exception 'Run schema-update-v14.sql (STAGE-11-SETUP) first, then this update'; end if;
end $$;

create table if not exists rs_config (id int primary key default 1 check (id = 1), cfg jsonb not null, updated_by uuid references profiles(id), updated_at timestamptz not null default now());
insert into rs_config (id, cfg) values (1, '{"month_due_day":7,"week_due_days":2,"gate":{"int":true,"cost":true,"vo":false,"supp":false,"inv":false}}') on conflict (id) do nothing;
create table if not exists rs_exemptions (id text primary key default 'RX' || replace(uuid_generate_v4()::text, '-', ''), project_id text not null references projects(id) on delete cascade,
  period_type text not null check (period_type in ('month','week')), period text not null, reason text not null, "by" text, at timestamptz not null default now(), withdrawn_at timestamptz, withdrawn_by text);
create unique index if not exists rs_exemptions_one on rs_exemptions (project_id, period_type, period) where withdrawn_at is null;
create table if not exists rs_reminders (id text primary key default 'RR' || replace(uuid_generate_v4()::text, '-', ''), project_id text not null references projects(id) on delete cascade,
  period_type text not null check (period_type in ('month','week')), period text not null, keys text[] not null, "to" jsonb not null, note text, subject text, body text,
  "by" text, by_user uuid references profiles(id), by_role text, at timestamptz not null default now());

alter table rs_config enable row level security;
alter table rs_exemptions enable row level security;
alter table rs_reminders enable row level security;
drop policy if exists rs_config_read on rs_config;
create policy rs_config_read on rs_config for select using (auth.uid() is not null);
drop policy if exists rs_exemptions_read on rs_exemptions;
create policy rs_exemptions_read on rs_exemptions for select using (can_see(project_id));
drop policy if exists rs_reminders_read on rs_reminders;
create policy rs_reminders_read on rs_reminders for select using (can_see(project_id));
revoke all on rs_config, rs_exemptions, rs_reminders from anon;
revoke insert, update, delete, truncate on rs_config, rs_exemptions, rs_reminders from authenticated;
grant select on rs_config, rs_exemptions, rs_reminders to authenticated;
drop trigger if exists trg_rs_rem_append on rs_reminders;
create trigger trg_rs_rem_append before update or delete on rs_reminders for each row execute function pt_append_only();

create or replace function pt_rs_reminder_ok(u uuid, pid text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(user_sees(u, pid) and (role_of(u) in ('sa','rm','pf') or pt_is_head(u)
    or exists (select 1 from release_approvers a join projects p on p.region = a.region_id where a.user_id = u and p.id = pid)), false) $$;

-- p: {kind, args}. remind: [project_id, period_type, period, note, {keys, to: [{id, name, email, role}], subject, body}];
-- exempt: [project_id, period_type, period, reason, withdraw]; cfg: [{month_due_day, week_due_days, gate}]
create or replace function reporting_act(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); kind text := p ->> 'kind'; a jsonb := coalesce(p -> 'args', '[]'::jsonb); pid text := a ->> 0; t text := a ->> 1; per text := a ->> 2; pl jsonb; x jsonb; r rs_reminders; e rs_exemptions; c jsonb; d int; w int;
begin
  if me is null or role_of(me) is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if kind in ('remind','exempt') then
    if t not in ('month','week') or (t = 'month' and coalesce(per, '') !~ '^\d{4}-(0[1-9]|1[0-2])$') or (t = 'week' and coalesce(per, '') !~ '^\d{4}-W\d{2}$') then raise exception 'Unknown period'; end if;
    if pid is null or not exists (select 1 from projects where id = pid) then raise exception 'Unknown project'; end if;
  end if;
  if kind = 'remind' then
    if not pt_rs_reminder_ok(me, pid) then raise exception 'Only the super admin, the Head of Planning and Cost Control, the regional and portfolio managers and the section planning manager of the region send reminders' using errcode = '42501'; end if;
    pl := a -> 4;
    if jsonb_typeof(pl -> 'keys') <> 'array' or jsonb_array_length(pl -> 'keys') = 0 then raise exception 'Nothing outstanding to remind about for this project'; end if;
    if exists (select 1 from jsonb_array_elements_text(pl -> 'keys') k where k not in ('int','cost','vo','supp','inv') or (t = 'week' and k <> 'int')) then raise exception 'Unknown deliverable'; end if;
    if jsonb_typeof(pl -> 'to') <> 'array' or jsonb_array_length(pl -> 'to') = 0 or jsonb_array_length(pl -> 'to') > 30 then raise exception 'No planning or costing engineer or project manager is assigned to this project'; end if;
    for x in select * from jsonb_array_elements(pl -> 'to') loop
      if coalesce(role_of((x ->> 'id')::uuid), '') not in ('plan','costing','pm') or not user_sees((x ->> 'id')::uuid, pid) then raise exception '% is not a planning or costing engineer or project manager of this project', coalesce(x ->> 'name', x ->> 'id'); end if;
    end loop;
    if exists (select 1 from rs_reminders where project_id = pid and period_type = t and period = per and at::date = current_date and keys @> array(select jsonb_array_elements_text(pl -> 'keys'))) then
      raise exception 'Already reminded today for these deliverables'; end if;
    insert into rs_reminders (project_id, period_type, period, keys, "to", note, subject, body, "by", by_user, by_role)
    values (pid, t, per, array(select jsonb_array_elements_text(pl -> 'keys')), pl -> 'to', nullif(left(btrim(coalesce(a ->> 3, '')), 300), ''), left(pl ->> 'subject', 300), left(pl ->> 'body', 2000), name_of(me), me, role_of(me))
    returning * into r;
    return to_jsonb(r);
  elsif kind = 'exempt' then
    if not (role_of(me) = 'sa' or pt_is_head(me)) then raise exception 'Only the super admin or the Head of Planning and Cost Control exempts a project' using errcode = '42501'; end if;
    if not user_sees(me, pid) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
    if coalesce((a ->> 4)::boolean, false) then
      update rs_exemptions set withdrawn_at = now(), withdrawn_by = name_of(me) where project_id = pid and period_type = t and period = per and withdrawn_at is null returning * into e;
      if not found then raise exception 'This project is not exempted for this period'; end if;
      return to_jsonb(e);
    end if;
    if length(btrim(coalesce(a ->> 3, ''))) < 10 then raise exception 'Give the reason for the exemption (a sentence)'; end if;
    if exists (select 1 from rs_exemptions where project_id = pid and period_type = t and period = per and withdrawn_at is null) then raise exception 'Already exempted for this period'; end if;
    insert into rs_exemptions (project_id, period_type, period, reason, "by") values (pid, t, per, left(btrim(a ->> 3), 500), name_of(me)) returning * into e;
    return to_jsonb(e);
  elsif kind = 'cfg' then
    if role_of(me) is distinct from 'sa' then raise exception 'Only the super admin changes the reporting rules' using errcode = '42501'; end if;
    c := a -> 0;
    if coalesce(c ->> 'month_due_day', '') !~ '^\d{1,2}$' or (c ->> 'month_due_day')::int not between 1 and 28 then raise exception 'The monthly due day is a day from 1 to 28 of the next month'; end if;
    if coalesce(c ->> 'week_due_days', '') !~ '^\d{1,2}$' or (c ->> 'week_due_days')::int > 14 then raise exception 'The weekly due days are 0 to 14 days after the week ends'; end if;
    if not coalesce((c -> 'gate' ->> 'int')::boolean, false) then raise exception 'The internal report always holds the executive report'; end if;
    update rs_config set cfg = jsonb_build_object('month_due_day', (c ->> 'month_due_day')::int, 'week_due_days', (c ->> 'week_due_days')::int,
      'gate', jsonb_build_object('int', true, 'cost', coalesce((c -> 'gate' ->> 'cost')::boolean, false), 'vo', coalesce((c -> 'gate' ->> 'vo')::boolean, false),
        'supp', coalesce((c -> 'gate' ->> 'supp')::boolean, false), 'inv', coalesce((c -> 'gate' ->> 'inv')::boolean, false))), updated_by = me, updated_at = now() where id = 1;
    return (select cfg from rs_config where id = 1);
  end if;
  raise exception 'Unknown action %', coalesce(kind, '');
end $$;

create or replace function reporting_features() returns jsonb language sql immutable as $$ select '{"version":29,"reporting_status":true}'::jsonb $$;
revoke execute on function pt_rs_reminder_ok(uuid, text), reporting_act(jsonb), reporting_features() from public, anon;
grant execute on function reporting_act(jsonb), reporting_features() to authenticated;
