-- ProTrack schema update v26 (ProTrackAI v3.19.2): correspondence and letters of a delay event.
-- 1. delay_corr keeps the letters, e-mails, notices, instructions and minutes behind each delay event: type, direction
--    (received from the Employer / Engineer, sent by alfanar, internal), date, reference, subject, from, to, notes, and
--    the file when there is one, as the app's delayCorrActLocal(). Files are kept in a new private storage bucket,
--    "delay-docs", at <project>/<event>/<id>/<file name>, up to 50 MB, the document rack's file types.
-- 2. Who reads: the people who read the register (cost-figure viewers, on the projects in their access). Who records:
--    the people who keep it (pt_dly_keeper: right delay.keep on the project). The same for the files.
-- 3. delay_corr_act(p) adds a record (with the file already uploaded) or removes one. Removing needs a reason; the record
--    stays (removed_at), and so does its file. A record can add its reference to the event, as the app's dlyCorrLink():
--    received -> Supporting documents ref.; sent -> Notice of claim documents ref.; a sent notice of claim also sets
--    the notice submission date when the event has none. That change goes through pt_dly_write, with the event's rules.
-- 4. An event that has letters cannot be deleted until they are removed.
-- Needs schema-update-v24.sql (STAGE-20-SETUP). v25 is not needed first. Additive: one table, one bucket, new
-- functions, one trigger. Safe to run twice. Undo: schema-rollback-v26.sql.

do $$ begin
  if to_regprocedure('public.pt_dly_write(text,uuid,jsonb,text,text)') is null or to_regclass('public.delay_events') is null then
    raise exception 'Run schema-update-v24.sql (STAGE-20-SETUP) first, then this update'; end if;
end $$;

-- ------------------------------------------------------------------ 1. the records and the bucket
create table if not exists delay_corr (
  id uuid primary key default uuid_generate_v4(),
  event_id uuid not null,   -- no foreign key: an event with letters is not deleted (trigger below)
  project_id text not null references projects(id) on delete cascade,
  kind text not null check (kind in ('Letter','E-mail','Notice of claim','Site instruction','Minutes of meeting','Variation order / instruction',
                                     'Request for information','Drawing / submittal','Photo / site record','Progress report','Other')),
  direction text not null check (direction in ('in','out','int')),
  corr_date date not null,
  ref_no text, subject text not null, from_party text, to_party text, notes text,
  storage_path text unique, file_name text, file_size bigint, mime text, sha256 text,
  created_by uuid references profiles(id), created_at timestamptz not null default now(),
  removed_at timestamptz, removed_by uuid references profiles(id), remove_note text);
create index if not exists delay_corr_event on delay_corr (event_id, corr_date);

alter table delay_corr enable row level security;
drop policy if exists dc_read on delay_corr;
create policy dc_read on delay_corr for select using (can_see(project_id) and pt_money_ok());
revoke all on delay_corr from anon;
revoke insert, update, delete, truncate on delay_corr from authenticated;
grant select on delay_corr to authenticated;

insert into storage.buckets (id, name, public, file_size_limit)
values ('delay-docs', 'delay-docs', false, 52428800)
on conflict (id) do update set public = false, file_size_limit = 52428800;

-- path: <project>/<event>/<id>/<file name>; reading as the register, adding as its keepers; no rule changes or deletes a file
create or replace function pt_dly_file_can(u uuid, path text, w boolean) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(exists (select 1 from delay_events where id::text = split_part(path, '/', 2) and project_id = split_part(path, '/', 1))
    and case when w then pt_dly_keeper(u, split_part(path, '/', 1))
             else user_sees(u, split_part(path, '/', 1)) and pt_right(u, 'money.view') end, false) $$;
drop policy if exists protrack_delay_docs_read on storage.objects;
create policy protrack_delay_docs_read on storage.objects for select to authenticated
  using (bucket_id = 'delay-docs' and public.pt_dly_file_can(auth.uid(), name, false));
drop policy if exists protrack_delay_docs_add on storage.objects;
create policy protrack_delay_docs_add on storage.objects for insert to authenticated
  with check (bucket_id = 'delay-docs' and array_length(string_to_array(name, '/'), 1) = 4
              and name ~* '\.(pdf|docx?|xlsx?|xlsm|xlsb|csv|pptx?|xer|xml|mpp|zip|png|jpe?g|gif|webp|tiff?|txt|msg|eml|dwg|dxf)$'
              and public.pt_dly_file_can(auth.uid(), name, true));

-- an event that has letters is not deleted
create or replace function pt_dly_corr_guard() returns trigger language plpgsql as $$
begin
  if exists (select 1 from delay_corr where event_id = old.id and removed_at is null) then
    raise exception 'Remove this event''s correspondence and letters first, then delete it'; end if;
  return old;
end $$;
drop trigger if exists trg_dly_corr_guard on delay_events;
create trigger trg_dly_corr_guard before delete on delay_events for each row execute function pt_dly_corr_guard();

-- ------------------------------------------------------------------ 2. adding and removing
-- what a record adds to its event (the app's dlyCorrLink)
create or replace function pt_dly_corr_link(e delay_events, c delay_corr) returns jsonb language plpgsql stable as $$
declare f jsonb := '{}'::jsonb; line text := coalesce(c.ref_no, c.subject) || ' (' || c.corr_date::text || ')'; k text; cur text;
begin
  foreach k in array case c.direction when 'in' then array['support_docs'] when 'out' then array['notice_docs'] else array[]::text[] end loop
    cur := coalesce(case k when 'support_docs' then e.support_docs else e.notice_docs end, '');
    if (c.ref_no is not null and position(lower(c.ref_no) in lower(cur)) > 0) or position(lower(line) in lower(cur)) > 0 then continue; end if;
    f := f || jsonb_build_object(k, left(concat_ws(E'\n', nullif(btrim(cur), ''), line), 4000));
  end loop;
  if c.direction = 'out' and c.kind = 'Notice of claim' and e.notice_date is null then f := f || jsonb_build_object('notice_date', c.corr_date::text); end if;
  return f;
end $$;

-- p: {action: 'add', event_id, kind, direction, corr_date, ref_no, subject, from_party, to_party, notes, link,
--     storage_path?, file_name?, sha256?} | {action: 'remove', id, note}
create or replace function delay_corr_act(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); a text := p ->> 'action'; e delay_events; c delay_corr; f jsonb; x text; sz bigint; mt text;
        note text := nullif(btrim(coalesce(p ->> 'note', '')), ''); err text;
        s_ref text := nullif(left(btrim(regexp_replace(coalesce(p ->> 'ref_no', ''), '\s+', ' ', 'g')), 120), '');
        s_subj text := left(btrim(regexp_replace(coalesce(p ->> 'subject', ''), '\s+', ' ', 'g')), 300);
begin
  if me is null or role_of(me) is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if a is null or a not in ('add','remove') then raise exception 'Unknown action %', coalesce(a, ''); end if;
  if a = 'remove' then
    select * into c from delay_corr where id = nullif(p ->> 'id', '')::uuid for update;
    if not found then raise exception 'Unknown record'; end if;
    select * into e from delay_events where id = c.event_id;
  else
    select * into e from delay_events where id = nullif(p ->> 'event_id', '')::uuid;
  end if;
  if e.id is null then raise exception 'Unknown delay event'; end if;
  if not user_sees(me, e.project_id) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
  if not pt_dly_keeper(me, e.project_id) then
    raise exception 'Only the planning engineers of this project, the Head of Planning and Cost Control or a super admin can change its delay events register' using errcode = '42501'; end if;

  if a = 'remove' then
    if c.removed_at is not null then raise exception 'This record is already removed'; end if;
    if note is null then raise exception 'Say why this record is removed'; end if;
    update delay_corr set removed_at = now(), removed_by = me, remove_note = left(note, 1000) where id = c.id returning * into c;
    insert into delay_audit (event_id, project_id, event_no, action, note, detail, by_user, by_name, by_role)
    values (e.id, e.project_id, e.event_no, 'Correspondence removed', note, jsonb_build_object('record', c.id, 'ref', c.ref_no, 'subject', c.subject), me, name_of(me), role_of(me));
    return to_jsonb(c);
  end if;

  if coalesce(p ->> 'kind', '') not in ('Letter','E-mail','Notice of claim','Site instruction','Minutes of meeting','Variation order / instruction',
                                        'Request for information','Drawing / submittal','Photo / site record','Progress report','Other') then
    raise exception 'Choose the type of correspondence'; end if;
  if coalesce(p ->> 'direction', '') not in ('in','out','int') then raise exception 'Choose whether it was received, sent or internal'; end if;
  if coalesce(p ->> 'corr_date', '') !~ '^\d{4}-\d{2}-\d{2}$' or pt_date(p ->> 'corr_date') is null then raise exception 'Enter the date of the letter'; end if;
  if (p ->> 'corr_date')::date > current_date then raise exception 'The date of the letter cannot be in the future'; end if;
  if s_subj = '' then raise exception 'Enter the subject of the letter'; end if;
  x := nullif(p ->> 'storage_path', '');
  if x is not null then
    if split_part(x, '/', 1) <> e.project_id or split_part(x, '/', 2) <> e.id::text or array_length(string_to_array(x, '/'), 1) <> 4 then
      raise exception 'The file is not in this event''s folder'; end if;
    select (metadata ->> 'size')::bigint, metadata ->> 'mimetype' into sz, mt from storage.objects where bucket_id = 'delay-docs' and name = x;
    if not found then raise exception 'The file was not found in storage; upload it again'; end if;
    if nullif(p ->> 'sha256', '') is not null and exists (select 1 from delay_corr where event_id = e.id and removed_at is null and sha256 = p ->> 'sha256') then
      raise exception 'This file is already attached to this event'; end if;
  end if;
  c := row(uuid_generate_v4(), e.id, e.project_id, p ->> 'kind', p ->> 'direction', (p ->> 'corr_date')::date, s_ref, s_subj,
           nullif(left(btrim(regexp_replace(coalesce(p ->> 'from_party', ''), '\s+', ' ', 'g')), 120), ''),
           nullif(left(btrim(regexp_replace(coalesce(p ->> 'to_party', ''), '\s+', ' ', 'g')), 120), ''),
           nullif(left(btrim(coalesce(p ->> 'notes', '')), 2000), ''),
           x, case when x is not null then left(coalesce(nullif(p ->> 'file_name', ''), split_part(x, '/', 4)), 200) end, sz, mt,
           case when x is not null then nullif(p ->> 'sha256', '') end, me, now(), null, null, null)::delay_corr;
  f := case when coalesce((p ->> 'link')::boolean, false) then pt_dly_corr_link(e, c) else '{}'::jsonb end;
  if f <> '{}'::jsonb then
    begin perform pt_dly_merge(e.project_id, e.id, f);
    exception when others then err := sqlerrm; end;
    if err is not null then raise exception '% (untick "Add its reference to the register" to record the letter only)', err; end if;
  end if;
  insert into delay_corr select (c).*;
  insert into delay_audit (event_id, project_id, event_no, action, note, detail, by_user, by_name, by_role)
  values (e.id, e.project_id, e.event_no, 'Correspondence added', null,
          jsonb_build_object('record', c.id, 'kind', c.kind, 'direction', c.direction, 'ref', c.ref_no, 'file', c.file_name), me, name_of(me), role_of(me));
  if f <> '{}'::jsonb then perform pt_dly_write(e.project_id, e.id, f, 'From correspondence ' || coalesce(c.ref_no, c.subject), 'correspondence'); end if;
  return to_jsonb(c);
end $$;

-- the app asks this to know v26 is in (schema-rollback-v26.sql removes it)
create or replace function delay_corr_features() returns jsonb language sql immutable as $$
  select '{"version":26,"delay_correspondence":true}'::jsonb $$;

-- ------------------------------------------------------------------ grants
revoke execute on function pt_dly_corr_link(delay_events, delay_corr), delay_corr_act(jsonb), delay_corr_features(), pt_dly_file_can(uuid, text, boolean) from public, anon;
revoke execute on function pt_dly_corr_link(delay_events, delay_corr) from authenticated;
grant execute on function delay_corr_act(jsonb), delay_corr_features(), pt_dly_file_can(uuid, text, boolean) to authenticated;
