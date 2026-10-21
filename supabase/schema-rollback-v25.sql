-- ProTrack schema rollback v25: back to the v3.19 delay events register on the server (schema-update-v24.sql).
-- delay_lists_set is removed, so nobody can change the lists, and delay_act / delay_import accept any value in the
-- seven drop-down columns again (pt_dly_merge and pt_dly_label as in v24).
-- Everything is kept: delay_lists with the lists as last set, and delay_list_audit with every change. Run
-- schema-update-v25.sql again to use them again. To remove them as well (not undoable), run separately:
-- drop table delay_list_audit; drop table delay_lists;
-- Safe to run twice.

drop function if exists delay_lists_set(jsonb);

-- pt_dly_label and pt_dly_merge: as in schema-update-v24.sql
create or replace function pt_dly_label(k text) returns text language sql immutable as $$
  select case k when 'start_date' then 'Claim event start date' when 'closed_on' then 'Claim event closing date (if closed)'
    when 'notice_date' then 'Notice of claim submission date' when 'data_date' then 'Claim data date'
    when 'prolong_cost' then 'Prolongation cost impact (SAR, if calculated)' when 'vo_omit' then 'Variation orders cost, omission (SAR, if calculated)'
    when 'vo_add' then 'Variation orders cost, added (SAR, if calculated)' else k end $$;

create or replace function pt_dly_merge(pid text, eid uuid, f jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare m jsonb := '{}'::jsonb; k text; v text; n numeric; today date := current_date;
begin
  if eid is not null then select to_jsonb(e) into m from delay_events e where id = eid; end if;
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

drop function if exists pt_dly_list(text);
drop function if exists pt_dly_list_default(text);

create or replace function delay_features() returns jsonb language sql immutable as $$
  select '{"version":24,"delay_register":true}'::jsonb $$;
revoke execute on function pt_dly_label(text), pt_dly_merge(text, uuid, jsonb), delay_features() from public, anon, authenticated;
grant execute on function delay_features() to authenticated;
