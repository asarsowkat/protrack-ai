-- ProTrack schema update v23 (ProTrackAI v3.17): the report email lists on the server, and the contract value of each
-- cost report column (cv_by) kept with the cost report.
-- 1. report_mail_lists holds who receives an email when a report is approved: the default list of internal reports
--    ('planning'), the list of monthly cost reports ('cost'), and a list of its own for the internal reports of a region.
--    Each list has the switch on / off, "weekly too" (internal reports), roles, named people and other addresses, as the
--    app's relMailCfg() (index.html, v3.17). report_mail_set(p) changes a list: a super admin any list; the section
--    planning manager of a region (release_approvers, v14) that region's internal report list only, as the app's
--    canRelMailRegion(). Everyone who approves reports reads the lists, since the email goes out from the approver's
--    browser through the server's mail function (send-daily-report). A region without a list of its own uses the default.
-- 2. A cost report by WBS head keeps figures.cv_by, the contract value each column's gross margin is measured on, as the
--    app's crCompute(): tender (A) and Rev-0 (B1) on the original contract value; revised Rev-0 (B2), current budget (D)
--    and EAC (I) on the internal revised contract value (v20); previous version (C) on the contract value of the previous
--    released cost report, else the internal revised value at the end of the previous month (prev_period says which month).
--    The server works it out itself, by a trigger, on every save of a draft; at approval it sets A, B1, B2, D and I as of
--    approval, as relActLocal() does (prev is kept as saved), and a released version cannot be changed (pt_release_frozen).
--    release_act_cv(p) takes the same p as release_act_bl / release_act and accepts the cv_by the browser sends: it checks
--    its shape, lets release_act_bl do everything it does today, and says which columns the server saved differently
--    (cv_by_differs), which happens only when the page was open while the change order and claim log changed.
--    release_act and release_act_bl are NOT replaced.
-- 3. margin_mail_features() tells the app this update is in, so live.html reads and saves the lists here, and sends cv_by.
-- Needs schema-update-v20.sql (pt_contract_of and the contract snapshot at approval) and schema-update-v22.sql
-- (release_act_bl). Does not need v19 or v21.
-- Additive: one table, new functions and one trigger. Safe to run twice. Undo: schema-rollback-v23.sql.

do $$ begin
  if to_regprocedure('public.pt_contract_of(text,text)') is null or to_regprocedure('public.release_act_bl(jsonb)') is null
     or not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'report_releases' and column_name = 'contract_snapshot') then
    raise exception 'Run schema-update-v20.sql (STAGE-16-SETUP) and schema-update-v22.sql (STAGE-18-SETUP) first, then this update'; end if;
end $$;

-- ------------------------------------------------------------------ 1. the report email lists
create table if not exists report_mail_lists (
  id bigserial primary key,
  kind text not null check (kind in ('planning','cost')),               -- planning: internal reports; cost: monthly cost reports
  region_id text references regions(id) on delete cascade,             -- set: the region's own internal report list
  enabled boolean not null default true,                                -- "Send an email when ... is approved"
  weekly boolean not null default true,                                 -- internal reports: weekly too (monthly always)
  roles text[] not null default '{}',                                   -- everyone in the role with access to the project
  people uuid[] not null default '{}',                                  -- named people, any project
  extra text[] not null default '{}',                                   -- other addresses
  updated_by uuid references profiles(id), updated_at timestamptz not null default now(),
  constraint report_mail_lists_region_ok check (region_id is null or kind = 'planning'));
create unique index if not exists report_mail_lists_one on report_mail_lists (kind, (coalesce(region_id, '')));
-- the defaults of the app (relMailCfg)
insert into report_mail_lists (kind, region_id, enabled, weekly, roles) values
  ('planning', null, true, true, array['pm','pf','rm','exec','plan']),
  ('cost', null, true, true, array['pm','pf','rm','exec','costing'])
on conflict do nothing;

-- the roles an email list may name, as the app's MAIL_ROLES
create or replace function pt_mail_roles() returns text[] language sql immutable as $$
  select array['eng','sm','pm','pf','rm','plan','costing','exec','sa'] $$;

-- reads the lists: whoever approves reports (super admin, the Head, a regional planning section manager, anyone given the
-- right to approve internal or cost reports)
create or replace function pt_rel_mail_reader(u uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) is not null and (role_of(u) = 'sa' or pt_is_head(u) or exists (select 1 from release_approvers a where a.user_id = u)
    or pt_cost_approver(u) or pt_right(u, 'report.internal.approve')), false) $$;

-- changes a region's internal report list: a super admin, or the region's planning section manager (canRelMailRegion)
create or replace function pt_rel_mail_region_keeper(u uuid, rg text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) = 'sa' or (role_of(u) is not null and exists (select 1 from release_approvers a where a.user_id = u and a.region_id = rg)), false) $$;

alter table report_mail_lists enable row level security;
drop policy if exists rml_read on report_mail_lists;
create policy rml_read on report_mail_lists for select using (pt_rel_mail_reader(auth.uid()));
-- no write policy: lists change through report_mail_set() only

-- p: {kind: 'planning' | 'cost', region: region id or empty, own: true | false (a region only), on, weekly, roles: [...],
--     people: [user id, ...], extra: [address, ...]}
--   own false: the region goes back to the default list (its own list is removed)
--   own true without the other fields: the region gets a list of its own, a copy of the default internal report list
--   otherwise the list is replaced by the one sent (a region's list is created when it has none)
create or replace function report_mail_set(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); k text := p ->> 'kind'; rg text := nullif(btrim(coalesce(p ->> 'region', '')), ''); rn text;
        ro text[]; pe uuid[]; ex text[]; bad text; n int; lst report_mail_lists; d report_mail_lists;
begin
  if me is null or role_of(me) is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if k is null or k not in ('planning','cost') then raise exception 'Unknown list: use planning (internal reports) or cost (monthly cost reports)'; end if;
  if rg is not null then
    if k <> 'planning' then raise exception 'Only internal reports have a list per region'; end if;
    select name into rn from regions where id = rg;
    if rn is null then raise exception 'Unknown region'; end if;
    if not pt_rel_mail_region_keeper(me, rg) then raise exception 'Only the section planning manager of the region or a super admin changes this list' using errcode = '42501'; end if;
  elsif role_of(me) <> 'sa' then raise exception 'Only a super admin changes this list' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtext('protrack:relmail'));

  if rg is not null and p ? 'own' and not coalesce((p ->> 'own')::boolean, false) then
    delete from report_mail_lists where kind = 'planning' and region_id = rg;
    insert into change_log (text, by_user) values ('Internal report email list for ' || rn || ': default list', me);
    return jsonb_build_object('kind', k, 'region', rg, 'own', false);
  end if;
  if rg is not null and coalesce((p ->> 'own')::boolean, false) and not (p ? 'roles' or p ? 'people' or p ? 'extra' or p ? 'on' or p ? 'weekly') then
    select * into lst from report_mail_lists where kind = 'planning' and region_id = rg;
    if lst.id is null then
      select * into d from report_mail_lists where kind = 'planning' and region_id is null;
      insert into report_mail_lists (kind, region_id, enabled, weekly, roles, people, extra, updated_by)
      values ('planning', rg, coalesce(d.enabled, true), coalesce(d.weekly, true), coalesce(d.roles, array['pm','pf','rm','exec','plan']),
              coalesce(d.people, '{}'), coalesce(d.extra, '{}'), me) returning * into lst;
      insert into change_log (text, by_user) values ('Internal report email list for ' || rn || ': own list', me);
    end if;
    return to_jsonb(lst);
  end if;

  -- the list as sent
  if (p ? 'roles' and jsonb_typeof(p -> 'roles') <> 'array') or (p ? 'people' and jsonb_typeof(p -> 'people') <> 'array')
     or (p ? 'extra' and jsonb_typeof(p -> 'extra') <> 'array') then raise exception 'Roles, people and addresses must be lists'; end if;
  select coalesce(array_agg(distinct x), '{}') into ro from jsonb_array_elements_text(coalesce(p -> 'roles', '[]'::jsonb)) x;
  select string_agg(x, ', ') into bad from unnest(ro) x where not (x = any(pt_mail_roles()));
  if bad is not null then raise exception 'Unknown role in the list: %', bad; end if;
  select string_agg(x, ', ') into bad from jsonb_array_elements_text(coalesce(p -> 'people', '[]'::jsonb)) x
   where case when x ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then not exists (select 1 from profiles where id = x::uuid) else true end;
  if bad is not null then raise exception 'Unknown person in the list: %', bad; end if;
  select coalesce(array_agg(distinct x::uuid), '{}') into pe from jsonb_array_elements_text(coalesce(p -> 'people', '[]'::jsonb)) x;
  select string_agg(x, ', ') into bad from jsonb_array_elements_text(coalesce(p -> 'extra', '[]'::jsonb)) x
   where btrim(x) !~ '^[^\s@,;]+@[^\s@,;]+\.[^\s@,;]+$' or length(btrim(x)) > 254;   -- the app's RM_EMAIL
  if bad is not null then raise exception 'Not an email address: %', bad; end if;
  select coalesce(array_agg(e order by o), '{}') into ex
    from (select btrim(x) e, min(o) o from jsonb_array_elements_text(coalesce(p -> 'extra', '[]'::jsonb)) with ordinality t(x, o) group by btrim(x)) s;
  n := cardinality(ex);
  if n > 50 then raise exception 'At most 50 other addresses'; end if;
  if cardinality(pe) > 500 then raise exception 'At most 500 named people'; end if;
  if (p ? 'on' and jsonb_typeof(p -> 'on') <> 'boolean') or (p ? 'weekly' and jsonb_typeof(p -> 'weekly') <> 'boolean') then
    raise exception 'on and weekly must be true or false'; end if;
  insert into report_mail_lists (kind, region_id, enabled, weekly, roles, people, extra, updated_by, updated_at)
  values (k, rg, coalesce((p ->> 'on')::boolean, true), coalesce((p ->> 'weekly')::boolean, true), ro, pe, ex, me, now())
  on conflict (kind, (coalesce(region_id, ''))) do update
     set enabled = excluded.enabled, weekly = excluded.weekly, roles = excluded.roles, people = excluded.people, extra = excluded.extra,
         updated_by = me, updated_at = now()
  returning * into lst;
  insert into change_log (text, by_user)
  values ('Report email list changed: ' || case when k = 'cost' then 'monthly cost reports' else 'internal reports' end || coalesce(' for ' || rn, ''), me);
  return to_jsonb(lst);
end $$;

-- ------------------------------------------------------------------ 2. the contract value of each cost report column
create or replace function pt_cv_cols() returns text[] language sql immutable as $$
  select array['tender','rev0','rev0_rev','prev','budget','eac'] $$;

-- cv_by of a cost report of the month, as the app's crCompute() (index.html, v3.17); null when the project has no
-- contract value (then the app has none either)
create or replace function pt_cost_cv_by(pid text, per text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare cc jsonb := pt_contract_of(pid, per); ri numeric := pt_num(cc ->> 'rev_int'); pr report_releases; pm text; pcv numeric;
begin
  if ri is null or per !~ '^\d{4}-\d{2}$' then return null; end if;
  -- the previous released cost report, as the app's crPrev()
  select * into pr from report_releases r where r.project_id = pid and r.kind = 'cost' and r.status = 'Released' and r.period < per
   order by r.period desc, r.rev desc limit 1;
  pm := to_char(to_date(per || '-01', 'YYYY-MM-DD') - interval '1 month', 'YYYY-MM');
  if pr.id is not null then pcv := pt_num(pr.figures ->> 'contract_value'); end if;
  if coalesce(pcv, 0) = 0 then pcv := pt_num(pt_contract_of(pid, pm) ->> 'rev_int'); end if;
  return jsonb_build_object('tender', cc -> 'orig', 'rev0', cc -> 'orig', 'rev0_rev', ri, 'prev', pcv, 'budget', ri, 'eac', ri,
                            'prev_period', case when pr.id is not null then pr.period else pm end);
end $$;

-- Draft and submitted cost reports by WBS head: cv_by is worked out whenever the figures change (a save, or Revise).
-- At approval (status moves to Released): A, B1, B2, D and I are set as of approval from the contract breakdown saved
-- with the release (v20's trg_rr_contract runs first: triggers run in name order), prev and prev_period stay as saved.
-- A released or superseded version is left alone (pt_release_frozen refuses any change to its figures).
create or replace function pt_release_cvby() returns trigger
language plpgsql security definer set search_path = public as $$
declare c jsonb; cv jsonb;
begin
  if new.kind is distinct from 'cost' then return new; end if;
  if tg_op = 'UPDATE' and old.status in ('Released','Superseded') then return new; end if;
  if new.status = 'Released' then
    c := coalesce(new.contract_snapshot, pt_contract_of(new.project_id, new.period));
    if c ->> 'rev_int' is not null then
      cv := case when jsonb_typeof(new.figures -> 'cv_by') = 'object' then new.figures -> 'cv_by' else '{}'::jsonb end;
      new.figures := coalesce(new.figures, '{}'::jsonb) || jsonb_build_object('cv_by', cv || jsonb_build_object(
        'tender', c -> 'orig', 'rev0', c -> 'orig', 'rev0_rev', c -> 'rev_int', 'budget', c -> 'rev_int', 'eac', c -> 'rev_int'));
    end if;
    return new;
  end if;
  if (tg_op = 'INSERT' or new.figures is distinct from old.figures) and jsonb_typeof(new.figures -> 'wbs') = 'array' then
    cv := pt_cost_cv_by(new.project_id, new.period);
    new.figures := case when cv is null then new.figures - 'cv_by' else new.figures || jsonb_build_object('cv_by', cv) end;
  end if;
  return new;
end $$;
drop trigger if exists trg_rr_cvby on report_releases;
create trigger trg_rr_cvby before insert or update on report_releases for each row execute function pt_release_cvby();

-- p: as release_act_bl. figures.cv_by {tender, rev0, rev0_rev, prev, budget, eac, prev_period} is checked and taken out
-- before release_act sees it (it accepts numbers, dates and short texts only); the server's own cv_by is saved (above).
-- The result is the saved report, plus cv_by_differs: the columns where the browser's value and the server's differ by
-- 1 SAR or more. Without cv_by, this is exactly release_act_bl.
create or replace function release_act_cv(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f jsonb := p -> 'figures'; cv jsonb; k text; res jsonb; sv jsonb; diff text[];
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if jsonb_typeof(f) = 'object' and f ? 'cv_by' then
    cv := f -> 'cv_by';
    p := jsonb_set(p, '{figures}', f - 'cv_by');
    if jsonb_typeof(cv) = 'null' then cv := null;
    elsif jsonb_typeof(cv) <> 'object' then raise exception 'The contract values by column must be sent as {tender, rev0, rev0_rev, prev, budget, eac}';
    else
      for k in select jsonb_object_keys(cv) loop
        if k = 'prev_period' then
          if jsonb_typeof(cv -> k) <> 'null' and not pt_period_ok(cv ->> k, 'month') then raise exception 'The previous month of the contract values must look like 2026-09'; end if;
        elsif k = any(pt_cv_cols()) then
          if jsonb_typeof(cv -> k) not in ('number','null') and pt_bad_num(cv ->> k) then raise exception 'Contract value % must be a number', k; end if;
          if pt_num(cv ->> k) < 0 then raise exception 'Contract value % cannot be negative', k; end if;
        else raise exception 'Unknown column in the contract values: %', k; end if;
      end loop;
    end if;
  end if;
  res := release_act_bl(p);
  if cv is not null and jsonb_typeof(res -> 'figures' -> 'cv_by') = 'object' then
    sv := res -> 'figures' -> 'cv_by';
    select array_agg(c order by o) into diff from unnest(pt_cv_cols()) with ordinality t(c, o)
     where abs(coalesce(pt_num(cv ->> c), 0) - coalesce(pt_num(sv ->> c), 0)) >= 1;
    if diff is not null then res := res || jsonb_build_object('cv_by_differs', to_jsonb(diff)); end if;
  end if;
  return res;
end $$;

-- ------------------------------------------------------------------ 3. the app asks this to know v23 is in (schema-rollback-v23.sql removes it)
create or replace function margin_mail_features() returns jsonb language sql immutable as $$
  select '{"version":23,"mail_lists":true,"cv_by":true}'::jsonb $$;

-- ------------------------------------------------------------------ grants
revoke execute on function pt_cost_cv_by(text, text) from public, anon, authenticated;
revoke execute on function report_mail_set(jsonb), release_act_cv(jsonb), pt_rel_mail_reader(uuid), pt_rel_mail_region_keeper(uuid, text) from public, anon;
grant execute on function report_mail_set(jsonb), release_act_cv(jsonb), margin_mail_features(), pt_rel_mail_reader(uuid), pt_rel_mail_region_keeper(uuid, text) to authenticated;
revoke all on report_mail_lists from anon;
grant select on report_mail_lists to authenticated;
