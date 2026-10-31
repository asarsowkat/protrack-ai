-- ProTrack schema update v50 (ProTrackAI v3.47): RASA Intelligence, the central knowledge and learning hub.
-- 1. Four rights: rasa.teach (submit corrections, business rules and knowledge for unanswered questions; executives, regional
--    managers, portfolio, planning, costing and project managers by default), rasa.sync (refresh what RASA reads from the modules;
--    planning and costing), rasa.review (knowledge reviewer of their projects; given by the super admin) and rasa.company
--    (designated approver of company-wide knowledge; given by the super admin). The screen 'rasa' joins pt_screens().
-- 2. The knowledge index: rasa_sources (one per record or document, with its module, project, access class, approval status,
--    content hash and version) and rasa_chunks (its passages, searchable with a full-text index). Nobody reads the passages
--    directly: rasa_search and rasa_passages return only what the asker may open (projects in access, cost figures, the
--    document rack's rows, report readers), checked here on every call.
--    ON HOLD until alfanar IT and Cybersecurity approve: embeddings and vector search (pgvector). The column and index are
--    written below as comments; search is full text with stemming, record numbers and filters until then.
-- 3. rasa_runs (every sync), rasa_proposals and rasa_publications (the review workflow and the published knowledge versions),
--    rasa_gaps (unanswered questions), rasa_feedback, rasa_questions (the question log, kept for the configured days) and
--    rasa_activity (append-only). rasa_config holds the module switches, sync strategies, approval policies and retention.
-- 4. Every write goes through rasa_act(p) and rasa_sync(p): the server checks the right, the project, the access class and
--    every state change again (Draft → Submitted → Under Review → Approved → Published; Rejected, Needs Revision, Superseded,
--    Withdrawn). Nobody approves their own proposal; company-wide knowledge needs rasa.company; a financial formula needs two
--    approvers and a confirmed regression check; a conflict with published knowledge is resolved before approval. The taught
--    knowledge in the index is rebuilt here from the published proposals, never taken from the browser.
-- Needs schema-update-v49.sql. Additive. Safe to run twice. Undo: schema-rollback-v50.sql.

do $$ begin
  if to_regprocedure('public.crf_features()') is null or to_regprocedure('public.pt_doc_can(uuid,text,text,boolean)') is null
     or to_regprocedure('public.pt_right(uuid,text,boolean)') is null or to_regprocedure('public.pt_screens()') is null then
    raise exception 'Run schema-update-v49.sql (STAGE-43-SETUP) first, then this update'; end if;
end $$;

-- ------------------------------------------------------------------ 1. rights and the screen
do $$
declare cur text[] := pt_rights(); src text; k text; scr text[] := pt_screens();
begin
  foreach k in array array['rasa.teach','rasa.sync','rasa.review','rasa.company'] loop if not (k = any(cur)) then cur := cur || k; end if; end loop;
  execute format('create or replace function pt_rights() returns text[] language sql immutable as $f$ select %L::text[] $f$', cur::text);
  select prosrc into src from pg_proc where proname = 'pt_right_default' and pronamespace = 'public'::regnamespace and pronargs = 2;
  if position('rasa.teach' in src) = 0 then
    if position('else false end' in src) = 0 then raise exception 'pt_right_default does not have the expected shape; add the rasa rights by hand'; end if;
    src := regexp_replace(src, 'else false end', E'when ''rasa.teach''              then base in (''exec'', ''rm'', ''pf'', ''plan'', ''costing'', ''pm'')\n    when ''rasa.sync''               then base in (''plan'', ''costing'')\n    when ''rasa.review''             then false\n    when ''rasa.company''            then false\n    else false end');
    execute format('create or replace function pt_right_default(base text, k text) returns boolean language sql immutable as $f$%s$f$', src);
  end if;
  if not ('rasa' = any(scr)) then scr := scr || 'rasa'; end if;
  execute format('create or replace function pt_screens() returns text[] language sql immutable as $f$ select %L::text[] $f$', scr::text);
end $$;
create or replace function pt_rk_can(u uuid, k text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) = 'sa' or pt_right(u, k, false), false) $$;
-- may person u read a source of this project, access class, document box and approval status?
create or replace function pt_rk_sees(u uuid, pid text, cls text, box text, appr text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(role_of(u) is not null and (pid is null or user_sees(u, pid)) and case
    when cls in ('all','company') then true
    when cls = 'money' then pt_rk_can(u, 'money.view') and role_of(u) <> 'foreman'
    when cls like 'doc:%' then role_of(u) = 'sa' or (role_of(u) <> 'foreman' and pt_doc_can(u, pid, box, false))
    when cls in ('dly','vo') then pt_rk_can(u, 'money.view') and role_of(u) <> 'foreman'
    when cls in ('iss','mat') then role_of(u) <> 'foreman'
    when cls = 'boq' then role_of(u) in ('sa','exec','rm','pf','plan','costing','pm')
    when cls = 'rel' then appr in ('Released','Superseded') or pt_rk_can(u, 'report.internal.prepare') or pt_rk_can(u, 'report.internal.approve')
    else false end, false) $$;

-- ------------------------------------------------------------------ 2. tables
create table if not exists rasa_config (id boolean primary key default true check (id), data jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'), set_by uuid, set_at timestamptz not null default now());
insert into rasa_config (id) values (true) on conflict do nothing;
create table if not exists rasa_sources (
  id text primary key check (length(id) between 3 and 300),
  mod text not null check (mod in ('sched','cost','docs','contract','prod','exec','cash','claims','proc','boq','proj','taught')),
  project_id text references projects(id) on delete cascade,
  cls text not null default 'all' check (cls ~ '^(all|company|money|rel|dly|vo|iss|mat|boq|doc:[a-z]{1,20})$'),
  box text, st text not null check (st in ('Indexed','Failed','Deleted')), appr text not null default 'Recorded' check (length(appr) <= 40),
  hash text, ver int not null default 1, data jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  indexed_by uuid, at_time timestamptz not null default now());
create index if not exists rasa_sources_mod on rasa_sources (mod, project_id);
create table if not exists rasa_chunks (
  source_id text not null references rasa_sources(id) on delete cascade, i int not null check (i between 0 and 999),
  t text not null check (length(t) <= 4000), loc text check (length(loc) <= 200), ids text[] not null default '{}',
  tsv tsvector generated always as (to_tsvector('english', coalesce(t, '') || ' ' || coalesce(array_to_string(ids, ' '), ''))) stored,
  primary key (source_id, i));
create index if not exists rasa_chunks_tsv on rasa_chunks using gin (tsv);
-- ON HOLD (alfanar IT): create extension if not exists vector; alter table rasa_chunks add column embedding vector(1536);
--                       create index on rasa_chunks using hnsw (embedding vector_cosine_ops);
create table if not exists rasa_runs (id bigserial primary key, mod text not null, data jsonb not null default '{}'::jsonb, by_user uuid, at_time timestamptz not null default now());
create table if not exists rasa_proposals (
  id text primary key, kind text not null check (kind in ('correction','rule','gap','note')), scope text not null check (scope in ('project','company')),
  project_id text references projects(id) on delete cascade,
  st text not null check (st in ('Draft','Submitted','Under Review','Approved','Published','Rejected','Needs Revision','Superseded','Withdrawn')),
  author uuid not null, data jsonb not null check (jsonb_typeof(data) = 'object'), at_time timestamptz not null default now(), updated_at timestamptz not null default now(),
  check ((scope = 'company') = (project_id is null)));
create sequence if not exists rasa_prop_seq;
create table if not exists rasa_publications (ver int primary key, prop_id text not null references rasa_proposals(id) on delete cascade, data jsonb not null default '{}'::jsonb, by_user uuid, at_time timestamptz not null default now());
create table if not exists rasa_gaps (id text primary key, key text not null, project_id text references projects(id) on delete cascade, st text not null default 'Open' check (st in ('Open','Resolved')), n int not null default 1, data jsonb not null default '{}'::jsonb, at_time timestamptz not null default now());
create sequence if not exists rasa_gap_seq;
create table if not exists rasa_feedback (id bigserial primary key, question_id text not null, v int not null check (v in (-1, 1)), by_user uuid not null, data jsonb not null default '{}'::jsonb, at_time timestamptz not null default now(), unique (question_id, by_user));
create table if not exists rasa_questions (id text primary key, by_user uuid not null, data jsonb not null check (jsonb_typeof(data) = 'object'), at_time timestamptz not null default now());
create table if not exists rasa_activity (id bigserial primary key, k text not null, project_id text, cls text, box text, data jsonb not null default '{}'::jsonb, by_user uuid, at_time timestamptz not null default now());
alter table rasa_config enable row level security; alter table rasa_sources enable row level security; alter table rasa_chunks enable row level security;
alter table rasa_runs enable row level security; alter table rasa_proposals enable row level security; alter table rasa_publications enable row level security;
alter table rasa_gaps enable row level security; alter table rasa_feedback enable row level security; alter table rasa_questions enable row level security; alter table rasa_activity enable row level security;
drop policy if exists rk_cfg_read on rasa_config; create policy rk_cfg_read on rasa_config for select to authenticated using (true);
drop policy if exists rk_src_read on rasa_sources; create policy rk_src_read on rasa_sources for select to authenticated using (pt_rk_sees(auth.uid(), project_id, cls, box, appr));
drop policy if exists rk_run_read on rasa_runs; create policy rk_run_read on rasa_runs for select to authenticated using (true);
drop policy if exists rk_prop_read on rasa_proposals; create policy rk_prop_read on rasa_proposals for select to authenticated using (project_id is null or user_sees(auth.uid(), project_id));
drop policy if exists rk_pub_read on rasa_publications; create policy rk_pub_read on rasa_publications for select to authenticated using (exists (select 1 from rasa_proposals p where p.id = prop_id and (p.project_id is null or user_sees(auth.uid(), p.project_id))));
drop policy if exists rk_gap_read on rasa_gaps; create policy rk_gap_read on rasa_gaps for select to authenticated using (project_id is null or user_sees(auth.uid(), project_id));
drop policy if exists rk_fb_read on rasa_feedback; create policy rk_fb_read on rasa_feedback for select to authenticated using (by_user = auth.uid() or pt_rk_can(auth.uid(), 'rasa.review'));
drop policy if exists rk_q_read on rasa_questions; create policy rk_q_read on rasa_questions for select to authenticated using (by_user = auth.uid() or (pt_rk_can(auth.uid(), 'rasa.review')
  and not exists (select 1 from jsonb_array_elements_text(coalesce(data -> 'pids', '[]'::jsonb)) x where not user_sees(auth.uid(), x))));
drop policy if exists rk_act_read on rasa_activity; create policy rk_act_read on rasa_activity for select to authenticated using (pt_rk_sees(auth.uid(), project_id, coalesce(cls, 'all'), box, 'Released'));
drop trigger if exists trg_rk_act_append on rasa_activity; create trigger trg_rk_act_append before update or delete on rasa_activity for each row execute function pt_append_only();
drop trigger if exists trg_rk_pub_append on rasa_publications; create trigger trg_rk_pub_append before update or delete on rasa_publications for each row execute function pt_append_only();
revoke all on rasa_config, rasa_sources, rasa_chunks, rasa_runs, rasa_proposals, rasa_publications, rasa_gaps, rasa_feedback, rasa_questions, rasa_activity from anon;
revoke insert, update, delete, truncate on rasa_config, rasa_sources, rasa_chunks, rasa_runs, rasa_proposals, rasa_publications, rasa_gaps, rasa_feedback, rasa_questions, rasa_activity from authenticated;
revoke select on rasa_chunks from authenticated;
grant select on rasa_config, rasa_sources, rasa_runs, rasa_proposals, rasa_publications, rasa_gaps, rasa_feedback, rasa_questions, rasa_activity to authenticated;

-- ------------------------------------------------------------------ 3. helpers
create or replace function pt_rk_log(k text, txt text, pid text, cls text, box text, link jsonb) returns void language sql security definer set search_path = public as $$
  insert into rasa_activity (k, project_id, cls, box, data, by_user) values (k, pid, cls, box, jsonb_build_object('k', k, 'text', left(txt, 300), 'by', name_of(auth.uid()), 'link', link), auth.uid()) $$;
-- the access class a module's sources must carry at least (the browser cannot make a source less protected than its module)
create or replace function pt_rk_cls_ok(m text, pid text, cls text, box text) returns boolean language sql stable security definer set search_path = public as $$
  select case m when 'cost' then cls = 'money' when 'cash' then cls = 'money' when 'contract' then cls = 'money'
    when 'docs' then cls = 'doc:' || coalesce(pt_doc_row(pid, box), '?') when 'claims' then cls in ('dly','vo') when 'exec' then cls = 'rel'
    when 'proc' then cls in ('money','mat') when 'boq' then cls = 'boq' when 'proj' then cls in ('all','iss') when 'sched' then cls = 'all' when 'prod' then cls = 'all'
    else false end $$;
-- the taught knowledge, rebuilt from the published proposals
create or replace function pt_rk_taught() returns void language plpgsql security definer set search_path = public as $$
declare r record; sid text;
begin
  update rasa_sources set st = 'Deleted', at_time = now() where mod = 'taught' and st <> 'Deleted' and substr(id, 11) not in (select id from rasa_proposals where st = 'Published');
  delete from rasa_chunks c using rasa_sources s where s.id = c.source_id and s.mod = 'taught' and s.st = 'Deleted';
  for r in select * from rasa_proposals where st = 'Published' loop
    sid := 'taught:kp:' || r.id;
    insert into rasa_sources (id, mod, project_id, cls, st, appr, hash, ver, data, indexed_by)
    values (sid, 'taught', r.project_id, case when r.scope = 'company' then 'company' else 'all' end, 'Indexed', 'Published', md5(r.data::text), coalesce((r.data ->> 'pubVer')::int, 1),
      jsonb_build_object('rec', 'kp:' || r.id, 'type', case r.kind when 'correction' then 'Correction' when 'rule' then 'Business rule' when 'gap' then 'Knowledge for a gap' else 'Knowledge note' end,
        'title', r.data ->> 'title', 'rev', 'v' || coalesce(r.data ->> 'ver', '1'), 'owner', r.data ->> 'author_name', 'prop', r.id, 'route', jsonb_build_object('rk', 'rev', 'prop', r.id), 'indexed', now(), 'n', 1), auth.uid())
    on conflict (id) do update set st = 'Indexed', appr = 'Published', hash = excluded.hash, data = excluded.data, at_time = now();
    delete from rasa_chunks where source_id = sid;
    insert into rasa_chunks (source_id, i, t, loc, ids) values (sid, 0, left(coalesce(r.data ->> 'title', '') || '. ' || coalesce(r.data ->> 'text', '') ||
      coalesce(' Formula or criteria: ' || (r.data ->> 'formula'), '') || coalesce(' Source: ' || (r.data ->> 'ref'), ''), 4000), 'Published v' || coalesce(r.data ->> 'pubVer', ''),
      coalesce(array(select jsonb_array_elements_text(coalesce(r.data -> 'ids', '[]'::jsonb))), '{}') || r.id);
  end loop;
end $$;

-- ------------------------------------------------------------------ 4. sync and search
-- p: {mod, kind, sources: [{id, rec, pid, cls, box, appr, hash, fail, title, …, chunks: [{i, t, loc, ids}]}], removed: [id], last, error, ms}
create or replace function rasa_sync(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); m text := p ->> 'mod'; s jsonb; c jsonb; pid text; n_add int := 0; n_ch int := 0; n_rm int := 0; n_fail int := 0; prev record; rid text; run jsonb;
begin
  if me is null or role_of(me) is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if m = 'taught' then perform pt_rk_taught(); return jsonb_build_object('ok', true); end if;
  if not pt_rk_can(me, 'rasa.sync') then raise exception 'Only those who keep records refresh RASA''s knowledge' using errcode = '42501'; end if;
  if m not in ('sched','cost','docs','contract','prod','exec','cash','claims','proc','boq','proj') then raise exception 'Unknown module'; end if;
  if m in ('cost','cash','contract') and not pt_rk_can(me, 'money.view') then raise exception 'Cost figures are not available for your role' using errcode = '42501'; end if;
  if coalesce(jsonb_array_length(p -> 'sources'), 0) > 60 then raise exception 'At most 60 sources a call'; end if;
  for s in select * from jsonb_array_elements(coalesce(p -> 'sources', '[]'::jsonb)) loop
    pid := nullif(s ->> 'pid', '');
    if s ->> 'id' is distinct from m || ':' || (s ->> 'rec') then raise exception 'A source id is its module and record'; end if;
    if pid is null or not user_sees(me, pid) then raise exception 'Not your project: %', pid using errcode = '42501'; end if;
    if not pt_rk_cls_ok(m, pid, s ->> 'cls', s ->> 'box') then raise exception 'The access class of % is not the module''s', s ->> 'id'; end if;
    if not pt_rk_sees(me, pid, s ->> 'cls', s ->> 'box', 'Released') then raise exception 'You may not read %', s ->> 'id' using errcode = '42501'; end if;
    if coalesce(jsonb_array_length(s -> 'chunks'), 0) > 400 then raise exception 'At most 400 passages a source'; end if;
    select * into prev from rasa_sources where id = s ->> 'id';
    if nullif(s ->> 'fail', '') is not null then n_fail := n_fail + 1;
      insert into rasa_sources (id, mod, project_id, cls, box, st, appr, hash, ver, data, indexed_by) values (s ->> 'id', m, pid, s ->> 'cls', s ->> 'box', 'Failed', left(coalesce(s ->> 'appr', 'Recorded'), 40), prev.hash, coalesce(prev.ver, 0),
        (s - 'chunks' - 'fail') || jsonb_build_object('err', left(s ->> 'fail', 300), 'synced', now()), me)
      on conflict (id) do update set st = 'Failed', data = excluded.data, at_time = now();
      continue; end if;
    if prev.id is not null and prev.hash = s ->> 'hash' and prev.st = 'Indexed' then continue; end if;
    if prev.id is null or prev.hash is null then n_add := n_add + 1; else n_ch := n_ch + 1; end if;
    insert into rasa_sources (id, mod, project_id, cls, box, st, appr, hash, ver, data, indexed_by)
    values (s ->> 'id', m, pid, s ->> 'cls', s ->> 'box', 'Indexed', left(coalesce(s ->> 'appr', 'Recorded'), 40), s ->> 'hash', coalesce(prev.ver, 0) + 1,
      (s - 'chunks' - 'fail') || jsonb_build_object('n', jsonb_array_length(coalesce(s -> 'chunks', '[]'::jsonb)), 'indexed', now(), 'synced', now(),
        'hist', coalesce(prev.data -> 'hist', '[]'::jsonb) || case when prev.hash is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('ver', prev.ver, 'hash', prev.hash, 'appr', prev.appr, 'at', prev.data ->> 'indexed')) end), me)
    on conflict (id) do update set st = 'Indexed', cls = excluded.cls, box = excluded.box, appr = excluded.appr, hash = excluded.hash, ver = excluded.ver, data = excluded.data, indexed_by = me, at_time = now();
    delete from rasa_chunks where source_id = s ->> 'id';
    for c in select * from jsonb_array_elements(coalesce(s -> 'chunks', '[]'::jsonb)) loop
      insert into rasa_chunks (source_id, i, t, loc, ids) values (s ->> 'id', (c ->> 'i')::int, left(c ->> 't', 4000), left(c ->> 'loc', 200), coalesce(array(select left(x, 80) from jsonb_array_elements_text(coalesce(c -> 'ids', '[]'::jsonb)) x limit 40), '{}'));
    end loop;
  end loop;
  for rid in select jsonb_array_elements_text(coalesce(p -> 'removed', '[]'::jsonb)) loop
    update rasa_sources set st = 'Deleted', at_time = now() where id = rid and mod = m and st <> 'Deleted' and user_sees(me, project_id);
    if found then n_rm := n_rm + 1; delete from rasa_chunks where source_id = rid; end if;
  end loop;
  if coalesce((p ->> 'last')::boolean, true) then
    run := jsonb_build_object('mod', m, 'kind', left(coalesce(p ->> 'kind', 'manual'), 20), 'by', name_of(me), 'added', n_add, 'changed', n_ch, 'removed', n_rm, 'failed', n_fail, 'same', 0, 'ms', coalesce((p ->> 'ms')::int, 0), 'err', left(p ->> 'error', 300));
    insert into rasa_runs (mod, data, by_user) values (m, run, me);
    perform pt_rk_log(case when p ->> 'error' is not null then 'failed' else 'sync' end, m || ': ' || coalesce('the sync failed: ' || (p ->> 'error'), n_add || ' added, ' || n_ch || ' updated, ' || n_rm || ' removed'), null, null, null, null);
  end if;
  return jsonb_build_object('run', run, 'added', n_add, 'changed', n_ch, 'removed', n_rm, 'failed', n_fail);
end $$;
-- p: {q (words), mods, pids, hist}; returns {rows: [passages the asker may open], hidden: number of other matches}
create or replace function rasa_search(p jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); q tsquery; ws text; cfg jsonb := (select data from rasa_config limit 1); rws jsonb; hid int;
begin
  if me is null or role_of(me) is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  select string_agg(w, ' or ') into ws from (select regexp_replace(w, '[^a-z0-9]', ' ', 'g') w from regexp_split_to_table(lower(left(coalesce(p ->> 'q', ''), 500)), '\s+') w limit 20) x where length(btrim(w)) >= 2;
  if ws is null then return jsonb_build_object('rows', '[]'::jsonb, 'hidden', 0); end if;
  q := websearch_to_tsquery('english', ws);
  with m as (
    select c.source_id, c.i, c.t, c.loc, c.ids, s.mod, s.project_id, s.cls, s.box, s.appr, ts_rank(c.tsv, q) r
    from rasa_chunks c join rasa_sources s on s.id = c.source_id
    where c.tsv @@ q and s.st = 'Indexed' and (coalesce((p ->> 'hist')::boolean, false) or s.appr <> 'Superseded')
      and (p -> 'mods' is null or jsonb_typeof(p -> 'mods') <> 'array' or s.mod in (select jsonb_array_elements_text(p -> 'mods')) or (s.mod = 'docs' and s.cls = 'doc:contract' and (p -> 'mods') ? 'contract'))
      and (p -> 'pids' is null or jsonb_typeof(p -> 'pids') <> 'array' or s.project_id is null or s.project_id in (select jsonb_array_elements_text(p -> 'pids')))
      and coalesce((cfg #>> array['mods', s.mod, 'on'])::boolean, true))
  select coalesce(jsonb_agg(jsonb_build_object('source_id', source_id, 'i', i, 't', t, 'loc', loc, 'ids', to_jsonb(ids)) order by r desc) filter (where ok), '[]'::jsonb), count(*) filter (where not ok)
    into rws, hid from (select *, pt_rk_sees(me, project_id, cls, box, appr) ok from m order by r desc limit 200) z;
  return jsonb_build_object('rows', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (select x from jsonb_array_elements(rws) x limit 60) y), 'hidden', hid);
end $$;
create or replace function rasa_passages(p jsonb) returns setof rasa_chunks language sql stable security definer set search_path = public as $$
  select c.* from rasa_chunks c join rasa_sources s on s.id = c.source_id where c.source_id = p ->> 'source_id' and s.st = 'Indexed' and pt_rk_sees(auth.uid(), s.project_id, s.cls, s.box, s.appr) order by c.i limit 400 $$;
create or replace function rasa_features() returns jsonb language sql stable as $$ select jsonb_build_object('version', 50, 'rasa', true, 'vector_search', false, 'server_llm', false) $$;

-- ------------------------------------------------------------------ 5. questions, gaps, feedback, teaching, review, settings
-- p: {op: 'question' | 'feedback' | 'gap' | 'prop_save' | 'prop' | 'settings', …}
create or replace function rasa_act(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); op text := p ->> 'op'; r record; d jsonb; pid text; nid text; a text := p ->> 'a'; note text := btrim(coalesce(p ->> 'note', ''));
  rev boolean; own boolean; need int; cfg jsonb := (select data from rasa_config limit 1); v int; g record; x jsonb; conf jsonb;
begin
  if me is null or role_of(me) is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if op = 'question' then
    d := p -> 'q';
    if exists (select 1 from jsonb_array_elements_text(coalesce(d -> 'pids', '[]'::jsonb)) z where not user_sees(me, z)) then raise exception 'Not your project' using errcode = '42501'; end if;
    insert into rasa_questions (id, by_user, data) values (left(d ->> 'id', 40), me, (d - 'by' - 'at') || jsonb_build_object('by_name', name_of(me), 'q', left(d ->> 'q', 500))) on conflict (id) do nothing;
    if p -> 'gap' is not null and jsonb_typeof(p -> 'gap') = 'object' then
      pid := nullif(p #>> '{gap,pid}', '');
      if pid is not null and not user_sees(me, pid) then raise exception 'Not your project' using errcode = '42501'; end if;
      update rasa_gaps set n = n + 1, data = data || jsonb_build_object('last', now(), 'qids', coalesce(data -> 'qids', '[]'::jsonb) || to_jsonb(d ->> 'id'))
        where key = left(p #>> '{gap,key}', 300) || '|' || coalesce(pid, '') and st = 'Open';
      if not found then
        nid := 'GAP-' || lpad(nextval('rasa_gap_seq')::text, 5, '0');
        insert into rasa_gaps (id, key, project_id, data) values (nid, left(p #>> '{gap,key}', 300) || '|' || coalesce(pid, ''), pid,
          jsonb_build_object('q', left(d ->> 'q', 500), 'mod', p #>> '{gap,mod}', 'why', p #>> '{gap,why}', 'at', now(), 'last', now(), 'by', name_of(me), 'qids', jsonb_build_array(d ->> 'id')));
        perform pt_rk_log('gap', 'New unanswered question: "' || left(d ->> 'q', 120) || '"', pid, null, null, jsonb_build_object('gap', nid));
      end if;
    end if;
    return jsonb_build_object('ok', true);
  elsif op = 'feedback' then
    if not exists (select 1 from rasa_questions where id = p ->> 'qid' and (by_user = me or pt_rk_can(me, 'rasa.review'))) then raise exception 'That answer is no longer in the log'; end if;
    v := (p ->> 'v')::int; if v not in (-1, 1) then raise exception 'Helpful or not helpful'; end if;
    insert into rasa_feedback (question_id, v, by_user, data) values (p ->> 'qid', v, me, jsonb_build_object('note', left(p ->> 'note', 1000), 'by_name', name_of(me)))
    on conflict (question_id, by_user) do update set v = excluded.v, data = excluded.data, at_time = now();
    if v < 0 then perform pt_rk_log('feedback', 'Answer marked not helpful', null, null, null, null); end if;
    return jsonb_build_object('ok', true);
  elsif op = 'gap' then
    select * into g from rasa_gaps where id = p ->> 'id';
    if g.id is null or (g.project_id is not null and not user_sees(me, g.project_id)) then raise exception 'Unknown gap'; end if;
    if a = 'resolve' then
      if not (pt_rk_can(me, 'rasa.teach') or pt_rk_can(me, 'rasa.review')) then raise exception 'Only those who teach or review RASA resolve gaps' using errcode = '42501'; end if;
      update rasa_gaps set st = 'Resolved', data = data || jsonb_build_object('res', coalesce(nullif(note, ''), 'Resolved'), 'res_by', name_of(me), 'res_at', now()) where id = g.id;
    elsif a = 'reopen' then update rasa_gaps set st = 'Open', data = data - 'res' where id = g.id;
    elsif a = 'review' then update rasa_gaps set data = data || jsonb_build_object('review', true, 'review_by', name_of(me)) where id = g.id;
      perform pt_rk_log('gap', 'Expert review requested: "' || left(g.data ->> 'q', 100) || '"', g.project_id, null, null, jsonb_build_object('gap', g.id));
    else raise exception 'Unknown action'; end if;
    return jsonb_build_object('ok', true);
  elsif op = 'prop_save' then
    if not pt_rk_can(me, 'rasa.teach') then raise exception 'Teaching RASA is for those with the right to teach it' using errcode = '42501'; end if;
    d := p -> 'p';
    if coalesce(d ->> 'kind', '') not in ('correction','rule','gap','note') then raise exception 'Choose what you are teaching'; end if;
    if length(btrim(coalesce(d ->> 'title', ''))) not between 3 and 160 then raise exception 'Give it a title of 3 to 160 characters'; end if;
    if length(btrim(coalesce(d ->> 'text', ''))) not between 10 and 4000 then raise exception 'Write the knowledge (10 to 4000 characters)'; end if;
    if coalesce(d ->> 'scope', '') not in ('project','company') then raise exception 'Choose project or company-wide'; end if;
    pid := case when d ->> 'scope' = 'company' then null else nullif(d ->> 'pid', '') end;
    if d ->> 'scope' = 'project' and (pid is null or not user_sees(me, pid)) then raise exception 'Choose one of your projects'; end if;
    if d ->> 'kind' = 'correction' and (length(btrim(coalesce(d ->> 'old', ''))) < 3 or length(btrim(coalesce(d ->> 'why', ''))) < 3) then raise exception 'Quote the incorrect statement and say why it is wrong'; end if;
    if d ->> 'kind' = 'rule' and (coalesce(d ->> 'mod', '') = '' or length(btrim(coalesce(d ->> 'purpose', ''))) < 3) then raise exception 'A business rule needs its module and business purpose'; end if;
    if coalesce((d ->> 'fin')::boolean, false) and d ->> 'kind' <> 'rule' then raise exception 'Only a business rule can be a financial formula'; end if;
    d := (d - 'id' - 'st' - 'author' - 'approvals' - 'hist' - 'pubVer') || jsonb_build_object('pid', pid, 'fin', coalesce((d ->> 'fin')::boolean, false));
    if nullif(p #>> '{p,id}', '') is not null then
      select * into r from rasa_proposals where id = p #>> '{p,id}';
      if r.id is null then raise exception 'Unknown proposal'; end if;
      if r.author <> me then raise exception 'Only its author changes a proposal'; end if;
      if r.st not in ('Draft','Needs Revision') then raise exception 'A proposal that is % cannot be changed', r.st; end if;
      update rasa_proposals set kind = d ->> 'kind', scope = d ->> 'scope', project_id = pid, updated_at = now(),
        data = r.data || d || jsonb_build_object('ver', coalesce((r.data ->> 'ver')::int, 1) + 1, 'hist', coalesce(r.data -> 'hist', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('st', r.st, 'a', 'Changed', 'by', name_of(me), 'at', now())))
        where id = r.id;
      nid := r.id;
    else
      nid := 'KP-' || lpad(nextval('rasa_prop_seq')::text, 5, '0');
      insert into rasa_proposals (id, kind, scope, project_id, st, author, data) values (nid, d ->> 'kind', d ->> 'scope', pid, 'Draft', me,
        d || jsonb_build_object('id', nid, 'ver', 1, 'author', me, 'author_name', name_of(me), 'at', now(), 'approvals', '[]'::jsonb, 'conflicts', '[]'::jsonb, 'hist', jsonb_build_array(jsonb_build_object('st', 'Draft', 'a', 'Created', 'by', name_of(me), 'at', now()))));
      perform pt_rk_log('proposal', 'Drafted: ' || (d ->> 'title'), pid, null, null, jsonb_build_object('prop', nid));
    end if;
    if coalesce((p ->> 'submit')::boolean, false) then return rasa_act(jsonb_build_object('op', 'prop', 'id', nid, 'a', 'submit')); end if;
    return jsonb_build_object('id', nid);
  elsif op = 'prop' then
    select * into r from rasa_proposals where id = p ->> 'id' for update;
    if r.id is null or (r.project_id is not null and not user_sees(me, r.project_id)) then raise exception 'Unknown proposal'; end if;
    own := r.author = me; rev := pt_rk_can(me, 'rasa.review') and (r.scope <> 'company' or pt_rk_can(me, 'rasa.company'));
    d := r.data;
    if a = 'submit' then
      if not own then raise exception 'Only its author submits a proposal'; end if;
      if r.st not in ('Draft','Needs Revision') then raise exception 'A proposal that is % cannot be submitted', r.st; end if;
      select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'title', o.data ->> 'title', 'scope', o.scope, 'why', 'Same title')), '[]'::jsonb) into conf from rasa_proposals o
        where o.id <> r.id and o.st = 'Published' and lower(btrim(o.data ->> 'title')) = lower(btrim(r.data ->> 'title')) and (o.scope = 'company' or o.project_id = r.project_id);
      d := d || jsonb_build_object('conflicts', conf, 'res', null, 'approvals', '[]'::jsonb); r.st := 'Submitted';
    elsif a = 'withdraw' then
      if not (own or rev) then raise exception 'Only its author or a reviewer withdraws a proposal'; end if;
      if r.st not in ('Draft','Submitted','Under Review','Needs Revision','Approved') then raise exception 'A published proposal is rolled back, not withdrawn'; end if; r.st := 'Withdrawn';
    elsif a = 'take' then
      if not rev then raise exception 'Only a knowledge reviewer of the project reviews proposals (company-wide knowledge: its designated approvers)' using errcode = '42501'; end if;
      if own then raise exception 'You cannot review your own proposal'; end if;
      if r.st <> 'Submitted' then raise exception 'Only a submitted proposal is taken for review'; end if;
      d := d || jsonb_build_object('rev_by', name_of(me), 'rev_id', me); r.st := 'Under Review';
    elsif a = 'resolve' then
      if not rev or own or r.st <> 'Under Review' then raise exception 'Only a reviewer resolves conflicts, during the review'; end if;
      if note not in ('replace','keep') then raise exception 'Replace the conflicting knowledge or keep both'; end if; d := d || jsonb_build_object('res', note);
    elsif a in ('revise','reject') then
      if not rev or own then raise exception 'Only a reviewer other than the author decides'; end if;
      if r.st not in ('Submitted','Under Review') then raise exception 'A proposal that is % cannot be returned or rejected', r.st; end if;
      if length(note) < 3 then raise exception 'Say why'; end if;
      r.st := case when a = 'reject' then 'Rejected' else 'Needs Revision' end;
    elsif a = 'approve' then
      if not rev then raise exception 'Only a knowledge reviewer approves (company-wide knowledge: its designated approvers)' using errcode = '42501'; end if;
      if own then raise exception 'You cannot approve your own proposal'; end if;
      if r.st <> 'Under Review' then raise exception 'Take the proposal for review first'; end if;
      if jsonb_array_length(coalesce(d -> 'conflicts', '[]'::jsonb)) > 0 and d ->> 'res' is null then raise exception 'Resolve the conflict with the published knowledge first'; end if;
      if exists (select 1 from jsonb_array_elements(coalesce(d -> 'approvals', '[]'::jsonb)) z where z ->> 'id' = me::text) then raise exception 'You have approved it already; it needs another approver'; end if;
      if coalesce((d ->> 'fin')::boolean, false) and not coalesce((p ->> 'regress')::boolean, false) then raise exception 'A financial formula needs the regression check confirmed'; end if;
      need := case when coalesce((d ->> 'fin')::boolean, false) then greatest(2, coalesce((cfg #>> '{pol,fin}')::int, 2)) else greatest(1, coalesce((cfg #>> array['pol', r.kind])::int, 1)) end;
      d := d || jsonb_build_object('approvals', coalesce(d -> 'approvals', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('id', me, 'by', name_of(me), 'at', now(), 'regress', coalesce((p ->> 'regress')::boolean, false))));
      if jsonb_array_length(d -> 'approvals') >= need then r.st := 'Approved'; d := d || jsonb_build_object('decision', 'Approved'); end if;
    elsif a = 'publish' then
      if not rev then raise exception 'Only a knowledge reviewer publishes' using errcode = '42501'; end if;
      if r.st <> 'Approved' then raise exception 'Only approved knowledge is published'; end if;
      v := coalesce((select max(ver) from rasa_publications), 0) + 1;
      if d ->> 'res' = 'replace' then
        for x in select * from jsonb_array_elements(coalesce(d -> 'conflicts', '[]'::jsonb)) loop
          update rasa_proposals set st = 'Superseded', updated_at = now(), data = data || jsonb_build_object('by_prop', r.id, 'hist', data -> 'hist' || jsonb_build_array(jsonb_build_object('st', 'Superseded', 'a', 'Replaced by ' || r.id, 'by', name_of(me), 'at', now())))
            where id = x ->> 'id' and st = 'Published';
          if found then d := d || jsonb_build_object('replaced', coalesce(d -> 'replaced', '[]'::jsonb) || to_jsonb(x ->> 'id')); end if;
        end loop;
      end if;
      d := d || jsonb_build_object('pubVer', v, 'pubAt', now(), 'pub_by', name_of(me)); r.st := 'Published';
      insert into rasa_publications (ver, prop_id, data, by_user) values (v, r.id, jsonb_build_object('op', 'publish', 'replaced', coalesce(d -> 'replaced', '[]'::jsonb), 'by', name_of(me)), me);
      if d ->> 'gap' is not null then update rasa_gaps set st = 'Resolved', data = data || jsonb_build_object('res', 'Answered by published knowledge ' || r.id, 'res_by', name_of(me), 'res_at', now()) where id = d ->> 'gap' and st = 'Open'; end if;
    elsif a = 'unpublish' then
      if not rev then raise exception 'Only a knowledge reviewer rolls back a publication' using errcode = '42501'; end if;
      if r.st <> 'Published' then raise exception 'Only published knowledge is rolled back'; end if;
      if length(note) < 3 then raise exception 'Say why it is rolled back'; end if;
      v := coalesce((select max(ver) from rasa_publications), 0) + 1;
      update rasa_proposals set st = 'Published', updated_at = now(), data = data || jsonb_build_object('hist', data -> 'hist' || jsonb_build_array(jsonb_build_object('st', 'Published', 'a', 'Restored: ' || r.id || ' rolled back', 'by', name_of(me), 'at', now())))
        where id in (select jsonb_array_elements_text(coalesce(d -> 'replaced', '[]'::jsonb))) and st = 'Superseded';
      insert into rasa_publications (ver, prop_id, data, by_user) values (v, r.id, jsonb_build_object('op', 'rollback', 'restored', coalesce(d -> 'replaced', '[]'::jsonb), 'by', name_of(me), 'note', left(note, 1000)), me);
      r.st := 'Withdrawn';
    else raise exception 'Unknown action'; end if;
    d := d || jsonb_build_object('hist', coalesce(d -> 'hist', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('st', r.st, 'a', a, 'by', name_of(me), 'at', now(), 'note', nullif(left(note, 1000), ''))));
    update rasa_proposals set st = r.st, data = d, updated_at = now() where id = r.id;
    if a in ('submit','approve','publish','unpublish','reject','revise') then
      perform pt_rk_log(case a when 'publish' then 'published' when 'unpublish' then 'withdrawn' when 'approve' then 'approved' else 'proposal' end, initcap(a) || ': ' || (d ->> 'title'), r.project_id, null, null, jsonb_build_object('prop', r.id)); end if;
    if a in ('publish','unpublish') then perform pt_rk_taught(); end if;
    return jsonb_build_object('id', r.id, 'st', r.st);
  elsif op = 'settings' then
    if role_of(me) <> 'sa' then raise exception 'Only the super admin changes RASA settings' using errcode = '42501'; end if;
    d := p -> 'cfg';
    if coalesce((d ->> 'keep')::int, 0) not between 30 and 730 then raise exception 'Keep questions 30 to 730 days'; end if;
    if coalesce((d #>> '{pol,fin}')::int, 0) not between 2 and 3 then raise exception 'A financial formula needs 2 or 3 approvals'; end if;
    update rasa_config set data = d, set_by = me, set_at = now();
    delete from rasa_questions where at_time < now() - make_interval(days => (d ->> 'keep')::int);
    delete from rasa_feedback where at_time < now() - make_interval(days => (d ->> 'keep')::int);
    perform pt_rk_log('settings', 'RASA settings changed', null, null, null, null);
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'Unknown operation';
end $$;

revoke execute on function rasa_sync(jsonb), rasa_search(jsonb), rasa_passages(jsonb), rasa_act(jsonb), rasa_features(), pt_rk_can(uuid,text), pt_rk_sees(uuid,text,text,text,text),
  pt_rk_log(text,text,text,text,text,jsonb), pt_rk_cls_ok(text,text,text,text), pt_rk_taught() from public, anon;
grant execute on function rasa_sync(jsonb), rasa_search(jsonb), rasa_passages(jsonb), rasa_act(jsonb), rasa_features() to authenticated;
