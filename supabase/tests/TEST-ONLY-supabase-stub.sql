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
