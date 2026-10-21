-- ProTrack schema update v25 (ProTrackAI v3.19.1): the drop-down lists of the delay events register.
-- 1. delay_lists keeps six lists of the company "Delay Events Register" workbook: claim identification, entitlement,
--    liability, concurrency, mitigation and claim owner, as the app's DLY_LISTS. The event status list stays Ongoing /
--    Closed (it decides the closing date and the claim duration) and is not stored.
-- 2. delay_lists_set(p) changes one list: a super admin only, as the app's dlyListSet(). Items are trimmed, 1 to 60 per
--    list, none empty, at most 200 characters, no two alike (whatever the case). Each change is kept in delay_list_audit.
-- 3. delay_act and delay_import accept a value of the list (in the list's spelling), or the value the event already
--    holds (an item removed from a list stays on the events that have it), as the app's dlyApplyLocal(). Another value
--    is refused: "<column>: "<value>" is not in the list. A super admin can add it in Settings -> Delay register lists".
--    pt_dly_merge and pt_dly_label are replaced for this; delay_act, delay_import and pt_dly_write are not touched.
-- Needs schema-update-v24.sql (STAGE-20-SETUP). Additive: two tables, new functions. Safe to run twice.
-- Undo: schema-rollback-v25.sql.

do $$ begin
  if to_regprocedure('public.pt_dly_merge(text,uuid,jsonb)') is null or to_regclass('public.delay_events') is null then
    raise exception 'Run schema-update-v24.sql (STAGE-20-SETUP) first, then this update'; end if;
end $$;

-- ------------------------------------------------------------------ 1. the lists
create table if not exists delay_lists (
  key text primary key check (key in ('identification','entitlement','liability','concurrency','mitigation','owner')),
  items text[] not null check (cardinality(items) between 1 and 60),
  updated_by uuid references profiles(id), updated_at timestamptz not null default now());
create table if not exists delay_list_audit (
  id bigserial primary key,
  key text not null, items text[] not null,
  by_user uuid references profiles(id), by_name text,
  at_time timestamptz not null default now());

-- the workbook's lists, word for word
create or replace function pt_dly_list_default(k text) returns text[] language sql immutable as $$
  select case k
    when 'entitlement' then array['EOT Only','EOT + Cost','V.O (Cost Only)','V.O (Time & Cost)','To Be Determined']
    when 'liability' then array['Employer','Engineer / PMC','SubContractor / Supplier','Neutral / Force Majeure','Joint Venture']
    when 'concurrency' then array['No Concurrency','Contractor Concurrent Delay','Third Party Concurrent','Under Assessment']
    when 'owner' then array['Regional Manager','Portfolio Manager','Project Manager']
    when 'mitigation' then array['Notice submitted','Particulars under preparation','EOT Claim Submitted','EOT Claim Approved','Revised Schedule Submitted & Approved']
    when 'identification' then array['Employer Delayed Approvals','Delayed access to Site','Delayed permits','Design changes','Employer / Engineer Variations','Suspension instructions','Employer / Engineer acts, such as verbal instructions or approval comments','Unforeseen conditions','Force Majeure','Legislative Change','Claims Related to S/C or Suppliers','Others,...']
  end $$;
insert into delay_lists (key, items)
select k, pt_dly_list_default(k) from unnest(array['identification','entitlement','liability','concurrency','mitigation','owner']) k
on conflict (key) do nothing;

alter table delay_lists enable row level security;
alter table delay_list_audit enable row level security;
drop policy if exists dl_read on delay_lists;
create policy dl_read on delay_lists for select using (auth.uid() is not null);
drop policy if exists dla_read on delay_list_audit;
create policy dla_read on delay_list_audit for select using (role_of(auth.uid()) = 'sa');
drop trigger if exists trg_dla_append on delay_list_audit;
create trigger trg_dla_append before update or delete on delay_list_audit for each row execute function pt_append_only();
drop trigger if exists trg_dla_truncate on delay_list_audit;
create trigger trg_dla_truncate before truncate on delay_list_audit execute function pt_no_truncate();
revoke all on delay_lists, delay_list_audit from anon;
revoke insert, update, delete, truncate on delay_lists, delay_list_audit from authenticated;
grant select on delay_lists, delay_list_audit to authenticated;

create or replace function pt_dly_list(k text) returns text[] language sql stable security definer set search_path = public as $$
  select coalesce((select items from delay_lists where key = k), pt_dly_list_default(k)) $$;

-- p: {key, items: [text]}
create or replace function delay_lists_set(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); k text := p ->> 'key'; it text[] := '{}'; x jsonb; v text; low text[] := '{}';
begin
  if me is null or role_of(me) is distinct from 'sa' then raise exception 'Only a super admin changes the lists' using errcode = '42501'; end if;
  if k = 'status' then raise exception 'The event status list is fixed: Ongoing and Closed decide the closing date and the claim duration'; end if;
  if k is null or k not in ('identification','entitlement','liability','concurrency','mitigation','owner') then raise exception 'Unknown list'; end if;
  if jsonb_typeof(p -> 'items') is distinct from 'array' or jsonb_array_length(p -> 'items') = 0 then raise exception 'A list needs at least one item'; end if;
  if jsonb_array_length(p -> 'items') > 60 then raise exception 'A list has at most 60 items'; end if;
  for x in select * from jsonb_array_elements(p -> 'items') loop
    v := btrim(regexp_replace(coalesce(x #>> '{}', ''), '\s+', ' ', 'g'));
    if v = '' then raise exception 'An item cannot be empty'; end if;
    if length(v) > 200 then raise exception 'An item is at most 200 characters'; end if;
    if lower(v) = any(low) then raise exception '"%" is already in the list', v; end if;
    it := it || v; low := low || lower(v);
  end loop;
  insert into delay_lists (key, items, updated_by, updated_at) values (k, it, me, now())
  on conflict (key) do update set items = excluded.items, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  insert into delay_list_audit (key, items, by_user, by_name) values (k, it, me, name_of(me));
  return jsonb_build_object('key', k, 'items', to_jsonb(it));
end $$;

-- ------------------------------------------------------------------ 2. the rules read the lists
create or replace function pt_dly_label(k text) returns text language sql immutable as $$
  select case k when 'start_date' then 'Claim event start date' when 'closed_on' then 'Claim event closing date (if closed)'
    when 'notice_date' then 'Notice of claim submission date' when 'data_date' then 'Claim data date'
    when 'prolong_cost' then 'Prolongation cost impact (SAR, if calculated)' when 'vo_omit' then 'Variation orders cost, omission (SAR, if calculated)'
    when 'vo_add' then 'Variation orders cost, added (SAR, if calculated)' when 'identification' then 'Claim identification'
    when 'entitlement' then 'Entitlement type' when 'liability' then 'Liability party' when 'concurrency' then 'Concurrency flag'
    when 'mitigation' then 'Mitigation / recovery action' when 'owner' then 'Claim owner' else k end $$;

create or replace function pt_dly_merge(pid text, eid uuid, f jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare m jsonb := '{}'::jsonb; old jsonb; k text; v text; c text; n numeric; today date := current_date;
begin
  if eid is not null then select to_jsonb(e) into m from delay_events e where id = eid; end if;
  old := m;
  foreach k in array pt_dly_keys() loop
    if not (f ? k) then continue; end if;
    v := nullif(btrim(coalesce(f ->> k, '')), '');
    if k in ('start_date','closed_on','notice_date','data_date') then
      if v is not null and (v !~ '^\d{4}-\d{2}-\d{2}$' or pt_date(v) is null) then raise exception '%: not a valid date', pt_dly_label(k); end if;
      m := m || jsonb_build_object(k, v);
    elsif k = 'time_bar' then
      if v is not null and (v !~ '^[0-9]{1,4}$' or v::int > 3650) then raise exception 'The time bar is a whole number of days, from 0 to 3650'; end if;
      m := m || jsonb_build_object(k, v::int);
    elsif k in ('sched_impact','prolong_cost','vo_omit','vo_add') then m := m || jsonb_build_object(k, pt_dly_numtext(v));
    elsif k = 'status' then
      if pt_dly_status(v) is null then raise exception 'The delay event status is Ongoing or Closed'; end if;
      m := m || jsonb_build_object(k, pt_dly_status(v));
    elsif k in ('identification','entitlement','liability','concurrency','mitigation','owner') then
      -- v25: a value of the list (its spelling), or the value the event already holds
      v := regexp_replace(v, '\s+', ' ', 'g');
      c := (select x from unnest(pt_dly_list(k)) x where lower(x) = lower(v) limit 1);
      if v is null or c is not null then m := m || jsonb_build_object(k, c);
      elsif v is not distinct from (old ->> k) then m := m || jsonb_build_object(k, v);
      else raise exception '%: "%" is not in the list. A super admin can add it in Settings → Delay register lists', pt_dly_label(k), v; end if;
    else m := m || jsonb_build_object(k, left(v, case when k in ('event_no','identification','entitlement','liability','concurrency','owner') then 200 else 4000 end));
    end if;
  end loop;
  if eid is null and nullif(m ->> 'status', '') is null then m := m || jsonb_build_object('status', case when nullif(m ->> 'closed_on', '') is not null then 'Closed' else 'Ongoing' end); end if;
  if nullif(btrim(coalesce(m ->> 'name', '')), '') is null then raise exception 'Enter the claim event name'; end if;
  if nullif(m ->> 'start_date', '') is null then raise exception 'Enter the claim event start date'; end if;
  if (m ->> 'start_date')::date > today then raise exception 'The claim event start date cannot be in the future'; end if;
  if m ->> 'status' = 'Closed' and nullif(m ->> 'closed_on', '') is null then raise exception 'Enter the closing date of a closed event'; end if;
  if m ->> 'status' <> 'Closed' and nullif(m ->> 'closed_on', '') is not null then
    raise exception 'A closing date is entered only when the event is closed: set the status to Closed, or clear the date'; end if;
  if (m ->> 'closed_on')::date < (m ->> 'start_date')::date then raise exception 'The closing date cannot be before the start date'; end if;
  if (m ->> 'closed_on')::date > today then raise exception 'The closing date cannot be in the future'; end if;
  if (m ->> 'notice_date')::date < (m ->> 'start_date')::date then raise exception 'The notice of claim cannot be dated before the event started'; end if;
  if (m ->> 'notice_date')::date > today then raise exception 'The notice of claim submission date cannot be in the future'; end if;
  if (m ->> 'data_date')::date > today then raise exception 'The claim data date cannot be in the future'; end if;
  if pt_dly_num(m ->> 'sched_impact') < 0 then raise exception 'The schedule impact cannot be negative'; end if;
  foreach k in array array['prolong_cost','vo_omit','vo_add'] loop
    n := pt_dly_num(m ->> k);
    if n < 0 then raise exception '%: enter the amount as a positive number', pt_dly_label(k); end if;
  end loop;
  if nullif(m ->> 'event_no', '') is not null and exists (select 1 from delay_events where project_id = pid and id is distinct from eid and pt_dly_nokey(event_no) = pt_dly_nokey(m ->> 'event_no')) then
    raise exception '% is already used on this project', m ->> 'event_no'; end if;
  return m;
end $$;

-- the app asks this to know v25 is in (schema-rollback-v25.sql removes it)
create or replace function delay_features() returns jsonb language sql immutable as $$
  select '{"version":25,"delay_register":true,"delay_lists":true}'::jsonb $$;

-- ------------------------------------------------------------------ grants
revoke execute on function pt_dly_list_default(text), pt_dly_list(text), pt_dly_label(text), pt_dly_merge(text, uuid, jsonb), delay_lists_set(jsonb) from public, anon, authenticated;
grant execute on function delay_lists_set(jsonb) to authenticated;
