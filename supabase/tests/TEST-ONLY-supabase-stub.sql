-- TEST ONLY. DO NOT RUN THIS ON SUPABASE: it would replace Supabase's own sign-in function.
-- It imitates the parts of Supabase the ProTrack schema needs, so the tests can run on a plain local PostgreSQL.
-- Minimal stand-in for the parts of Supabase the schema relies on (test only).
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key, email text);
create or replace function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
grant usage on schema public to authenticated, anon;
alter default privileges in schema public grant all on tables to authenticated;
alter default privileges in schema public grant all on sequences to authenticated;
alter default privileges in schema public grant execute on functions to authenticated;
-- Supabase Storage stand-in (test only): the two tables the v13 rules use
create schema if not exists storage;
create table if not exists storage.buckets (id text primary key, name text not null, owner uuid, public boolean default false,
  file_size_limit bigint, allowed_mime_types text[], created_at timestamptz default now(), updated_at timestamptz default now());
create table if not exists storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id),
  name text, owner uuid default auth.uid(), metadata jsonb, created_at timestamptz default now(), unique (bucket_id, name));
alter table storage.objects enable row level security;
grant usage on schema storage to authenticated, anon;
grant select, insert, update, delete on storage.objects to authenticated;
grant select on storage.buckets to authenticated;
-- as on Supabase, signed-in requests may call auth.uid() (storage rules use it directly)
grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
