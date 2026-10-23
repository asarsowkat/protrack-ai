-- ProTrack schema update v38 (ProTrackAI v3.34): emails are really sent, and only to the right people.
-- Until now the app prepared each email in the browser (who receives it, subject and body) and handed it to a server
-- function that was never installed, so nothing was sent; and had it been installed, anyone signed in could have used it
-- to send any text to any address. From this update:
-- 1. mail_outbox: one row per email: what it is about (a daily report, an internal or cost report, a Reporting status
--    reminder, or a test), the subject and body the app prepared, the recipients THE SERVER worked out, and its status
--    (queued, sending, sent, failed), the attempts and the error. Read by the person who queued it and by super admins;
--    nobody writes it directly.
-- 2. mail_queue(p): the only way in. The server checks that the event is real and that the caller made it, and works out
--    the recipients itself:
--      dpr      the daily report is Approved and the caller approved it (or is a super admin); everyone active in the
--               roles of the approval email settings (mail_config) who has access to the project; with "site roles only
--               for their own reports" (chain_only), site engineers and site managers only if they reviewed or approved it;
--      release  the internal or cost report is Released and the caller approved it (or is a super admin); the report
--               email list of the region (internal reports) or the default list (report_mail_lists): its roles with
--               access to the project, its named people and its other addresses; a weekly internal report only when the
--               list says weekly too;
--      remind   a Reporting status reminder the caller sent in the last hour (rs_reminders): the people it named who
--               still have access to the project;
--      test     a super admin's test email, to themselves.
--    The same event is queued once: asking again returns the email already queued.
-- 3. mail_retry(p): a super admin puts a failed email back in the queue.
-- 4. The Edge Function send-mail (supabase/functions/send-mail) sends a queued email through the company mailbox
--    (Microsoft Graph) or an SMTP relay, with the service key, and records the result. Without it emails stay queued and
--    are listed in Settings -> Email.
-- 5. mail_features() tells the app this update is in.
-- Needs schema-update-v16.sql (user_sees with region access), v23 (report_mail_lists) and v29 (rs_reminders) for those
-- kinds; each kind is refused with a clear message when its update is missing. Additive. Safe to run twice.
-- Undo: schema-rollback-v38.sql.

create table if not exists mail_outbox (
  id uuid primary key default uuid_generate_v4(),
  kind text not null check (kind in ('dpr','release','remind','test')),
  ref text not null,                                       -- the daily report, release or reminder id; 'test-<uuid>' for a test
  project_id text references projects(id) on delete set null,
  label text,                                              -- shown in the outbox: "DPR-0012", "Monthly cost report PE-001 Sep 2026"
  subject text not null check (length(subject) between 1 and 300),
  html text not null check (length(html) <= 400000),
  recipients jsonb not null default '[]'::jsonb,           -- [{id, name, email, role}] as the server worked them out
  status text not null default 'queued' check (status in ('queued','sending','sent','failed')),
  attempts int not null default 0,
  error text,
  provider text, provider_ref text,
  queued_by uuid references profiles(id), queued_at timestamptz not null default now(),
  sent_at timestamptz, updated_at timestamptz not null default now());
create unique index if not exists mail_outbox_once on mail_outbox (kind, ref);
create index if not exists mail_outbox_recent on mail_outbox (queued_at desc);
alter table mail_outbox enable row level security;
drop policy if exists mail_outbox_read on mail_outbox;
create policy mail_outbox_read on mail_outbox for select using (queued_by = auth.uid() or my_role()::text = 'sa');
revoke insert, update, delete on mail_outbox from authenticated, anon;

-- a person's address, from the sign-in accounts
create or replace function pt_mail_addr(u uuid) returns text
language sql stable security definer set search_path = public, auth as $$
  select nullif(btrim(email), '') from auth.users where id = u $$;
revoke execute on function pt_mail_addr(uuid) from public, authenticated, anon;

create or replace function pt_mail_person(u uuid) returns jsonb
language sql stable security definer set search_path = public, auth as $$
  select jsonb_build_object('id', p.id, 'name', p.name, 'email', pt_mail_addr(p.id), 'role', p.role::text)
    from profiles p where p.id = u and p.active and pt_mail_addr(p.id) is not null $$;
revoke execute on function pt_mail_person(uuid) from public, authenticated, anon;

create or replace function mail_queue(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare me uuid := auth.uid(); r text := role_of(auth.uid()); k text := p ->> 'kind'; v_ref text := btrim(coalesce(p ->> 'ref', ''));
        subj text := btrim(coalesce(p ->> 'subject', '')); body text := coalesce(p ->> 'html', '');
        pid text; lbl text := left(btrim(coalesce(p ->> 'label', '')), 200); rc jsonb := '[]'::jsonb; cur mail_outbox;
        d dprs; mc mail_config; rel report_releases; reg text; lst record; rem record; x jsonb; e text;
begin
  if me is null or r is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if k is null or k not in ('dpr','release','remind','test') then raise exception 'Unknown email type %', coalesce(k, ''); end if;
  if subj = '' or length(subj) > 300 then raise exception 'The subject is missing or longer than 300 characters'; end if;
  if body = '' or length(body) > 400000 then raise exception 'The email body is missing or too long'; end if;
  if k = 'test' then
    if r <> 'sa' then raise exception 'Only a super admin sends a test email' using errcode = '42501'; end if;
    v_ref := 'test-' || uuid_generate_v4()::text;
  elsif v_ref = '' then raise exception 'Say which report the email is about'; end if;


  if k = 'dpr' then
    select * into d from dprs where id = v_ref;
    if d.id is null then raise exception 'Unknown daily report %', v_ref; end if;
    if d.status::text <> 'Approved' then raise exception 'Daily report % is not approved', v_ref; end if;
    if r <> 'sa' and not exists (select 1 from dpr_audit a where a.dpr_id = d.id and a.action = 'Approved' and a.by_user = me) then
      raise exception 'Only the person who approved daily report % sends its email', v_ref using errcode = '42501'; end if;
    select * into mc from mail_config where id = 1;
    if mc.id is null or not mc.enabled then return jsonb_build_object('id', null, 'n', 0, 'skipped', 'Approval email is switched off'); end if;
    pid := d.project_id; lbl := coalesce(nullif(lbl, ''), d.id);
    select coalesce(jsonb_agg(pt_mail_person(u.id) order by u.name), '[]'::jsonb) into rc
      from profiles u
     where u.active and u.role::text = any(mc.roles) and pt_mail_addr(u.id) is not null and user_sees(u.id, pid)
       and (not mc.chain_only or u.role::text not in ('eng','sm')
            or exists (select 1 from dpr_audit a where a.dpr_id = d.id and a.action in ('Reviewed','Approved') and a.by_user = u.id));

  elsif k = 'release' then
    if to_regclass('public.report_mail_lists') is null then raise exception 'Report emails need the v23 database update (STAGE-19-SETUP)'; end if;
    begin select * into rel from report_releases where id = v_ref::uuid; exception when invalid_text_representation then raise exception 'Unknown report %', v_ref; end;
    if rel.id is null then raise exception 'Unknown report %', v_ref; end if;
    if rel.status <> 'Released' then raise exception 'This report is not released'; end if;
    if rel.kind not in ('planning','cost') then raise exception 'Only internal and cost reports are emailed'; end if;
    if r <> 'sa' and rel.approved_by is distinct from me then
      raise exception 'Only the person who approved this report sends its email' using errcode = '42501'; end if;
    pid := rel.project_id; select region into reg from projects where id = pid;
    select * into lst from report_mail_lists l where l.kind = rel.kind and l.region_id = reg and rel.kind = 'planning';
    if lst.id is null then select * into lst from report_mail_lists l where l.kind = rel.kind and l.region_id is null; end if;
    if lst.id is null or not lst.enabled then return jsonb_build_object('id', null, 'n', 0, 'skipped', 'Report emails are switched off for this report'); end if;
    if rel.kind = 'planning' and rel.period_type = 'week' and not lst.weekly then
      return jsonb_build_object('id', null, 'n', 0, 'skipped', 'Weekly internal reports are not emailed'); end if;
    select coalesce(jsonb_agg(pt_mail_person(u.id) order by u.name), '[]'::jsonb) into rc
      from profiles u
     where u.active and pt_mail_addr(u.id) is not null
       and ((u.role::text = any(lst.roles) and user_sees(u.id, pid)) or u.id = any(lst.people));
    foreach e in array coalesce(lst.extra, '{}') loop
      e := lower(btrim(e));
      if e ~ '^[^\s@,;]+@[^\s@,;]+\.[^\s@,;]+$' and not exists (select 1 from jsonb_array_elements(rc) y where lower(y ->> 'email') = e) then
        rc := rc || jsonb_build_array(jsonb_build_object('id', null, 'name', e, 'email', e, 'role', 'other')); end if;
    end loop;

  elsif k = 'remind' then
    if to_regclass('public.rs_reminders') is null then raise exception 'Reminders need the v29 database update (STAGE-25-SETUP)'; end if;
    select * into rem from rs_reminders where id = v_ref;
    if rem.id is null then raise exception 'Unknown reminder %', v_ref; end if;
    if rem.by_user is distinct from me then raise exception 'Only the person who sent this reminder emails it' using errcode = '42501'; end if;
    if rem.at < now() - interval '1 hour' then raise exception 'This reminder is more than an hour old; send a new one'; end if;
    pid := rem.project_id;
    for x in select * from jsonb_array_elements(coalesce(rem."to", '[]'::jsonb)) loop
      if (x ->> 'id') ~ '^[0-9a-f-]{36}$' and user_sees((x ->> 'id')::uuid, pid) and pt_mail_person((x ->> 'id')::uuid) is not null then
        rc := rc || jsonb_build_array(pt_mail_person((x ->> 'id')::uuid)); end if;
    end loop;

  else
    rc := coalesce(jsonb_build_array(pt_mail_person(me)), '[]'::jsonb);
    if jsonb_array_length(rc) = 0 or rc = '[null]'::jsonb then raise exception 'Your account has no email address'; end if;
    lbl := 'Test email';
  end if;

  -- the same event is queued once (checked after the caller is known to have made it)
  select * into cur from mail_outbox where kind = k and mail_outbox.ref = v_ref;
  if cur.id is not null then
    return jsonb_build_object('id', cur.id, 'status', cur.status, 'n', jsonb_array_length(cur.recipients), 'to', cur.recipients, 'duplicate', true); end if;
  rc := coalesce((select jsonb_agg(y) from jsonb_array_elements(rc) y where y <> 'null'::jsonb), '[]'::jsonb);
  if jsonb_array_length(rc) = 0 then return jsonb_build_object('id', null, 'n', 0, 'skipped', 'Nobody on the list has access and an email address'); end if;
  insert into mail_outbox (kind, ref, project_id, label, subject, html, recipients, queued_by)
  values (k, v_ref, pid, nullif(lbl, ''), subj, body, rc, me)
  on conflict (kind, ref) do nothing returning * into cur;
  if cur.id is null then select * into cur from mail_outbox where kind = k and mail_outbox.ref = v_ref; end if;
  return jsonb_build_object('id', cur.id, 'status', cur.status, 'n', jsonb_array_length(cur.recipients), 'to', cur.recipients);
end $$;

-- a super admin puts a failed email back in the queue
create or replace function mail_retry(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); cur mail_outbox;
begin
  if role_of(me) is distinct from 'sa' then raise exception 'Only a super admin sends an email again' using errcode = '42501'; end if;
  select * into cur from mail_outbox where id = (p ->> 'id')::uuid for update;
  if cur.id is null then raise exception 'Unknown email'; end if;
  if cur.status = 'sent' then raise exception 'This email was sent already'; end if;
  update mail_outbox set status = 'queued', error = null, updated_at = now() where id = cur.id returning * into cur;
  return jsonb_build_object('id', cur.id, 'status', cur.status);
end $$;

create or replace function mail_features() returns jsonb language sql immutable as $$ select '{"version": 38, "queue": true}'::jsonb $$;

revoke execute on function mail_queue(jsonb), mail_retry(jsonb) from public, anon;
grant execute on function mail_queue(jsonb), mail_retry(jsonb), mail_features() to authenticated;
