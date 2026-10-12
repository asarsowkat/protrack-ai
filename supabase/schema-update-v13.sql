-- ProTrack schema update v13 (ProTrackAI v3.4): the three-row project document rack.
-- Row 1 Contract & Commercial (kept by the costing engineer), Row 2 Planning & Scheduling (planning engineer),
-- Row 3 Cost Control & Costing (costing engineer). The Head of Planning and Cost Control and super admins keep all three.
-- Each project has default box files (C01-C10, P01-P12, K01-K14); authorized people can rename, reorder, hide and add boxes.
-- Documents are stored in a private Supabase Storage bucket, "project-docs", at <project>/<box>/<id>/<file name>.
-- Files are never overwritten or deleted by the app: a new revision is a new file. Nothing here changes budgets,
-- schedules, change orders or any ProTrackAI calculation: documents are records only.
-- Additive: new tables, functions, one bucket and its access rules. Safe to run twice. Undo: schema-rollback-v13.sql.

-- ------------------------------------------------------------------ storage bucket (private, 50 MB a file)
insert into storage.buckets (id, name, public, file_size_limit)
values ('project-docs', 'project-docs', false, 52428800)
on conflict (id) do update set public = false, file_size_limit = 52428800;

-- ------------------------------------------------------------------ box files
create table if not exists doc_boxes (
  project_id text not null references projects(id) on delete cascade,
  box_key text not null check (box_key ~ '^[A-Z][A-Z0-9]{1,11}$'),
  row_key text not null check (row_key in ('contract','planning','cost')),
  title text check (title is null or length(btrim(title)) between 1 and 80),   -- null: the default title
  sort int,
  hidden boolean not null default false,
  note text check (note is null or length(note) <= 500),
  created_by uuid references profiles(id), created_at timestamptz not null default now(),
  updated_by uuid references profiles(id), updated_at timestamptz not null default now(),
  primary key (project_id, box_key));

-- which row a box belongs to: its saved row, else the default box's row
create or replace function pt_doc_row(pid text, k text) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select row_key from doc_boxes where project_id = pid and box_key = k),
    case when k ~ '^C(0[1-9]|10)$' then 'contract' when k ~ '^P(0[1-9]|1[0-2])$' then 'planning'
         when k ~ '^K(0[1-9]|1[0-4])$' then 'cost' end) $$;

-- who may read (w = false) or keep (w = true) the documents of a box
--   read:  people with access to the project; Contract and Cost rows not for site staff (foreman, site engineer,
--          site manager); the Planning row not for foremen
--   keep:  Contract and Cost rows: costing engineers; Planning row: planning engineers; the Head and super admins: all
create or replace function pt_doc_can(u uuid, pid text, k text, w boolean) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare rw text := pt_doc_row(pid, k); r text := role_of(u);
begin
  if u is null or r is null or rw is null or pid is null or not user_sees(u, pid) then return false; end if;
  if not w then
    return case when rw = 'planning' then r <> 'foreman' else r not in ('foreman','eng','sm') end;
  end if;
  return r = 'sa' or pt_is_head(u) or (rw = 'planning' and r = 'plan') or (rw in ('contract','cost') and r = 'costing');
end $$;

alter table doc_boxes enable row level security;
drop policy if exists db_read on doc_boxes;
create policy db_read on doc_boxes for select using (pt_doc_can(auth.uid(), project_id, box_key, false));
-- no write policies: only doc_act writes boxes

-- ------------------------------------------------------------------ documents (one row per file; revisions are new rows)
create table if not exists documents (
  id uuid primary key default uuid_generate_v4(),
  project_id text not null references projects(id) on delete cascade,
  box_key text not null,
  title text not null check (length(btrim(title)) between 1 and 200),
  category text check (category is null or length(category) <= 120),
  ref_no text check (ref_no is null or length(ref_no) <= 80),
  revision text check (revision is null or length(revision) <= 30),
  period text check (period is null or period ~ '^\d{4}-(0[1-9]|1[0-2])$' or period ~ '^\d{4}-W(0[1-9]|[1-4]\d|5[0-3])$'),
  doc_date date,
  status text not null default 'For information' check (status in ('Draft','Submitted','Issued','Approved','Certified','Rejected','Paid','Superseded','For information')),
  description text check (description is null or length(description) <= 2000),
  storage_path text not null unique,
  file_name text not null,
  file_size bigint,
  mime text,
  sha256 text check (sha256 is null or sha256 ~ '^[0-9a-f]{64}$'),
  supersedes uuid references documents(id),
  created_by uuid references profiles(id), created_at timestamptz not null default now(),
  updated_by uuid references profiles(id), updated_at timestamptz not null default now());
create index if not exists documents_box on documents (project_id, box_key, created_at desc);

-- the file of a document never changes
create or replace function pt_doc_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'Documents are kept; mark them Superseded instead' using errcode = '42501'; end if;
  if new.storage_path is distinct from old.storage_path or new.file_name is distinct from old.file_name or new.sha256 is distinct from old.sha256
     or new.file_size is distinct from old.file_size or new.project_id is distinct from old.project_id or new.box_key is distinct from old.box_key
     or new.created_by is distinct from old.created_by or new.created_at is distinct from old.created_at or new.supersedes is distinct from old.supersedes then
    raise exception 'The file of a document cannot be changed; upload a new revision' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists trg_doc_guard on documents;
create trigger trg_doc_guard before update or delete on documents for each row execute function pt_doc_guard();
drop trigger if exists trg_doc_truncate on documents;
create trigger trg_doc_truncate before truncate on documents execute function pt_no_truncate();

alter table documents enable row level security;
drop policy if exists doc_read on documents;
create policy doc_read on documents for select using (pt_doc_can(auth.uid(), project_id, box_key, false));

-- ------------------------------------------------------------------ history (append-only)
create table if not exists doc_audit (
  id bigserial primary key,
  doc_id uuid references documents(id),
  project_id text not null references projects(id) on delete cascade,
  box_key text,
  action text not null, note text, detail jsonb,
  by_user uuid references profiles(id), by_name text, by_role text,
  at_time timestamptz not null default now());
create index if not exists doc_audit_doc on doc_audit (doc_id, id);
drop trigger if exists trg_doca_append on doc_audit;
create trigger trg_doca_append before update or delete on doc_audit for each row execute function pt_append_only();
drop trigger if exists trg_doca_truncate on doc_audit;
create trigger trg_doca_truncate before truncate on doc_audit execute function pt_no_truncate();
alter table doc_audit enable row level security;
drop policy if exists doca_read on doc_audit;
create policy doca_read on doc_audit for select using (case when box_key is null then can_see(project_id) and pt_money_ok()
                                                       else pt_doc_can(auth.uid(), project_id, box_key, false) end);

create or replace function pt_doc_log(did uuid, pid text, k text, a text, n text, d jsonb) returns void
language sql security definer set search_path = public as $$
  insert into doc_audit (doc_id, project_id, box_key, action, note, detail, by_user, by_name, by_role)
  values (did, pid, k, a, nullif(btrim(coalesce(n, '')), ''), d, auth.uid(), name_of(auth.uid()), role_of(auth.uid())) $$;

-- ------------------------------------------------------------------ storage access rules for the bucket
-- path: <project>/<box>/<id>/<file name>; reading and adding follow pt_doc_can; there is no rule to change or delete a file
drop policy if exists protrack_docs_read on storage.objects;
create policy protrack_docs_read on storage.objects for select to authenticated
  using (bucket_id = 'project-docs' and public.pt_doc_can(auth.uid(), split_part(name, '/', 1), split_part(name, '/', 2), false));
drop policy if exists protrack_docs_add on storage.objects;
create policy protrack_docs_add on storage.objects for insert to authenticated
  with check (bucket_id = 'project-docs' and array_length(string_to_array(name, '/'), 1) = 4
              and name ~* '\.(pdf|docx?|xlsx?|xlsm|xlsb|csv|pptx?|xer|xml|mpp|zip|png|jpe?g|gif|webp|tiff?|txt|msg|eml|dwg|dxf)$'
              and public.pt_doc_can(auth.uid(), split_part(name, '/', 1), split_part(name, '/', 2), true));

-- ------------------------------------------------------------------ the only way to write documents and boxes
-- p.action: add | edit | status | box_save | box_order
create or replace function doc_act(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); a text := p ->> 'action'; pid text; k text; d documents; o record; n text := p ->> 'note';
        f jsonb := coalesce(p -> 'fields', '{}'::jsonb); ch text[] := '{}'; x text; rw text; i int; sz bigint; mt text; st text;
begin
  if me is null or role_of(me) is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if a is null or a not in ('add','edit','status','box_save','box_order') then raise exception 'Unknown action %', a; end if;

  if a in ('edit','status') then
    select * into d from documents where id = nullif(p ->> 'id', '')::uuid for update;
    if d.id is null or not pt_doc_can(me, d.project_id, d.box_key, false) then raise exception 'Unknown document'; end if;
    if not pt_doc_can(me, d.project_id, d.box_key, true) then raise exception 'You can see this document but not change it' using errcode = '42501'; end if;
    if a = 'status' then
      st := p ->> 'status';
      if st is null or st not in ('Draft','Submitted','Issued','Approved','Certified','Rejected','Paid','Superseded','For information') then raise exception 'Unknown status %', st; end if;
      if st = d.status then return to_jsonb(d); end if;
      x := d.status;
      if st in ('Rejected','Superseded') and nullif(btrim(coalesce(n, '')), '') is null then raise exception 'Add a comment saying why the document is %', lower(st); end if;
      update documents set status = st, updated_by = me, updated_at = now() where id = d.id returning * into d;
      perform pt_doc_log(d.id, d.project_id, d.box_key, 'Status ' || st, n, jsonb_build_object('from', x, 'to', st));
      return to_jsonb(d);
    end if;
    -- edit: details only, never the file
    if f ? 'title' and length(btrim(coalesce(f ->> 'title', ''))) not between 1 and 200 then raise exception 'The title is needed (200 characters at most)'; end if;
    if f ? 'period' and nullif(f ->> 'period', '') is not null and not ((f ->> 'period') ~ '^\d{4}-(0[1-9]|1[0-2])$' or (f ->> 'period') ~ '^\d{4}-W(0[1-9]|[1-4]\d|5[0-3])$') then raise exception 'The period must look like 2026-09 or 2026-W41'; end if;
    if f ? 'doc_date' and pt_bad_date(f ->> 'doc_date') then raise exception 'The document date is not a valid date'; end if;
    foreach x in array array['title','category','ref_no','revision','period','doc_date','description'] loop
      if f ? x and (to_jsonb(d) ->> x) is distinct from nullif(btrim(coalesce(f ->> x, '')), '') then ch := ch || x; end if;
    end loop;
    if array_length(ch, 1) is null then return to_jsonb(d); end if;
    update documents set
      title = case when f ? 'title' then btrim(f ->> 'title') else title end,
      category = case when f ? 'category' then nullif(btrim(coalesce(f ->> 'category', '')), '') else category end,
      ref_no = case when f ? 'ref_no' then nullif(btrim(coalesce(f ->> 'ref_no', '')), '') else ref_no end,
      revision = case when f ? 'revision' then nullif(btrim(coalesce(f ->> 'revision', '')), '') else revision end,
      period = case when f ? 'period' then nullif(btrim(coalesce(f ->> 'period', '')), '') else period end,
      doc_date = case when f ? 'doc_date' then pt_date(f ->> 'doc_date') else doc_date end,
      description = case when f ? 'description' then nullif(btrim(coalesce(f ->> 'description', '')), '') else description end,
      updated_by = me, updated_at = now()
     where id = d.id returning * into d;
    perform pt_doc_log(d.id, d.project_id, d.box_key, 'Details changed', n, jsonb_build_object('changes', to_jsonb(ch)));
    return to_jsonb(d);
  end if;

  pid := p ->> 'project_id';
  if pid is null or not user_sees(me, pid) then raise exception 'You do not have access to this project' using errcode = '42501'; end if;

  if a = 'add' then
    k := upper(btrim(coalesce(p ->> 'box_key', '')));
    if not pt_doc_can(me, pid, k, true) then raise exception 'Only the people who keep this row can add documents to it' using errcode = '42501'; end if;
    x := p ->> 'storage_path';
    if x is null or split_part(x, '/', 1) <> pid or split_part(x, '/', 2) <> k or array_length(string_to_array(x, '/'), 1) <> 4 then
      raise exception 'The file is not in this box''s folder'; end if;
    select (metadata ->> 'size')::bigint, metadata ->> 'mimetype' into sz, mt from storage.objects where bucket_id = 'project-docs' and name = x;
    if not found then raise exception 'The file was not found in storage; upload it again'; end if;
    if exists (select 1 from documents where storage_path = x) then raise exception 'This file is already registered'; end if;
    if length(btrim(coalesce(p ->> 'title', ''))) not between 1 and 200 then raise exception 'The title is needed (200 characters at most)'; end if;
    st := coalesce(nullif(p ->> 'status', ''), 'For information');
    if st not in ('Draft','Submitted','Issued','Approved','Certified','Rejected','Paid','Superseded','For information') then raise exception 'Unknown status %', st; end if;
    if nullif(p ->> 'period', '') is not null and not ((p ->> 'period') ~ '^\d{4}-(0[1-9]|1[0-2])$' or (p ->> 'period') ~ '^\d{4}-W(0[1-9]|[1-4]\d|5[0-3])$') then
      raise exception 'The period must look like 2026-09 or 2026-W41'; end if;
    if pt_bad_date(p ->> 'doc_date') then raise exception 'The document date is not a valid date'; end if;
    if nullif(p ->> 'supersedes', '') is not null and not exists (select 1 from documents where id = (p ->> 'supersedes')::uuid and project_id = pid and box_key = k) then
      raise exception 'A new revision must be in the same box as the document it replaces'; end if;
    insert into documents (project_id, box_key, title, category, ref_no, revision, period, doc_date, status, description, storage_path, file_name, file_size, mime, sha256, supersedes, created_by, updated_by)
    values (pid, k, btrim(p ->> 'title'), nullif(btrim(coalesce(p ->> 'category', '')), ''), nullif(btrim(coalesce(p ->> 'ref_no', '')), ''),
            nullif(btrim(coalesce(p ->> 'revision', '')), ''), nullif(p ->> 'period', ''), pt_date(p ->> 'doc_date'), st,
            nullif(btrim(coalesce(p ->> 'description', '')), ''), x, coalesce(nullif(btrim(p ->> 'file_name'), ''), split_part(x, '/', 4)), sz, mt,
            nullif(lower(p ->> 'sha256'), ''), nullif(p ->> 'supersedes', '')::uuid, me, me)
    returning * into d;
    perform pt_doc_log(d.id, pid, k, case when d.supersedes is null then 'Uploaded' else 'New revision uploaded' end, n,
                       jsonb_build_object('file', d.file_name, 'size', d.file_size, 'revision', d.revision, 'supersedes', d.supersedes));
    return to_jsonb(d);
  end if;

  if a = 'box_save' then
    k := upper(btrim(coalesce(p ->> 'box_key', '')));
    if k = '' then   -- a new box
      rw := p ->> 'row_key';
      if rw is null or rw not in ('contract','planning','cost') then raise exception 'Choose the row for the new box'; end if;
      if length(btrim(coalesce(p ->> 'title', ''))) not between 1 and 80 then raise exception 'The box needs a name (80 characters at most)'; end if;
      if not (role_of(me) = 'sa' or pt_is_head(me) or (rw = 'planning' and role_of(me) = 'plan') or (rw <> 'planning' and role_of(me) = 'costing')) then
        raise exception 'Only the people who keep this row can add boxes to it' using errcode = '42501'; end if;
      if (select count(*) from doc_boxes where project_id = pid and box_key like 'X%') >= 60 then raise exception 'At most 60 added boxes per project'; end if;
      loop k := 'X' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6)); exit when not exists (select 1 from doc_boxes where project_id = pid and box_key = k); end loop;
      insert into doc_boxes (project_id, box_key, row_key, title, sort, note, created_by, updated_by)
      values (pid, k, rw, btrim(p ->> 'title'), coalesce((p ->> 'sort')::int, 1000), nullif(btrim(coalesce(p ->> 'note', '')), ''), me, me);
      perform pt_doc_log(null, pid, k, 'Box added', p ->> 'title', jsonb_build_object('row', rw));
      return jsonb_build_object('box_key', k);
    end if;
    rw := pt_doc_row(pid, k);
    if rw is null then raise exception 'Unknown box %', k; end if;
    if not pt_doc_can(me, pid, k, true) then raise exception 'Only the people who keep this row can change its boxes' using errcode = '42501'; end if;
    if p ? 'title' and nullif(btrim(coalesce(p ->> 'title', '')), '') is not null and length(btrim(p ->> 'title')) > 80 then raise exception 'The box name is too long (80 characters at most)'; end if;
    insert into doc_boxes (project_id, box_key, row_key, title, sort, hidden, note, created_by, updated_by)
    values (pid, k, rw, case when p ? 'title' then nullif(btrim(coalesce(p ->> 'title', '')), '') end, (p ->> 'sort')::int, coalesce((p ->> 'hidden')::boolean, false),
            case when p ? 'note' then nullif(btrim(coalesce(p ->> 'note', '')), '') end, me, me)
    on conflict (project_id, box_key) do update set
      title = case when p ? 'title' then nullif(btrim(coalesce(p ->> 'title', '')), '') else doc_boxes.title end,
      sort = case when p ? 'sort' then (p ->> 'sort')::int else doc_boxes.sort end,
      hidden = case when p ? 'hidden' then (p ->> 'hidden')::boolean else doc_boxes.hidden end,
      note = case when p ? 'note' then nullif(btrim(coalesce(p ->> 'note', '')), '') else doc_boxes.note end,
      updated_by = me, updated_at = now();
    perform pt_doc_log(null, pid, k, 'Box changed', null, p - 'action' - 'project_id' - 'box_key');
    return jsonb_build_object('box_key', k);
  end if;

  -- box_order: the boxes of one row, in the order given
  rw := p ->> 'row_key';
  if rw is null or rw not in ('contract','planning','cost') then raise exception 'Choose the row to reorder'; end if;
  if jsonb_typeof(p -> 'keys') <> 'array' then raise exception 'Give the boxes in their new order'; end if;
  i := 0;
  for x in select jsonb_array_elements_text(p -> 'keys') loop
    i := i + 1; k := upper(x);
    if pt_doc_row(pid, k) is distinct from rw then raise exception 'Box % is not in this row', k; end if;
    if not pt_doc_can(me, pid, k, true) then raise exception 'Only the people who keep this row can reorder it' using errcode = '42501'; end if;
    insert into doc_boxes (project_id, box_key, row_key, sort, created_by, updated_by) values (pid, k, rw, i * 10, me, me)
    on conflict (project_id, box_key) do update set sort = i * 10, updated_by = me, updated_at = now();
  end loop;
  perform pt_doc_log(null, pid, null, 'Boxes reordered', null, jsonb_build_object('row', rw, 'keys', p -> 'keys'));
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function pt_doc_row(text, text), pt_doc_log(uuid, text, text, text, text, jsonb), pt_doc_guard() from public, anon, authenticated;
revoke execute on function pt_doc_can(uuid, text, text, boolean), doc_act(jsonb) from public, anon;
grant execute on function pt_doc_can(uuid, text, text, boolean), doc_act(jsonb) to authenticated;
grant select on doc_boxes, documents, doc_audit to authenticated;
