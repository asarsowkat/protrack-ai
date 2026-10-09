-- ProTrack schema update v3
-- For: Site Manager role, approval matrix per project, report timers,
-- approval email log, role access for site roles, project managers on costing.
-- Run AFTER schema.sql and schema-update-v2.sql. Safe to run more than once.
-- Supabase → SQL Editor → New query → paste → Run.

-- 1. The Site Manager role --------------------------------------------------
alter type user_role add value if not exists 'sm';
-- (functions below compare role as text, so this works in the same run)

-- 2. Permissions: who may edit, review, approve, cost ----------------------
create or replace function my_role_text() returns text
language sql stable security definer as $$
  select role::text from profiles where id = auth.uid() and active $$;

create or replace function can_edit_dpr(p text) returns boolean
language sql stable security definer as $$
  select can_see(p) and my_role_text() in ('sa','pm','sm','eng','foreman') $$;

create or replace function can_approve(p text) returns boolean
language sql stable security definer as $$
  select can_see(p) and my_role_text() in ('sa','pm','sm') $$;

create or replace function can_review(p text) returns boolean
language sql stable security definer as $$
  select can_see(p) and my_role_text() in ('sa','pm','sm','eng') $$;

-- project managers now keep costing, invoices and purchase orders for their projects
create or replace function can_cost(p text) returns boolean
language sql stable security definer as $$
  select can_see(p) and my_role_text() in ('sa','costing','pm') $$;

-- 3. Approval matrix: per project, foreman → site engineer, site engineer → site manager
create table if not exists approval_matrix (
  project_id text not null references projects(id) on delete cascade,
  kind       text not null check (kind in ('fm','eng')),   -- fm: foreman→engineer, eng: engineer→site manager
  from_user  uuid not null references profiles(id) on delete cascade,
  to_user    uuid not null references profiles(id) on delete cascade,
  set_by     uuid references profiles(id), set_at timestamptz default now(),
  primary key (project_id, kind, from_user));
alter table approval_matrix enable row level security;
drop policy if exists am_read  on approval_matrix;
drop policy if exists am_write on approval_matrix;
create policy am_read  on approval_matrix for select using (can_see(project_id));
create policy am_write on approval_matrix for all
  using (my_role_text() = 'sa') with check (my_role_text() = 'sa');

-- 4. Timers and email marker on each daily report --------------------------
alter table dprs add column if not exists timing jsonb default '{}'::jsonb;   -- {create,review,approve:{secs,by,role,sessions,at}}
alter table dprs add column if not exists mailed jsonb;                       -- {id,n,at}

-- 5. Role access for site roles --------------------------------------------
create table if not exists role_config (
  role       text primary key,               -- 'eng' | 'sm'
  reports    text[] not null default '{}',   -- report ids the role may open
  exec_layout jsonb not null default '{}'::jsonb,
  updated_by uuid references profiles(id), updated_at timestamptz default now());
alter table role_config enable row level security;
drop policy if exists rc_read  on role_config;
drop policy if exists rc_write on role_config;
create policy rc_read  on role_config for select using (auth.uid() is not null);
create policy rc_write on role_config for all using (my_role_text() = 'sa') with check (my_role_text() = 'sa');
insert into role_config (role, reports, exec_layout) values
  ('eng', '{actprog,projprog,prod,histo,warn}',
   '{"kpis":["projects","complete","spi","prod","heads","crit"],"group":"project","cols":["bar","spi","prod","crit"]}'),
  ('sm',  '{actprog,projprog,regprog,prod,histo,recon,warn,timing}',
   '{"kpis":["projects","complete","spi","prod","heads","crit","warn"],"group":"project","cols":["bar","spi","prod","crit"]}')
on conflict (role) do nothing;

-- 6. Approval email settings and log ----------------------------------------
create table if not exists mail_config (
  id int primary key default 1 check (id = 1),
  enabled    boolean not null default true,
  roles      text[] not null default '{eng,sm,pm,pf,plan,costing,exec,sa}',
  chain_only boolean not null default true,     -- site roles only for reports they review or approve
  updated_at timestamptz default now());
insert into mail_config (id) values (1) on conflict (id) do nothing;
alter table mail_config enable row level security;
drop policy if exists mc_read  on mail_config;
drop policy if exists mc_write on mail_config;
create policy mc_read  on mail_config for select using (auth.uid() is not null);
create policy mc_write on mail_config for update using (my_role_text() = 'sa') with check (my_role_text() = 'sa');

create table if not exists mail_log (
  id uuid primary key default uuid_generate_v4(),
  dpr_id text references dprs(id) on delete set null,
  project_id text references projects(id) on delete cascade,
  subject text, recipients jsonb, status text,
  sent_by uuid references profiles(id), sent_at timestamptz default now());
alter table mail_log enable row level security;
drop policy if exists ml_read  on mail_log;
drop policy if exists ml_write on mail_log;
create policy ml_read  on mail_log for select using (can_see(project_id));
create policy ml_write on mail_log for insert with check (can_approve(project_id));

create index if not exists mail_log_proj on mail_log (project_id, sent_at desc);
create index if not exists am_to on approval_matrix (project_id, to_user);
