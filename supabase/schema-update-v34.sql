-- ProTrack schema update v34 (ProTrackAI v3.27): the release strategy (go-live stage by stage) and document text for RASA.
-- 1. golive_cfg holds one row, the release strategy: the stages (name, planned go-live date), the stage of each module, the
--    stage live up to (0 = nothing live yet), and whether the menu hides the modules not live yet. Everyone signed in reads
--    it (RASA and the menu need it). golive_set(p) changes it: a super admin only, with the checks of the app's glCheck().
--    Each change is kept in golive_audit, which cannot be changed. The first row keeps every module live (live up to stage
--    4), as before this update, until the super admin sets the plan.
-- 2. doc_text keeps the text of a document of the Project document rack, page by page (PDF), sheet by sheet (Excel, CSV) or
--    in parts of about 3,000 characters (Word, TXT, XER, XML), read in the browser when the file is uploaded. doc_text_meta
--    keeps one row per document: pages, characters, status (Read, No text, Failed), by whom and when.
--    Both are read with the rights of the document itself (pt_doc_can, v13): who cannot read a document cannot read its text.
--    doc_text_set(p) replaces the text of a document: the people who keep its box, or a super admin.
--    doc_text_info() lists the text status of the documents the person can read.
--    doc_text_search(p) finds passages for RASA: full text (english) over the words, the documents the person can read only,
--    ranked by how many of the words a page holds, with the passage around them (ts_headline).
-- 3. golive_features() tells the app this update is in.
-- Needs schema-update-v13.sql (documents, pt_doc_can). Additive. Safe to run twice. Undo: schema-rollback-v34.sql.

do $$ begin
  if to_regclass('public.documents') is null or to_regprocedure('public.pt_doc_can(uuid,text,text,boolean)') is null then
    raise exception 'Run schema-update-v13.sql (STAGE-10-SETUP) first, then this update'; end if;
end $$;

-- ------------------------------------------------------------------ 1. the release strategy
create table if not exists golive_cfg (
  id int primary key check (id = 1),
  cfg jsonb not null,
  updated_by uuid references profiles(id), updated_name text, updated_at timestamptz not null default now());
create table if not exists golive_audit (
  id bigserial primary key,
  cfg jsonb not null,
  note text check (note is null or length(note) <= 300),
  by_user uuid references profiles(id), by_name text,
  at_time timestamptz not null default now());
insert into golive_cfg (id, cfg) values (1, jsonb_build_object(
  'stages', jsonb_build_array(jsonb_build_object('n', 1, 'name', 'Stage 1', 'date', null), jsonb_build_object('n', 2, 'name', 'Stage 2', 'date', null),
                              jsonb_build_object('n', 3, 'name', 'Stage 3', 'date', null), jsonb_build_object('n', 4, 'name', 'Stage 4', 'date', null)),
  'map', jsonb_build_object('daily', 1, 'planning', 1, 'projects', 1, 'reports', 1, 'home', 2, 'docs', 2, 'cost', 2, 'materials', 3, 'claims', 3, 'invoices', 3, 'boq', 4),
  'current', 4, 'hide_menu', false))
on conflict (id) do nothing;

alter table golive_cfg enable row level security;
alter table golive_audit enable row level security;
drop policy if exists gl_read on golive_cfg;
create policy gl_read on golive_cfg for select using (auth.uid() is not null);
drop policy if exists gla_read on golive_audit;
create policy gla_read on golive_audit for select using (role_of(auth.uid()) = 'sa');
drop trigger if exists trg_gla_append on golive_audit;
create trigger trg_gla_append before update or delete on golive_audit for each row execute function pt_append_only();
drop trigger if exists trg_gla_truncate on golive_audit;
create trigger trg_gla_truncate before truncate on golive_audit execute function pt_no_truncate();
revoke all on golive_cfg, golive_audit from anon;
revoke insert, update, delete, truncate on golive_cfg, golive_audit from authenticated;
grant select on golive_cfg, golive_audit to authenticated;

-- p: {stages: [{name, date}], map: {module: stage}, current, hide_menu, note}
create or replace function golive_set(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); st jsonb := p -> 'stages'; n int; i int; x jsonb; nm text; d text; prev date; m text; v int; cur int; c jsonb;
        mods text[] := array['daily','planning','projects','docs','home','cost','materials','claims','invoices','boq','reports'];
        stages jsonb := '[]'::jsonb; map jsonb := '{}'::jsonb;
begin
  if me is null or role_of(me) is distinct from 'sa' then raise exception 'Only a super admin changes the release strategy' using errcode = '42501'; end if;
  if jsonb_typeof(st) is distinct from 'array' then raise exception 'Between 1 and 6 stages'; end if;
  n := jsonb_array_length(st);
  if n < 1 or n > 6 then raise exception 'Between 1 and 6 stages'; end if;
  for i in 0 .. n - 1 loop
    x := st -> i; nm := btrim(regexp_replace(coalesce(x ->> 'name', ''), '\s+', ' ', 'g')); d := nullif(x ->> 'date', '');
    if nm = '' or length(nm) > 40 then raise exception 'Each stage needs a name of 40 characters at most'; end if;
    if d is not null then
      if d !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'A planned go-live is a date'; end if;
      if prev is not null and d::date < prev then raise exception 'A later stage cannot go live before an earlier one'; end if;
      prev := d::date;
    end if;
    stages := stages || jsonb_build_array(jsonb_build_object('n', i + 1, 'name', nm, 'date', d));
  end loop;
  foreach m in array mods loop
    v := case when coalesce(p -> 'map' ->> m, '') ~ '^\d{1,2}$' then (p -> 'map' ->> m)::int end;
    if v is null or v < 1 or v > n then raise exception 'Each module needs a stage from 1 to %', n; end if;
    map := map || jsonb_build_object(m, v);
  end loop;
  cur := case when coalesce(p ->> 'current', '') ~ '^\d{1,2}$' then (p ->> 'current')::int end;
  if cur is null or cur < 0 or cur > n then raise exception 'Live up to a stage from 0 (nothing live yet) to %', n; end if;
  if length(coalesce(p ->> 'note', '')) > 300 then raise exception 'A comment is 300 characters at most'; end if;
  if p ? 'hide_menu' and jsonb_typeof(p -> 'hide_menu') is distinct from 'boolean' then raise exception 'hide_menu is true or false'; end if;
  c := jsonb_build_object('stages', stages, 'map', map, 'current', cur, 'hide_menu', coalesce((p ->> 'hide_menu')::boolean, false));
  insert into golive_cfg (id, cfg, updated_by, updated_name, updated_at) values (1, c, me, name_of(me), now())
  on conflict (id) do update set cfg = excluded.cfg, updated_by = excluded.updated_by, updated_name = excluded.updated_name, updated_at = excluded.updated_at;
  insert into golive_audit (cfg, note, by_user, by_name) values (c, nullif(btrim(coalesce(p ->> 'note', '')), ''), me, name_of(me));
  return c;
end $$;

-- ------------------------------------------------------------------ 2. document text
create table if not exists doc_text_meta (
  doc_id uuid primary key references documents(id) on delete cascade,
  pages int not null default 0 check (pages between 0 and 400),
  chars int not null default 0,
  status text not null check (status in ('Read','No text','Failed')),
  unit text not null default 'page' check (unit in ('page','sheet','part')),
  error text check (error is null or length(error) <= 300),
  by_user uuid references profiles(id), by_name text,
  at_time timestamptz not null default now());
create table if not exists doc_text (
  doc_id uuid not null references documents(id) on delete cascade,
  page int not null check (page between 1 and 400),
  body text not null check (length(body) <= 20000),
  tsv tsvector generated always as (to_tsvector('english', body)) stored,
  primary key (doc_id, page));
create index if not exists doc_text_tsv on doc_text using gin (tsv);

alter table doc_text_meta enable row level security;
alter table doc_text enable row level security;
-- the rights of the document itself, wherever it sits now (a document moved to another box takes its text with it)
drop policy if exists dtm_read on doc_text_meta;
create policy dtm_read on doc_text_meta for select using (exists (select 1 from documents d where d.id = doc_id and pt_doc_can(auth.uid(), d.project_id, d.box_key, false)));
drop policy if exists dtx_read on doc_text;
create policy dtx_read on doc_text for select using (exists (select 1 from documents d where d.id = doc_id and pt_doc_can(auth.uid(), d.project_id, d.box_key, false)));
revoke all on doc_text_meta, doc_text from anon;
revoke insert, update, delete, truncate on doc_text_meta, doc_text from authenticated;
grant select on doc_text_meta, doc_text to authenticated;

-- p: {doc_id, pages: [text], status: 'Read' | 'No text' | 'Failed', unit: 'page' | 'sheet' | 'part', error}
create or replace function doc_text_set(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); d documents; st text := p ->> 'status'; un text := coalesce(nullif(p ->> 'unit', ''), 'page');
        pg jsonb := coalesce(p -> 'pages', '[]'::jsonb); x jsonb; i int := 0; ch int := 0; t text;
begin
  if me is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  select * into d from documents where id = case when coalesce(p ->> 'doc_id', '') ~ '^[0-9a-fA-F-]{36}$' then (p ->> 'doc_id')::uuid end;
  if d.id is null or not pt_doc_can(me, d.project_id, d.box_key, false) then raise exception 'Unknown document'; end if;
  if role_of(me) is distinct from 'sa' and not pt_doc_can(me, d.project_id, d.box_key, true) then
    raise exception 'Only the people who keep this box read its text for RASA' using errcode = '42501'; end if;
  if st is null or st not in ('Read','No text','Failed') then raise exception 'Unknown status'; end if;
  if un not in ('page','sheet','part') then raise exception 'Unknown unit'; end if;
  if jsonb_typeof(pg) is distinct from 'array' then raise exception 'The pages are a list'; end if;
  if jsonb_array_length(pg) > 400 then raise exception 'At most 400 pages'; end if;
  if st <> 'Read' and jsonb_array_length(pg) > 0 then raise exception 'Only text that was read has pages'; end if;
  delete from doc_text where doc_id = d.id;
  for x in select * from jsonb_array_elements(pg) loop
    i := i + 1;
    if jsonb_typeof(x) is distinct from 'string' then raise exception 'Page % is not text', i; end if;
    t := left(x #>> '{}', 20000); ch := ch + length(btrim(t));
    if btrim(t) <> '' then insert into doc_text (doc_id, page, body) values (d.id, i, t); end if;
  end loop;
  if st = 'Read' and ch < 20 then st := 'No text'; delete from doc_text where doc_id = d.id; end if;
  insert into doc_text_meta (doc_id, pages, chars, status, unit, error, by_user, by_name, at_time)
  values (d.id, case when st = 'Read' then i else 0 end, ch, st, un, left(nullif(p ->> 'error', ''), 300), me, name_of(me), now())
  on conflict (doc_id) do update set pages = excluded.pages, chars = excluded.chars, status = excluded.status, unit = excluded.unit,
    error = excluded.error, by_user = excluded.by_user, by_name = excluded.by_name, at_time = excluded.at_time;
  return jsonb_build_object('doc_id', d.id, 'pages', case when st = 'Read' then i else 0 end, 'status', st);
end $$;

create or replace function doc_text_info() returns table (doc_id uuid, pages int, chars int, status text, unit text, error text, by_name text, at_time timestamptz)
language sql stable security definer set search_path = public as $$
  select m.doc_id, m.pages, m.chars, m.status, m.unit, m.error, m.by_name, m.at_time
    from doc_text_meta m join documents d on d.id = m.doc_id
   where pt_doc_can(auth.uid(), d.project_id, d.box_key, false) $$;

-- p: {terms: [word], pids: [project], lim}
create or replace function doc_text_search(p jsonb) returns table (doc_id uuid, page int, snippet text, rank real, hits int)
language plpgsql stable security definer set search_path = public as $$
declare terms text[]; q tsquery; lim int; me uuid := auth.uid();
begin
  if me is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  lim := least(greatest(case when coalesce(p ->> 'lim', '') ~ '^\d{1,3}$' then (p ->> 'lim')::int else 12 end, 1), 30);
  select array_agg(w) into terms from (
    select distinct lower(regexp_replace(value, '[^A-Za-z0-9]', '', 'g')) w
      from jsonb_array_elements_text(case when jsonb_typeof(p -> 'terms') = 'array' then p -> 'terms' else '[]'::jsonb end)) s
   where w <> '' and length(to_tsvector('english', w)) > 0;   -- an english stop word has no lexeme
  if terms is null then return; end if;
  terms := terms[1:12];
  q := to_tsquery('english', array_to_string(array(select t || ':*' from unnest(terms) t), ' | '));
  return query
    select x.doc_id, x.page,
           ts_headline('english', x.body, q, 'StartSel=[[,StopSel=]],MaxWords=60,MinWords=25,ShortWord=2,MaxFragments=1'),
           ts_rank_cd(x.tsv, q),
           (select count(*)::int from unnest(terms) w where x.tsv @@ to_tsquery('english', w || ':*'))
      from doc_text x join documents d on d.id = x.doc_id
     where x.tsv @@ q and pt_doc_can(me, d.project_id, d.box_key, false)
       and (jsonb_typeof(p -> 'pids') is distinct from 'array' or d.project_id in (select jsonb_array_elements_text(p -> 'pids')))
     order by 5 desc, 4 desc
     limit lim;
end $$;

-- ------------------------------------------------------------------ 3. the app checks this
create or replace function golive_features() returns jsonb language sql stable as $$ select jsonb_build_object('release_strategy', true, 'doc_text', true) $$;

revoke execute on function golive_set(jsonb), doc_text_set(jsonb), doc_text_info(), doc_text_search(jsonb), golive_features() from public, anon;
grant execute on function golive_set(jsonb), doc_text_set(jsonb), doc_text_info(), doc_text_search(jsonb), golive_features() to authenticated;
