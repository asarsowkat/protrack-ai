-- ProTrack schema update v2
-- Adds the tables for the features built since schema.sql:
-- invoice register, upload histories, DCMA results, reporting reminders and
-- per-person dashboard layouts. Safe to run more than once.
-- Supabase → SQL Editor → New query → paste → Run.

-- the costing role is already in the role list from schema.sql; this line is a no-op if so
do $$ begin
  alter type user_role add value if not exists 'costing';
exception when others then null; end $$;

create table if not exists invoices (
  id uuid primary key default uuid_generate_v4(),
  project_id text not null references projects(id) on delete cascade,
  invoice_no text not null,
  invoice_date date,
  inv_type text default 'Progress',        -- Progress | Advance | Retention release | Variation | Other
  amount numeric default 0,
  submitted numeric default 0,
  approved numeric default 0,
  collected numeric default 0,
  remark text,
  uploaded_by uuid references profiles(id), uploaded_at timestamptz default now(),
  unique (project_id, invoice_no));

create table if not exists upload_history (   -- costing files and invoice registers
  id uuid primary key default uuid_generate_v4(),
  project_id text references projects(id) on delete cascade,
  kind text not null,                        -- costing | invoices
  file_name text, rows_total int, rows_ok int, rows_rejected int, rows_flagged int,
  by_user uuid references profiles(id), at_time timestamptz default now());

create table if not exists dcma_results (
  project_id text primary key references projects(id) on delete cascade,
  file_name text, data_date date, tasks int, rels int,
  checks jsonb not null,                     -- [{no,name,val,thr,pass,why}]
  by_user uuid references profiles(id), at_time timestamptz default now());

create table if not exists reminders (
  id uuid primary key default uuid_generate_v4(),
  project_id text references projects(id) on delete cascade,
  message text not null, sent_to text[],
  by_user uuid references profiles(id), at_time timestamptz default now());

create table if not exists user_prefs (        -- executive summary layout, per person
  user_id uuid primary key references profiles(id) on delete cascade,
  prefs jsonb not null default '{}'::jsonb,
  updated_at timestamptz default now());

alter table invoices       enable row level security;
alter table upload_history enable row level security;
alter table dcma_results   enable row level security;
alter table reminders      enable row level security;
alter table user_prefs     enable row level security;

drop policy if exists inv_read on invoices;
drop policy if exists inv_write on invoices;
create policy inv_read  on invoices for select using (can_see(project_id));
create policy inv_write on invoices for all using (can_cost(project_id)) with check (can_cost(project_id));

drop policy if exists uh_read on upload_history;
drop policy if exists uh_write on upload_history;
create policy uh_read  on upload_history for select using (can_see(project_id));
create policy uh_write on upload_history for insert with check (can_cost(project_id) or can_plan(project_id));

drop policy if exists dc_read on dcma_results;
drop policy if exists dc_write on dcma_results;
create policy dc_read  on dcma_results for select using (can_see(project_id));
create policy dc_write on dcma_results for all using (can_plan(project_id)) with check (can_plan(project_id));

drop policy if exists rm_read on reminders;
drop policy if exists rm_write on reminders;
create policy rm_read  on reminders for select using (can_see(project_id));
create policy rm_write on reminders for insert with check (
  can_see(project_id) and (select role from profiles where id = auth.uid()) in ('sa','exec','rm','pf','plan'));

drop policy if exists up_self on user_prefs;
create policy up_self on user_prefs for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- purchase orders: the costing engineer of the project may add subcontractor companies
drop policy if exists m_write_sub on subcontractors;
create policy m_write_sub on subcontractors for all
  using (my_role() in ('sa','costing')) with check (my_role() in ('sa','costing'));

create index if not exists invoices_proj on invoices (project_id, invoice_date);
create index if not exists uh_proj on upload_history (project_id, kind, at_time desc);
