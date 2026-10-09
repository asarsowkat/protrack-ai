-- ProTrack production schema for Supabase (PostgreSQL)
-- Run once in Supabase → SQL Editor → New query → Run.
-- Every table has row level security, so a user can only reach the projects
-- their access record allows. Nothing relies on the client behaving well.

create extension if not exists "uuid-ossp";

-- ---------------------------------------------------------------- people
create type user_role as enum
  ('sa','exec','rm','pf','plan','pm','eng','foreman','ro','costing');

create table profiles (
  id          uuid primary key references auth.users on delete cascade,
  name        text not null,
  title       text,
  role        user_role not null default 'ro',
  active      boolean not null default true,
  created_at  timestamptz default now()
);

create table regions (
  id text primary key, name text not null, manager uuid references profiles(id));

create table sectors (
  id text primary key, name text not null);

create table cities (
  id text primary key, name text not null, region text references regions(id));

-- ------------------------------------------------------------- projects
create table projects (
  id          text primary key,                  -- any format: PE-329, EL-000
  name        text not null,
  short       text not null,
  sector      text references sectors(id),
  region      text references regions(id),
  city        text references cities(id),
  ptype       text,
  start_date  date, finish_date date,
  value_m     numeric,
  status      text default 'Active',
  mh_source   text default 'Costing file',
  billing     jsonb default '{}'::jsonb,         -- phase caps, releases, retention, advance
  eot         jsonb default '{}'::jsonb,
  created_at  timestamptz default now()
);

create table project_access (                    -- who may see what
  user_id    uuid references profiles(id) on delete cascade,
  project_id text references projects(id) on delete cascade,
  primary key (user_id, project_id));

create table region_access (                     -- regional and portfolio managers
  user_id   uuid references profiles(id) on delete cascade,
  region_id text references regions(id) on delete cascade,
  primary key (user_id, region_id));

create table project_team (
  project_id text references projects(id) on delete cascade,
  user_id    uuid references profiles(id) on delete cascade,
  team_role  text,                               -- pm | eng | foreman
  primary key (project_id, user_id, team_role));

create table milestones (
  id uuid primary key default uuid_generate_v4(),
  project_id text references projects(id) on delete cascade,
  name text not null, ms_type text,              -- Start | Intermediate | TCC | PAC | FAC
  planned date, forecast date, actual date);

-- ----------------------------------------------------------- activities
create table activities (
  id            text not null,
  project_id    text not null references projects(id) on delete cascade,
  name          text not null,
  cls           text not null default 'CON',     -- CON | ENG | PRC
  disc          text, area text, wbs text,
  uom           text, qty numeric,
  budget_mh     numeric, p6_mh numeric, costing_mh numeric,
  budget_rate   numeric, budget_cost numeric,    -- from the costing file
  price_weight  numeric,                         -- from the P6 weighting resource
  trade_mix     jsonb default '{}'::jsonb,       -- {"Helper":120,"Steel Fixer":160}
  bs date, bf date, prior_qty numeric default 0,
  gang text, costed boolean default false,
  cur           jsonb default '{}'::jsonb,       -- ENG/PRC milestone state
  primary key (project_id, id));

create table baseline_sets (                     -- revised and recovery, dates only
  project_id text references projects(id) on delete cascade,
  set_code   text not null,                      -- REV | REC
  loaded_by  uuid references profiles(id), loaded_at timestamptz default now(),
  file_name  text, rows jsonb not null,
  primary key (project_id, set_code));

create table baseline_history (                  -- snapshot before each import, for undo
  id uuid primary key default uuid_generate_v4(),
  project_id text references projects(id) on delete cascade,
  taken_by uuid references profiles(id), taken_at timestamptz default now(),
  file_name text, activities jsonb not null);

-- -------------------------------------------------------- daily reports
create type dpr_status as enum ('Draft','Submitted','Reviewed','Approved','Rejected');

create table dprs (
  id          text primary key,                  -- DPR-0001
  project_id  text not null references projects(id) on delete cascade,
  report_date date not null,
  foreman     text, site_engineer text,
  status      dpr_status not null default 'Draft',
  remarks     text,
  created_by  uuid references profiles(id), created_at timestamptz default now(),
  updated_at  timestamptz default now(),
  unique (project_id, report_date, foreman));

create table dpr_lines (
  id uuid primary key default uuid_generate_v4(),
  dpr_id text references dprs(id) on delete cascade,
  activity_id text not null,
  qty numeric default 0,
  labour jsonb default '[]'::jsonb,              -- [{cat,count,reg,ot}]
  subs   jsonb default '[]'::jsonb,              -- [{sub,cat,count,hours,qty}]
  equip  jsonb default '[]'::jsonb);

create table dpr_audit (
  id uuid primary key default uuid_generate_v4(),
  dpr_id text references dprs(id) on delete cascade,
  action text not null, note text,
  by_user uuid references profiles(id), at_time timestamptz default now());

create table attachments (
  id uuid primary key default uuid_generate_v4(),
  dpr_id text references dprs(id) on delete cascade,
  storage_path text not null, caption text,
  uploaded_by uuid references profiles(id), uploaded_at timestamptz default now());

-- ------------------------------------------------- rates and commercial
create table trades (
  name text primary key, active boolean default true);

create table trade_rates (                       -- dated, never restated
  id uuid primary key default uuid_generate_v4(),
  trade text references trades(name) on delete cascade,
  from_date date not null, monthly numeric, hours int default 208,
  factor numeric default 2.5, hourly numeric not null,
  note text, set_by uuid references profiles(id), set_at timestamptz default now(),
  unique (trade, from_date));

create table subcontractors (
  id text primary key, name text not null, code text, contact text);

create table purchase_orders (
  id uuid primary key default uuid_generate_v4(),
  sub_id text references subcontractors(id) on delete cascade,
  project_id text references projects(id) on delete cascade,
  po_no text not null, po_type text not null,    -- Measured | Manpower supply
  po_date date, po_value numeric,
  unique (sub_id, project_id));

create table po_rates (
  id uuid primary key default uuid_generate_v4(),
  po_id uuid references purchase_orders(id) on delete cascade,
  rate_key text not null,                        -- activity id, or trade name
  unit text, rate numeric not null, from_date date not null,
  unique (po_id, rate_key, from_date));

-- ------------------------------------------------- weekly and audit log
create table weekly_updates (
  id uuid primary key default uuid_generate_v4(),
  project_id text references projects(id) on delete cascade,
  data_date date not null, file_name text,
  rows jsonb not null,
  applied_by uuid references profiles(id), applied_at timestamptz default now());

create table change_log (
  id bigserial primary key,
  project_id text references projects(id) on delete set null,
  text text not null,
  by_user uuid references profiles(id), at_time timestamptz default now());

-- =================================================================
--  Row level security
-- =================================================================
create or replace function my_role() returns user_role
language sql stable security definer as $$
  select role from profiles where id = auth.uid() and active $$;

create or replace function can_see(p text) returns boolean
language sql stable security definer as $$
  select case
    when (select role from profiles where id = auth.uid() and active) in ('sa','exec') then true
    when exists (select 1 from project_access a where a.user_id = auth.uid() and a.project_id = p) then true
    when exists (select 1 from region_access r join projects pr on pr.region = r.region_id
                 where r.user_id = auth.uid() and pr.id = p) then true
    else false end $$;

create or replace function can_edit_dpr(p text) returns boolean
language sql stable security definer as $$
  select can_see(p) and (select role from profiles where id = auth.uid())
         in ('sa','pm','eng','foreman') $$;

create or replace function can_approve(p text) returns boolean
language sql stable security definer as $$
  select can_see(p) and (select role from profiles where id = auth.uid()) in ('sa','pm') $$;

create or replace function can_plan(p text) returns boolean
language sql stable security definer as $$
  select can_see(p) and (select role from profiles where id = auth.uid()) in ('sa','plan') $$;

create or replace function can_cost(p text) returns boolean
language sql stable security definer as $$
  select can_see(p) and (select role from profiles where id = auth.uid()) in ('sa','costing') $$;

alter table profiles        enable row level security;
alter table projects        enable row level security;
alter table project_access  enable row level security;
alter table region_access   enable row level security;
alter table project_team    enable row level security;
alter table milestones      enable row level security;
alter table activities      enable row level security;
alter table baseline_sets   enable row level security;
alter table baseline_history enable row level security;
alter table dprs            enable row level security;
alter table dpr_lines       enable row level security;
alter table dpr_audit       enable row level security;
alter table attachments     enable row level security;
alter table trades          enable row level security;
alter table trade_rates     enable row level security;
alter table subcontractors  enable row level security;
alter table purchase_orders enable row level security;
alter table po_rates        enable row level security;
alter table weekly_updates  enable row level security;
alter table change_log      enable row level security;
alter table regions enable row level security;
alter table sectors enable row level security;
alter table cities  enable row level security;

-- everyone signed in reads their own profile; super admin manages all
create policy p_self   on profiles for select using (id = auth.uid() or my_role() = 'sa');
create policy p_admin  on profiles for all    using (my_role() = 'sa') with check (my_role() = 'sa');

-- master data: read for all, write for super admin
create policy m_read_r on regions for select using (auth.uid() is not null);
create policy m_write_r on regions for all using (my_role()='sa') with check (my_role()='sa');
create policy m_read_s on sectors for select using (auth.uid() is not null);
create policy m_write_s on sectors for all using (my_role()='sa') with check (my_role()='sa');
create policy m_read_c on cities  for select using (auth.uid() is not null);
create policy m_write_c on cities  for all using (my_role()='sa') with check (my_role()='sa');
create policy m_read_t on trades  for select using (auth.uid() is not null);
create policy m_write_t on trades  for all using (my_role()='sa') with check (my_role()='sa');
create policy m_read_tr on trade_rates for select using (auth.uid() is not null);
create policy m_write_tr on trade_rates for all using (my_role() in ('sa','costing')) with check (my_role() in ('sa','costing'));
create policy m_read_sub on subcontractors for select using (auth.uid() is not null);
create policy m_write_sub on subcontractors for all using (my_role() in ('sa','costing')) with check (my_role() in ('sa','costing'));

-- projects and everything hanging off them
create policy pr_read  on projects for select using (can_see(id));
create policy pr_write on projects for all using (my_role()='sa') with check (my_role()='sa');

create policy ac_read  on activities for select using (can_see(project_id));
create policy ac_plan  on activities for all using (can_plan(project_id) or can_cost(project_id))
                                     with check (can_plan(project_id) or can_cost(project_id));

create policy ms_read  on milestones for select using (can_see(project_id));
create policy ms_write on milestones for all using (can_plan(project_id)) with check (can_plan(project_id));

create policy bs_read  on baseline_sets for select using (can_see(project_id));
create policy bs_write on baseline_sets for all using (can_plan(project_id)) with check (can_plan(project_id));
create policy bh_read  on baseline_history for select using (can_see(project_id));
create policy bh_write on baseline_history for all using (can_plan(project_id)) with check (can_plan(project_id));

create policy d_read   on dprs for select using (can_see(project_id));
create policy d_insert on dprs for insert with check (can_edit_dpr(project_id));
create policy d_update on dprs for update using (
  (can_edit_dpr(project_id) and status in ('Draft','Submitted','Rejected')) or can_approve(project_id));

create policy dl_read  on dpr_lines for select using (exists (select 1 from dprs d where d.id=dpr_id and can_see(d.project_id)));
create policy dl_write on dpr_lines for all using (exists (select 1 from dprs d where d.id=dpr_id and can_edit_dpr(d.project_id)))
                                    with check (exists (select 1 from dprs d where d.id=dpr_id and can_edit_dpr(d.project_id)));

create policy da_read  on dpr_audit for select using (exists (select 1 from dprs d where d.id=dpr_id and can_see(d.project_id)));
create policy da_write on dpr_audit for insert with check (exists (select 1 from dprs d where d.id=dpr_id and can_see(d.project_id)));

create policy at_read  on attachments for select using (exists (select 1 from dprs d where d.id=dpr_id and can_see(d.project_id)));
create policy at_write on attachments for all using (exists (select 1 from dprs d where d.id=dpr_id and can_edit_dpr(d.project_id)))
                                      with check (exists (select 1 from dprs d where d.id=dpr_id and can_edit_dpr(d.project_id)));

create policy po_read  on purchase_orders for select using (can_see(project_id));
create policy po_write on purchase_orders for all using (can_cost(project_id) or my_role()='sa')
                                          with check (can_cost(project_id) or my_role()='sa');
create policy por_read on po_rates for select using (exists (select 1 from purchase_orders o where o.id=po_id and can_see(o.project_id)));
create policy por_write on po_rates for all using (my_role() in ('sa','costing')) with check (my_role() in ('sa','costing'));

create policy wu_read  on weekly_updates for select using (can_see(project_id));
create policy wu_write on weekly_updates for all using (can_plan(project_id)) with check (can_plan(project_id));

create policy cl_read  on change_log for select using (project_id is null or can_see(project_id));
create policy cl_write on change_log for insert with check (auth.uid() is not null);

create policy pa_read  on project_access for select using (user_id = auth.uid() or my_role()='sa');
create policy pa_write on project_access for all using (my_role()='sa') with check (my_role()='sa');
create policy ra_read  on region_access for select using (user_id = auth.uid() or my_role()='sa');
create policy ra_write on region_access for all using (my_role()='sa') with check (my_role()='sa');
create policy pt_read  on project_team for select using (can_see(project_id));
create policy pt_write on project_team for all using (my_role()='sa') with check (my_role()='sa');

-- helpful indexes
create index on activities (project_id, cls);
create index on dprs (project_id, report_date);
create index on dpr_lines (dpr_id, activity_id);
create index on change_log (at_time desc);
