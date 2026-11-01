-- ProTrack schema update v53 (ProTrackAI v3.50): client invoice formats for the Client Invoice Builder.
-- 1. cib_formats: a client's own invoice workbook (its file in the private bucket cib-formats at fmt/<id>.xlsx, at most 25 MB)
--    and the map ProTrack reads from it (the breakdown tables, header cells, TCC and FAC cells, the forecast; no figures of the
--    sample). Read by everyone who sees billing figures (money.view, not foremen); kept by those with cib.setup through
--    cib_fmt_act(p): fmt_add (after the file is stored), fmt_map (name, client, map), fmt_del (then the browser removes the file,
--    which storage allows only once no format refers to it). The format's history is kept on the row.
-- 2. cib_act: inv_export notes in the audit trail that an invoice was exported, and in which format. cib_features: version 53.
-- 3. A fix: the read rule of report-media (v47) called user_sees(), which signed-in people may not run, so with v47 installed no
--    stored file could be read from any bucket; it now calls pt_rm_see().
-- The browser fills the workbook itself (only the cells of the map change) and checks the format's own totals against the
-- invoice the server worked out; the server never runs the workbook.
-- Needs schema-update-v52.sql. Additive. Safe to run twice. Undo: schema-rollback-v53.sql.

do $$ begin
  if to_regprocedure('public.cib_features()') is null or coalesce((cib_features() ->> 'version')::int, 0) < 52 then
    raise exception 'Run schema-update-v52.sql (STAGE-46-SETUP) first, then this update'; end if;
end $$;

-- ------------------------------------------------------------------ 1. who sees and keeps the formats
create or replace function pt_cib_fmt_see(u uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) is not null and role_of(u) <> 'foreman' and pt_right(u, 'money.view', false), false) $$;
create or replace function pt_cib_fmt_keep(u uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(pt_cib_fmt_see(u) and pt_right(u, 'cib.setup', false), false) $$;

-- ------------------------------------------------------------------ 2. the formats and their files
create table if not exists cib_formats (
  id text primary key check (id ~ '^CF[a-z0-9]{6,40}$'),
  name text not null check (length(btrim(name)) between 2 and 80),
  client text check (client is null or length(btrim(client)) between 1 and 200),
  file_path text not null unique check (file_path ~ '^fmt/CF[a-z0-9]{6,40}\.xlsx$'),
  file_name text not null check (length(file_name) between 1 and 200),
  file_size bigint not null check (file_size between 1 and 26214400),
  file_hash text check (file_hash is null or file_hash ~ '^[0-9a-f]{64}$'),
  map jsonb not null check (jsonb_typeof(map) = 'object'),
  hist jsonb not null default '[]'::jsonb check (jsonb_typeof(hist) = 'array'),
  created_by uuid, created_name text, created_at timestamptz not null default now(),
  updated_by uuid, updated_name text, updated_at timestamptz not null default now());
create unique index if not exists cib_formats_name on cib_formats (lower(btrim(name)), lower(coalesce(btrim(client), '')));
alter table cib_formats enable row level security;
drop policy if exists cib_f_read on cib_formats; create policy cib_f_read on cib_formats for select to authenticated using (pt_cib_fmt_see(auth.uid()));
revoke all on cib_formats from anon;
revoke insert, update, delete, truncate on cib_formats from authenticated;
grant select on cib_formats to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('cib-formats', 'cib-formats', false, 26214400, array['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists protrack_cf_read on storage.objects;
create policy protrack_cf_read on storage.objects for select to authenticated
  using (bucket_id = 'cib-formats' and public.pt_cib_fmt_see(auth.uid()));
drop policy if exists protrack_cf_add on storage.objects;
create policy protrack_cf_add on storage.objects for insert to authenticated
  with check (bucket_id = 'cib-formats' and name ~ '^fmt/CF[a-z0-9]{6,40}\.xlsx$' and public.pt_cib_fmt_keep(auth.uid()));
drop policy if exists protrack_cf_del on storage.objects;
create policy protrack_cf_del on storage.objects for delete to authenticated
  using (bucket_id = 'cib-formats' and public.pt_cib_fmt_keep(auth.uid()) and not exists (select 1 from public.cib_formats f where f.file_path = objects.name));

-- ------------------------------------------------------------------ 3. a fix: reading files in storage
-- The read rule of report-media (v47) called user_sees(), which signed-in people may not run. PostgreSQL checks that right for
-- every read rule of storage.objects, so no file could be read from any bucket. The rule now calls pt_rm_see(), which they may
-- run (it answers only for the person asking).
create or replace function pt_rm_see(u uuid, pid text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(u = auth.uid() and user_sees(u, pid), false) $$;
revoke execute on function pt_rm_see(uuid, text) from public, anon;
grant execute on function pt_rm_see(uuid, text) to authenticated;
drop policy if exists protrack_rm_read on storage.objects;
create policy protrack_rm_read on storage.objects for select to authenticated
  using (bucket_id = 'report-media' and public.pt_rm_see(auth.uid(), split_part(name, '/', 1)));

-- ------------------------------------------------------------------ 4. keeping a format
create or replace function cib_fmt_act(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); op text := p ->> 'op'; fid text := p ->> 'id'; nm text := btrim(coalesce(p ->> 'name', '')); cl text := nullif(btrim(coalesce(p ->> 'client', '')), '');
  m jsonb := p -> 'map'; f record; pth text; sz bigint;
begin
  if me is null or role_of(me) is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if not pt_cib_fmt_keep(me) then raise exception 'Only those who keep the Schedule-C keep the invoice formats' using errcode = '42501'; end if;
  if op in ('fmt_add', 'fmt_map') then
    if length(nm) not between 2 and 80 then raise exception 'Give the format a name (2 to 80 characters)'; end if;
    if cl is not null and length(cl) > 200 then raise exception 'The client name is too long'; end if;
    if jsonb_typeof(m) is distinct from 'object' or jsonb_typeof(m -> 'sheets') is distinct from 'array' or jsonb_typeof(m -> 'tables') is distinct from 'array' or jsonb_typeof(m -> 'fields') is distinct from 'array' then
      raise exception 'The format map is not valid'; end if;
    if pg_column_size(m) > 2000000 then raise exception 'The format map is too large'; end if;
    if exists (select 1 from cib_formats x where lower(btrim(x.name)) = lower(nm) and lower(coalesce(btrim(x.client), '')) = lower(coalesce(cl, '')) and x.id is distinct from fid) then
      raise exception 'A format with this name is already kept for this client'; end if;
  end if;
  if op = 'fmt_add' then
    if fid is null or fid !~ '^CF[a-z0-9]{6,40}$' then raise exception 'Unknown format'; end if;
    pth := 'fmt/' || fid || '.xlsx';
    if p ->> 'path' is distinct from pth then raise exception 'The workbook path is not valid'; end if;
    if not exists (select 1 from storage.objects where bucket_id = 'cib-formats' and name = pth) then raise exception 'The workbook was not stored'; end if;
    if exists (select 1 from cib_formats where id = fid) then raise exception 'This format is already kept'; end if;
    sz := coalesce(pt_num(p ->> 'size'), 0)::bigint; if sz < 1 or sz > 26214400 then raise exception 'The workbook is larger than 25 MB'; end if;
    insert into cib_formats (id, name, client, file_path, file_name, file_size, file_hash, map, hist, created_by, created_name, updated_by, updated_name)
    values (fid, nm, cl, pth, left(coalesce(nullif(btrim(p ->> 'file'), ''), fid || '.xlsx'), 200), sz, case when p ->> 'hash' ~ '^[0-9a-f]{64}$' then p ->> 'hash' end, m,
      jsonb_build_array(jsonb_build_object('at', now(), 'by', name_of(me), 'act', 'Uploaded', 'note', left(p ->> 'file', 200))), me, name_of(me), me, name_of(me));
    return jsonb_build_object('id', fid);
  end if;
  select * into f from cib_formats where id = fid for update;
  if f.id is null then raise exception 'Unknown format'; end if;
  if op = 'fmt_map' then
    update cib_formats set name = nm, client = cl, map = m, updated_by = me, updated_name = name_of(me), updated_at = now(),
      hist = hist || jsonb_build_array(jsonb_build_object('at', now(), 'by', name_of(me), 'act', 'Map changed')) where id = f.id;
    return jsonb_build_object('ok', true);
  elsif op = 'fmt_del' then
    delete from cib_formats where id = f.id;
    return jsonb_build_object('ok', true, 'path', f.file_path);
  end if;
  raise exception 'Unknown action';
end $$;

-- ------------------------------------------------------------------ 5. the export noted; the version
create or replace function cib_features() returns jsonb language sql stable as $$ select jsonb_build_object('version', 53, 'llm_review', false, 'inv_weight', true, 'formats', true) $$;
create or replace function cib_act(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); op text := p ->> 'op'; pid text := p ->> 'pid'; note text := btrim(coalesce(p ->> 'note', '')); sc record; iv record; ap record; x jsonb; k text; e text; wt numeric; vi text;
  rv int; nid text; n int := 0; tot numeric; c jsonb; seqn int; pfrom date; upto date; last record; ref text; d date; b jsonb; aft jsonb; reviewer uuid; amt numeric; ch boolean := false; g numeric; pt jsonb; h jsonb;
begin
  if me is null or role_of(me) is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if pid is null or not exists (select 1 from projects where id = pid) or not user_sees(me, pid) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;
  if not pt_cib_can(me, null, pid) then raise exception 'Billing figures are not open to you' using errcode = '42501'; end if;
  k := case when op in ('sch_save','sch_head','sch_rules','sch_item','sch_discard','inv_migrate') then 'cib.setup' when op = 'sch_approve' then 'cib.approve'
    when op in ('map_save','map_review') then 'cib.map' when op in ('inv_save','inv_submit') then 'cib.prepare' when op = 'inv_review' then 'cib.review' when op = 'inv_approve' then 'cib.approve'
    when op in ('inv_certify','inv_pay') then 'cib.certify' else null end;
  if k is not null and not pt_cib_can(me, k, pid) then raise exception 'You do not have the right % for this project', k using errcode = '42501'; end if;

  if op = 'sch_save' then
    if exists (select 1 from cib_schedules where project_id = pid and status = 'Draft') then raise exception 'A draft revision is already waiting for approval: approve or replace it first'; end if;
    if jsonb_typeof(p -> 'items') <> 'array' or jsonb_array_length(p -> 'items') = 0 then raise exception 'The price schedule has no items'; end if;
    if jsonb_array_length(p -> 'items') > 6000 then raise exception 'The price schedule has more than 6,000 items'; end if;
    if exists (select 1 from jsonb_array_elements(p -> 'items') i where length(upper(regexp_replace(coalesce(i ->> 'no', ''), '\s', '', 'g'))) not between 1 and 60) then raise exception 'Every item needs a number of up to 60 characters'; end if;
    select upper(regexp_replace(i ->> 'no', '\s', '', 'g')) into e from jsonb_array_elements(p -> 'items') i group by 1 having count(*) > 1 limit 1;
    if e is not null then raise exception 'Item % appears twice', e; end if;
    if exists (select 1 from jsonb_array_elements(p -> 'items') i where coalesce(nullif(i ->> 'value', '')::numeric, 0) < 0) then raise exception 'An item value is negative'; end if;
    h := cib_head_clean(p -> 'head');
    select coalesce(max(rev), 0) + 1 into rv from cib_schedules where project_id = pid;
    x := coalesce(p -> 'rules', (select rules from cib_schedules where project_id = pid and status = 'Approved'), '{}'::jsonb);
    for c in select value from jsonb_each(x) loop e := pt_cib_rule_err('{"t":"pct","cap":100,"tcc":0,"fac":0}'::jsonb || c); if e is not null then raise exception '%', e; end if; end loop;
    nid := 'CS-' || pid || '-' || rv;
    insert into cib_schedules (id, project_id, rev, status, head, rules, file_name, file_hash, created_by, created_name) values (nid, pid, rv, 'Draft', h, x, left(p ->> 'file', 300), left(p ->> 'hash', 100), me, name_of(me));
    insert into cib_items (schedule_id, project_id, item_no, seq, data)
      select nid, pid, upper(regexp_replace(i ->> 'no', '\s', '', 'g')), o::int, (i - 'no') || jsonb_build_object('value', round(coalesce(nullif(i ->> 'value', '')::numeric, 0), 2),
        'parent', case when coalesce(i ->> 'parent', '') = '' then null else upper(regexp_replace(i ->> 'parent', '\s', '', 'g')) end,
        'limit', coalesce(nullif(i ->> 'limit', '')::numeric, 100), 'st', coalesce(nullif(i ->> 'st', ''), 'Active'), 'comp', coalesce(nullif(i ->> 'comp', ''), 'OTH'), 'leaf', coalesce((i ->> 'leaf')::boolean, true))
      from jsonb_array_elements(p -> 'items') with ordinality t(i, o);
    perform pt_cib_log(pid, 'Schedule-C uploaded', 'Revision ' || rv, null, jsonb_build_object('file', p ->> 'file', 'items', jsonb_array_length(p -> 'items'), 'value', h -> 'value'), note);
    return jsonb_build_object('id', nid, 'rev', rv, 'st', 'Draft');
  end if;
  if op in ('sch_head','sch_rules','sch_item','sch_approve','sch_discard') then
    select * into sc from cib_schedules where id = p ->> 'sch' and project_id = pid for update;
    if sc.id is null then raise exception 'Unknown revision'; end if;
    if op <> 'sch_approve' and sc.status <> 'Draft' then raise exception 'Only a draft revision changes; upload a new revision to change an approved one'; end if;
    if op = 'sch_head' then h := cib_head_clean(p -> 'head'); update cib_schedules set head = h where id = sc.id; perform pt_cib_log(pid, 'Schedule-C header changed', 'Revision ' || sc.rev, sc.head, h, note);
    elsif op = 'sch_rules' then
      for k, c in select key, value from jsonb_each(coalesce(p -> 'rules', '{}'::jsonb)) loop
        if k not in ('GEN','ENG','MAT','CON','INS','TC','CLO','OTH') then raise exception 'Unknown component %', k; end if;
        e := pt_cib_rule_err('{"t":"pct","cap":100,"tcc":0,"fac":0}'::jsonb || c); if e is not null then raise exception '%: %', k, e; end if; end loop;
      update cib_schedules set rules = p -> 'rules' where id = sc.id; perform pt_cib_log(pid, 'Invoicing rules changed', 'Revision ' || sc.rev, sc.rules, p -> 'rules', note);
    elsif op = 'sch_item' then
      select data into b from cib_items where schedule_id = sc.id and item_no = upper(regexp_replace(p ->> 'no', '\s', '', 'g')); if b is null then raise exception 'Unknown item'; end if;
      if jsonb_typeof(p -> 'rule') = 'object' then e := pt_cib_rule_err(pt_cib_rule(sc.rules, coalesce(nullif(p ->> 'comp', ''), b ->> 'comp'), p -> 'rule')); if e is not null then raise exception '%', e; end if; end if;
      if coalesce(nullif(p ->> 'limit', '')::numeric, 100) <= 0 or coalesce(nullif(p ->> 'limit', '')::numeric, 100) > 100 then raise exception 'The invoice limit is more than 0%% and at most 100%%'; end if;
      if coalesce(p ->> 'comp', '') <> '' and p ->> 'comp' not in ('GEN','ENG','MAT','CON','INS','TC','CLO','OTH') then raise exception 'Unknown component'; end if;
      aft := b || jsonb_build_object('rule', case when jsonb_typeof(p -> 'rule') = 'object' then p -> 'rule' else 'null'::jsonb end, 'limit', coalesce(nullif(p ->> 'limit', '')::numeric, 100), 'comp', coalesce(nullif(p ->> 'comp', ''), b ->> 'comp'));
      update cib_items set data = aft where schedule_id = sc.id and item_no = upper(regexp_replace(p ->> 'no', '\s', '', 'g'));
      perform pt_cib_log(pid, 'Item rule changed', p ->> 'no', jsonb_build_object('rule', b -> 'rule', 'limit', b -> 'limit', 'comp', b -> 'comp'), jsonb_build_object('rule', aft -> 'rule', 'limit', aft -> 'limit', 'comp', aft -> 'comp'), note);
    elsif op = 'sch_approve' then
      if sc.status <> 'Draft' then raise exception 'Only a draft revision is approved'; end if;
      if sc.created_by = me and role_of(me) <> 'sa' then raise exception 'Nobody approves a revision they uploaded'; end if;
      select coalesce(sum((data ->> 'value')::numeric), 0) into tot from cib_items where schedule_id = sc.id and (data ->> 'leaf')::boolean and data ->> 'st' = 'Active';
      if abs(tot - (sc.head ->> 'value')::numeric) > greatest(1, (sc.head ->> 'value')::numeric * 0.005) and note = '' then raise exception 'The items do not add up to the approved value: give the reason to approve it'; end if;
      for c in select value from jsonb_each(sc.rules) loop e := pt_cib_rule_err('{"t":"pct","cap":100,"tcc":0,"fac":0}'::jsonb || c); if e is not null then raise exception '%', e; end if; end loop;
      update cib_schedules set status = 'Superseded' where project_id = pid and status = 'Approved';
      update cib_schedules set status = 'Approved', approved_by = me, approved_name = name_of(me), approved_at = now() where id = sc.id;
      perform pt_cib_log(pid, 'Schedule-C approved', 'Revision ' || sc.rev, null, jsonb_build_object('value', sc.head -> 'value'), note);
    else delete from cib_schedules where id = sc.id; perform pt_cib_log(pid, 'Draft revision discarded', 'Revision ' || sc.rev, null, null, note); end if;
    return jsonb_build_object('ok', true, 'id', sc.id);
  end if;

  if op = 'map_save' then
    select * into sc from cib_schedules where project_id = pid and status <> 'Superseded' order by rev desc limit 1;
    b := '{}'::jsonb; aft := '{}'::jsonb;
    for x in select value from jsonb_array_elements(coalesce(p -> 'rows', '[]'::jsonb)) loop
      e := btrim(coalesce(x ->> 'act', '')); if e = '' or length(e) > 60 then raise exception 'Every activity needs an ID'; end if;
      k := nullif(upper(regexp_replace(coalesce(x ->> 'item', ''), '\s', '', 'g')), '');
      if k is not null and x ->> 'src' = 'manual' and not exists (select 1 from cib_items where schedule_id = sc.id and item_no = k) then raise exception 'Item % is not in the price schedule', k; end if;
      wt := case when x ->> 'src' = 'manual' then null else nullif(greatest(coalesce(pt_num(x ->> 'w'), 0), 0), 0) end;
      vi := case when x ->> 'src' = 'manual' then null when x ->> 'via' = 'wbs' then 'wbs' else 'code' end;
      if exists (select 1 from cib_maps where project_id = pid and act_id = e and item_no is not distinct from k and src = case when x ->> 'src' = 'manual' then 'manual' else 'p6' end
        and w is not distinct from wt and via is not distinct from vi) then continue; end if;
      b := b || jsonb_build_object(e, (select item_no from cib_maps where project_id = pid and act_id = e)); aft := aft || jsonb_build_object(e, k); n := n + 1;
      if k is null then delete from cib_maps where project_id = pid and act_id = e;
      else insert into cib_maps (project_id, act_id, item_no, act_name, src, w, via, by_user, by_name) values (pid, e, k, left(x ->> 'name', 300), case when x ->> 'src' = 'manual' then 'manual' else 'p6' end, wt, vi, me, name_of(me))
        on conflict (project_id, act_id) do update set item_no = excluded.item_no, act_name = excluded.act_name, src = excluded.src, w = excluded.w, via = excluded.via, by_user = me, by_name = name_of(me), at_time = now(); end if;
    end loop;
    if coalesce((p ->> 'replace_p6')::boolean, false) then
      for e in select act_id from cib_maps where project_id = pid and src = 'p6' and act_id not in (select btrim(z ->> 'act') from jsonb_array_elements(coalesce(p -> 'rows', '[]'::jsonb)) z) loop
        b := b || jsonb_build_object(e, (select item_no from cib_maps where project_id = pid and act_id = e)); aft := aft || jsonb_build_object(e, null); n := n + 1;
        delete from cib_maps where project_id = pid and act_id = e; end loop; end if;
    if n > 0 then perform pt_cib_log(pid, case when coalesce((p ->> 'replace_p6')::boolean, false) then 'Mapping read from P6' else 'Mapping changed' end, p ->> 'file', b, aft, note); end if;
    return jsonb_build_object('changed', n);
  end if;
  if op = 'map_review' then
    k := upper(regexp_replace(coalesce(p ->> 'item', ''), '\s', '', 'g'));
    if not exists (select 1 from cib_items i join cib_schedules s on s.id = i.schedule_id where s.project_id = pid and s.status <> 'Superseded' and i.item_no = k) then raise exception 'Unknown item'; end if;
    select to_jsonb(r) into b from cib_map_reviews r where project_id = pid and item_no = k;
    if coalesce(p ->> 'd', '') = '' then delete from cib_map_reviews where project_id = pid and item_no = k; perform pt_cib_log(pid, 'Mapping review removed', k, b, null, null); return jsonb_build_object('ok', true); end if;
    if p ->> 'd' not in ('manual','zero') then raise exception 'Unknown review'; end if;
    if length(note) < 5 then raise exception 'Give the reason (at least 5 characters)'; end if;
    if p ->> 'd' = 'manual' and (nullif(p ->> 'pct', '') is null or (p ->> 'pct')::numeric not between 0 and 100) then raise exception 'The progress is between 0%% and 100%%'; end if;
    insert into cib_map_reviews (project_id, item_no, decision, pct, note, by_user, by_name) values (pid, k, p ->> 'd', case when p ->> 'd' = 'manual' then round((p ->> 'pct')::numeric, 2) else 0 end, left(note, 500), me, name_of(me))
      on conflict (project_id, item_no) do update set decision = excluded.decision, pct = excluded.pct, note = excluded.note, by_user = me, by_name = name_of(me), at_time = now();
    perform pt_cib_log(pid, 'Mapping reviewed', k, b, jsonb_build_object('d', p ->> 'd', 'pct', p -> 'pct', 'note', note), null);
    return jsonb_build_object('ok', true);
  end if;

  if op = 'inv_save' then
    select * into ap from cib_schedules where project_id = pid and status = 'Approved'; if ap.id is null then raise exception 'Approve a Schedule-C revision first'; end if;
    if p ->> 'id' is not null then select * into iv from cib_invoices where id = p ->> 'id' and project_id = pid for update; if iv.id is null then raise exception 'Unknown invoice'; end if;
      if iv.status <> 'Draft' then raise exception 'Only a draft invoice changes'; end if; seqn := iv.seq;
    else if exists (select 1 from cib_invoices where project_id = pid and status = 'Draft') then raise exception 'A draft invoice is already open: finish or cancel it first'; end if;
      select coalesce(max(seq), 0) + 1 into seqn from cib_invoices where project_id = pid and status <> 'Cancelled'; end if;
    if coalesce(p ->> 'to', '') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'The period end is not a valid date'; end if;
    upto := (p ->> 'to')::date; if upto > current_date then raise exception 'The period end is in the future'; end if;
    select * into last from cib_invoices where project_id = pid and status <> 'Cancelled' and seq < seqn order by seq desc limit 1;
    pfrom := coalesce(nullif(p ->> 'from', '')::date, last.period_to + 1, (select start_date from projects where id = pid), upto);
    if pfrom > upto then raise exception 'The period starts after it ends'; end if;
    ref := coalesce(nullif(left(btrim(coalesce(p ->> 'ref', '')), 60), ''), pid || '-INV-' || lpad(seqn::text, 2, '0'));
    c := pt_cib_compute(pid, ap.id, seqn, pfrom, upto);
    x := jsonb_build_object('ref', ref, 'rev', ap.rev, 'su', c -> 'su', 'dd', c -> 'dd', 'lines', c -> 'lines', 'tot', c -> 'tot', 'exc', c -> 'exc');
    if p ->> 'id' is null then
      nid := 'CI-' || pid || '-' || seqn || '-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS');
      insert into cib_invoices (id, project_id, seq, status, kind, schedule_id, period_from, period_to, data, prepared_by, prepared_name, hist)
        values (nid, pid, seqn, 'Draft', 'Progress', ap.id, pfrom, upto, x || '{"docs":{}}'::jsonb, me, name_of(me), jsonb_build_array(jsonb_build_object('st', 'Draft', 'by', name_of(me), 'at', now(), 'note', 'Prepared from P6 progress')));
      perform pt_cib_log(pid, 'Invoice prepared', '#' || seqn || ' ' || ref, null, jsonb_build_object('gross_this', c #> '{tot,gross_this}', 'to', upto), null);
    else
      nid := iv.id;
      update cib_invoices set schedule_id = ap.id, period_from = pfrom, period_to = upto, updated_at = now(),
        data = (iv.data - 'ai') || x || case when iv.data ? 'ai' and jsonb_typeof(iv.data -> 'ai') = 'object' then jsonb_build_object('ai', (iv.data -> 'ai') || '{"stale":true}'::jsonb) else '{}'::jsonb end where id = iv.id;
      perform pt_cib_log(pid, 'Invoice recalculated', '#' || seqn || ' ' || ref, jsonb_build_object('gross_this', iv.data #> '{tot,gross_this}', 'to', iv.period_to), jsonb_build_object('gross_this', c #> '{tot,gross_this}', 'to', upto), null);
    end if;
    return jsonb_build_object('id', nid, 'seq', seqn, 'tot', c -> 'tot', 'exc', c -> 'exc');
  end if;
  if op = 'inv_migrate' then
    select * into ap from cib_schedules where project_id = pid and status = 'Approved'; if ap.id is null then raise exception 'Approve a Schedule-C revision first'; end if;
    if exists (select 1 from cib_invoices where project_id = pid and kind <> 'Migrated' and status <> 'Cancelled') then raise exception 'Invoices are already prepared here: the history is loaded before the first invoice'; end if;
    seqn := nullif(p ->> 'seq', '')::int; if seqn is null or seqn not between 1 and 999 then raise exception 'The invoice number is a whole number from 1 to 999'; end if;
    if exists (select 1 from cib_invoices where project_id = pid and seq >= seqn and status <> 'Cancelled') then raise exception 'Invoice #% or a later one is already recorded', seqn; end if;
    if coalesce(p ->> 'to', '') !~ '^\d{4}-\d{2}-\d{2}$' or (p ->> 'to')::date > current_date then raise exception 'The certified-to date is not valid'; end if;
    c := '[]'::jsonb; tot := 0;
    for x in select value from jsonb_array_elements(coalesce(p -> 'lines', '[]'::jsonb)) loop
      k := upper(regexp_replace(coalesce(x ->> 'no', ''), '\s', '', 'g')); select data into b from cib_items where schedule_id = ap.id and item_no = k and (data ->> 'leaf')::boolean and data ->> 'st' = 'Active';
      if b is null then raise exception 'Item % is not a billable item of the approved revision', k; end if;
      g := round(coalesce(nullif(x ->> 'cum', '')::numeric, 0), 2); if g < 0 then raise exception 'Item %: negative amount', k; end if;
      if g > (b ->> 'value')::numeric + 0.5 then raise exception 'Item %: certified to date is more than its value', k; end if;
      c := c || jsonb_build_object('no', k, 'desc', b ->> 'desc', 'comp', b ->> 'comp', 'unit', coalesce(b ->> 'unit', ''), 'qty', coalesce((b ->> 'qty')::numeric, 0), 'rate', coalesce((b ->> 'rate')::numeric, 0), 'value', (b ->> 'value')::numeric,
        'rule', pt_cib_rule(ap.rules, b ->> 'comp', case when jsonb_typeof(b -> 'rule') = 'object' then b -> 'rule' else null end) ->> 't', 'prog', null, 'src', 'history', 'acts', 0, 'cum_pay', g, 'prev_pay', 0, 'this_pay', g, 'cert_cum', g);
      tot := tot + g; end loop;
    if jsonb_array_length(c) = 0 then raise exception 'No certified amounts to load'; end if;
    if tot > (ap.head ->> 'value')::numeric + 0.5 then raise exception 'Certified to date is more than the contract value'; end if;
    if least(coalesce(nullif(p ->> 'ret_cum', '')::numeric, 0), coalesce(nullif(p ->> 'adv_cum', '')::numeric, 0), coalesce(nullif(p ->> 'rel_cum', '')::numeric, 0)) < 0 then raise exception 'Amounts are not negative'; end if;
    if coalesce(nullif(p ->> 'adv_cum', '')::numeric, 0) > (ap.head ->> 'value')::numeric * coalesce((ap.head ->> 'adv_pct')::numeric, 0) / 100 + 0.5 then raise exception 'The advance recovered is more than the advance'; end if;
    nid := 'CI-' || pid || '-' || seqn || '-H';
    insert into cib_invoices (id, project_id, seq, status, kind, schedule_id, period_from, period_to, data, prepared_by, prepared_name, hist)
      values (nid, pid, seqn, 'Certified', 'Migrated', ap.id, nullif(p ->> 'from', '')::date, (p ->> 'to')::date,
        jsonb_build_object('ref', coalesce(nullif(left(p ->> 'ref', 60), ''), 'Invoice #' || lpad(seqn::text, 2, '0')), 'rev', ap.rev, 'lines', c, 'exc', '[]'::jsonb, 'docs', '{}'::jsonb, 'file', left(p ->> 'file', 300),
          'tot', jsonb_build_object('cv', (ap.head ->> 'value')::numeric, 'gross_prev', 0, 'gross_this', round(tot, 2), 'gross_cum', round(tot, 2), 'ret_this', round(coalesce(nullif(p ->> 'ret_cum', '')::numeric, 0), 2),
            'ret_cum', round(coalesce(nullif(p ->> 'ret_cum', '')::numeric, 0), 2), 'rel_this', 0, 'rel_cum', round(coalesce(nullif(p ->> 'rel_cum', '')::numeric, 0), 2), 'rel_tcc', coalesce((p ->> 'rel_tcc')::boolean, false),
            'rel_fac', coalesce((p ->> 'rel_fac')::boolean, false), 'adv_amt', round((ap.head ->> 'value')::numeric * coalesce((ap.head ->> 'adv_pct')::numeric, 0) / 100, 2), 'adv_this', round(coalesce(nullif(p ->> 'adv_cum', '')::numeric, 0), 2),
            'adv_cum', round(coalesce(nullif(p ->> 'adv_cum', '')::numeric, 0), 2), 'net', 0, 'vat', 0, 'total', 0, 'balance', round((ap.head ->> 'value')::numeric - tot, 2), 'vat_pct', coalesce((ap.head ->> 'vat')::numeric, 0)),
          'cert', jsonb_build_object('amt', round(tot, 2), 'date', p ->> 'to', 'ref', left(p ->> 'ref', 60), 'by', name_of(me), 'changed', false)),
        me, name_of(me), jsonb_build_array(jsonb_build_object('st', 'Certified', 'by', name_of(me), 'at', now(), 'note', 'Loaded from ' || coalesce(left(p ->> 'file', 200), 'the latest client invoice'))));
    perform pt_cib_log(pid, 'Invoice history loaded', '#' || seqn, null, jsonb_build_object('file', p ->> 'file', 'items', jsonb_array_length(c), 'certified', round(tot, 2)), null);
    return jsonb_build_object('id', nid, 'seq', seqn);
  end if;

  select * into iv from cib_invoices where id = p ->> 'id' and project_id = pid for update;
  if iv.id is null then raise exception 'Unknown invoice'; end if;
  -- v53: an export of the invoice (in the ProTrackAI layout or a client format) is noted; whoever sees the project's billing figures may export
  if op = 'inv_export' then
    perform pt_cib_log(pid, 'Invoice exported', '#' || lpad(iv.seq::text, 2, '0') || ' · ' || left(coalesce(nullif(btrim(p ->> 'fmt'), ''), 'ProTrackAI layout'), 80), null,
      jsonb_build_object('fmt', left(p ->> 'fmt', 80)), left(nullif(note, ''), 500));
    return jsonb_build_object('ok', true); end if;
  select (hh ->> 'by_id')::uuid into reviewer from jsonb_array_elements(iv.hist) hh where hh ->> 'st' = 'Reviewed' order by (hh ->> 'at') desc limit 1;
  if op = 'inv_ai' then
    if not (pt_cib_can(me, 'cib.prepare', pid) or pt_cib_can(me, 'cib.review', pid) or pt_cib_can(me, 'cib.approve', pid)) then raise exception 'Only those who prepare, review or approve client invoices run the review' using errcode = '42501'; end if;
    update cib_invoices set data = data || jsonb_build_object('ai', jsonb_build_object('at', now(), 'by', name_of(me), 'score', least(greatest(coalesce((p ->> 'score')::int, 0), 0), 100),
      'find', coalesce((select jsonb_agg(f) from (select f from jsonb_array_elements(coalesce(p -> 'find', '[]'::jsonb)) f limit 80) z), '[]'::jsonb))) where id = iv.id;
    perform pt_cib_log(pid, 'Invoice reviewed (rules)', '#' || iv.seq, null, jsonb_build_object('score', p -> 'score'), null);
    return jsonb_build_object('ok', true);
  end if;
  if op = 'inv_docs' then
    if not (pt_cib_can(me, 'cib.prepare', pid) or pt_cib_can(me, 'cib.approve', pid)) then raise exception 'Only those who prepare or approve client invoices keep its documents' using errcode = '42501'; end if;
    if iv.status in ('Certified','Paid','Cancelled') then raise exception 'This invoice is closed'; end if;
    if p ->> 'k' not in ('appr','sum','mat','prog','spare','train','cont','ins','cert') then raise exception 'Unknown document'; end if;
    if coalesce(p ->> 'v', '') not in ('yes','na','') then raise exception 'Attached, not applicable or missing'; end if;
    update cib_invoices set data = jsonb_set(data, '{docs}', coalesce(data -> 'docs', '{}'::jsonb) || jsonb_build_object(p ->> 'k', p ->> 'v')) where id = iv.id;
    perform pt_cib_log(pid, 'Invoice document', '#' || iv.seq || ' ' || (p ->> 'k'), iv.data #> array['docs', p ->> 'k'], to_jsonb(p ->> 'v'), null);
    return jsonb_build_object('ok', true);
  end if;
  if op = 'inv_submit' then
    if iv.status <> 'Draft' then raise exception 'Only a draft is submitted'; end if;
    c := pt_cib_compute(pid, iv.schedule_id, iv.seq, iv.period_from, iv.period_to);
    if abs((c #>> '{tot,gross_this}')::numeric - (iv.data #>> '{tot,gross_this}')::numeric) > 0.5 then raise exception 'Progress, mapping or rules changed since this draft was calculated: recalculate it first'; end if;
    select string_agg(z ->> 'msg', ' · ') into e from jsonb_array_elements(c -> 'exc') z where z ->> 'sev' = 'block';
    if e is not null then raise exception 'Not submitted: %', e; end if;
    if jsonb_typeof(iv.data -> 'ai') is distinct from 'object' or coalesce((iv.data #>> '{ai,stale}')::boolean, false) or (iv.data #>> '{ai,at}')::timestamptz < iv.updated_at then raise exception 'Run "Review invoice" on the current figures first'; end if;
  elsif op = 'inv_review' then
    if iv.status <> 'Submitted' then raise exception 'Only a submitted invoice is reviewed'; end if;
    if iv.prepared_by = me and role_of(me) <> 'sa' then raise exception 'Nobody reviews an invoice they prepared'; end if;
  elsif op = 'inv_approve' then
    if iv.status <> 'Reviewed' then raise exception 'Only a reviewed invoice is approved'; end if;
    if (iv.prepared_by = me or reviewer = me) and role_of(me) <> 'sa' then raise exception 'Nobody approves an invoice they prepared or reviewed'; end if;
    if exists (select 1 from unnest(array['appr','sum','mat','prog','spare','train','cont','ins','cert']) dk where coalesce(iv.data #>> array['docs', dk], '') = '') then raise exception 'Mark every supporting document attached or not applicable first'; end if;
  elsif op = 'inv_return' then
    if not (pt_cib_can(me, 'cib.review', pid) or pt_cib_can(me, 'cib.approve', pid)) then raise exception 'Only a reviewer or approver returns an invoice' using errcode = '42501'; end if;
    if iv.status not in ('Submitted','Reviewed','Approved') then raise exception 'Only an invoice under review or approved is returned'; end if;
    if length(note) < 5 then raise exception 'Say why it is returned'; end if;
  elsif op = 'inv_issue' then
    if not (pt_cib_can(me, 'cib.prepare', pid) or pt_cib_can(me, 'cib.approve', pid)) then raise exception 'Only those who prepare or approve client invoices issue them' using errcode = '42501'; end if;
    if iv.status <> 'Approved' then raise exception 'Only an approved invoice is issued'; end if;
    if coalesce(p ->> 'date', '') !~ '^\d{4}-\d{2}-\d{2}$' or (p ->> 'date')::date > current_date then raise exception 'The issue date is not valid'; end if;
    if (p ->> 'date')::date < iv.period_to then raise exception 'An invoice is issued after its period ends'; end if;
  elsif op = 'inv_certify' then
    if iv.status <> 'Issued' then raise exception 'Only an issued invoice is certified'; end if;
    if coalesce(p ->> 'date', '') !~ '^\d{4}-\d{2}-\d{2}$' or (p ->> 'date')::date > current_date then raise exception 'The certificate date is not valid'; end if;
    if (p ->> 'date')::date < (iv.data #>> '{issued,date}')::date then raise exception 'Certified before it was issued'; end if;
  elsif op = 'inv_pay' then
    if iv.status <> 'Certified' then raise exception 'Only a certified invoice is marked paid'; end if;
    if coalesce(p ->> 'date', '') !~ '^\d{4}-\d{2}-\d{2}$' or (p ->> 'date')::date > current_date then raise exception 'The payment date is not valid'; end if;
    if (p ->> 'date')::date < (iv.data #>> '{cert,date}')::date then raise exception 'Paid before it was certified'; end if;
    amt := nullif(p ->> 'amt', '')::numeric; if amt is null or amt <= 0 then raise exception 'The amount paid is more than 0'; end if;
    if amt > (iv.data #>> '{tot,total}')::numeric + 0.5 then raise exception 'Paid more than the invoice total with VAT'; end if;
  elsif op = 'inv_cancel' then
    if iv.status = 'Draft' then if not pt_cib_can(me, 'cib.prepare', pid) then raise exception 'Only those who prepare client invoices cancel a draft' using errcode = '42501'; end if;
    else if not pt_cib_can(me, 'cib.approve', pid) then raise exception 'You do not have the right cib.approve for this project' using errcode = '42501'; end if;
      if iv.status not in ('Submitted','Reviewed','Approved') then raise exception 'An issued invoice is not cancelled: the client certifies it or rejects it with a credit note'; end if; end if;
    if length(note) < 5 then raise exception 'Say why it is cancelled'; end if;
  else raise exception 'Unknown action'; end if;

  -- the state change
  b := iv.data;
  if op = 'inv_certify' then
    tot := 0;
    select jsonb_agg(l || jsonb_build_object('cert_this', cc, 'cert_cum', round((l ->> 'prev_pay')::numeric + cc, 2))), sum(cc), bool_or(abs(cc - (l ->> 'this_pay')::numeric) > 0.005)
      into c, tot, ch from (select l, round(case when p -> 'lines' ? (l ->> 'no') and nullif(p #>> array['lines', l ->> 'no'], '') is not null then (p #>> array['lines', l ->> 'no'])::numeric else (l ->> 'this_pay')::numeric end, 2) cc
        from jsonb_array_elements(iv.data -> 'lines') l) z;
    if exists (select 1 from jsonb_array_elements(c) l where (l ->> 'cert_this')::numeric < 0 or (l ->> 'cert_this')::numeric > (l ->> 'this_pay')::numeric + 0.5) then raise exception 'A certified amount is negative or more than claimed'; end if;
    g := round(coalesce(tot, 0), 2); x := iv.data -> 'tot';
    if ch then
      select data -> 'tot' into pt from cib_invoices where project_id = pid and status in ('Certified','Paid') and seq < iv.seq order by seq desc limit 1; pt := coalesce(pt, '{}'::jsonb);
      select head into h from cib_schedules where id = iv.schedule_id;
      x := x || jsonb_build_object('gross_this', g, 'gross_cum', round((x ->> 'gross_prev')::numeric + g, 2),
        'ret_this', round(least(g * coalesce((h ->> 'ret_pct')::numeric, 0) / 100, greatest(0, (h ->> 'value')::numeric * coalesce(nullif(h ->> 'ret_cap', '')::numeric, 100) / 100 - coalesce((pt ->> 'ret_cum')::numeric, 0))), 2),
        'adv_this', round(least(g * coalesce((h ->> 'adv_rec')::numeric, 0) / 100, greatest(0, (x ->> 'adv_amt')::numeric - coalesce((pt ->> 'adv_cum')::numeric, 0))), 2));
      x := x || jsonb_build_object('ret_cum', round(coalesce((pt ->> 'ret_cum')::numeric, 0) + (x ->> 'ret_this')::numeric, 2), 'adv_cum', round(coalesce((pt ->> 'adv_cum')::numeric, 0) + (x ->> 'adv_this')::numeric, 2),
        'net', round(g - (x ->> 'ret_this')::numeric + (x ->> 'rel_this')::numeric - (x ->> 'adv_this')::numeric, 2), 'balance', round((x ->> 'cv')::numeric - (x ->> 'gross_prev')::numeric - g, 2));
      x := x || jsonb_build_object('vat', round((x ->> 'net')::numeric * (x ->> 'vat_pct')::numeric / 100, 2));
      x := x || jsonb_build_object('total', round((x ->> 'net')::numeric + (x ->> 'vat')::numeric, 2));
    end if;
    update cib_invoices set data = data || jsonb_build_object('lines', c, 'tot', x, 'cert', jsonb_build_object('amt', g, 'date', p ->> 'date', 'ref', left(p ->> 'ref', 60), 'by', name_of(me), 'at', now(), 'changed', coalesce(ch, false))) where id = iv.id;
  elsif op = 'inv_issue' then
    update cib_invoices set data = data || jsonb_build_object('issued', jsonb_build_object('date', p ->> 'date', 'ref', coalesce(nullif(left(p ->> 'ref', 60), ''), iv.data ->> 'ref'), 'by', name_of(me)),
      'ref', coalesce(nullif(left(p ->> 'ref', 60), ''), iv.data ->> 'ref')) where id = iv.id;
  elsif op = 'inv_pay' then
    update cib_invoices set data = data || jsonb_build_object('paid', jsonb_build_object('amt', round(amt, 2), 'date', p ->> 'date', 'ref', left(p ->> 'ref', 60), 'by', name_of(me))) where id = iv.id;
  elsif op = 'inv_return' then
    update cib_invoices set data = case when jsonb_typeof(data -> 'ai') = 'object' then jsonb_set(data, '{ai,stale}', 'true') else data end where id = iv.id;
  end if;
  k := case op when 'inv_submit' then 'Submitted' when 'inv_review' then 'Reviewed' when 'inv_approve' then 'Approved' when 'inv_return' then 'Draft' when 'inv_issue' then 'Issued'
    when 'inv_certify' then 'Certified' when 'inv_pay' then 'Paid' else 'Cancelled' end;
  update cib_invoices set status = k, updated_at = case when op = 'inv_return' then now() else updated_at end,
    hist = hist || jsonb_build_array(jsonb_build_object('st', k, 'by', name_of(me), 'by_id', me, 'at', now(), 'note', case when op = 'inv_return' then 'Returned: ' || note when op = 'inv_certify' and ch then 'Certified with changes' else nullif(note, '') end))
    where id = iv.id;
  perform pt_cib_log(pid, 'Invoice ' || lower(case when k = 'Draft' then 'returned' else k end), '#' || iv.seq || ' ' || (iv.data ->> 'ref'), jsonb_build_object('st', iv.status), jsonb_build_object('st', k), nullif(note, ''));
  return jsonb_build_object('ok', true, 'st', k);
end $$;

revoke execute on function cib_fmt_act(jsonb), pt_cib_fmt_see(uuid), pt_cib_fmt_keep(uuid) from public, anon;
grant execute on function cib_fmt_act(jsonb), pt_cib_fmt_see(uuid), pt_cib_fmt_keep(uuid) to authenticated;
