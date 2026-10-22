-- ProTrack schema update v37 (ProTrackAI v3.32): the Cashflow Dashboard and its finance cost rates.
-- 1. The screen 'cfd' (Invoices & Cash Flow -> Cashflow Dashboard) joins pt_screens(), so the super admin can show or hide
--    it for a role in Settings -> Role access. Who sees it by default is worked out by the app: those who see both the
--    cash-inflow and the cash-out forecasts. The dashboard itself reads what the server already gives (the invoice register,
--    the payment terms, the updated schedules, Finance's cash-out, the PO payment terms, the released cost reports) and
--    works the figures out in the browser, as the cash-inflow and cash-out forecasts do.
-- 2. cf_rates: the interest rate (% per annum) treasury charges on a project's deficit, month by month. cf_settings: one row,
--    the average rate for the forecast period (used from the current month for a month without its own rate) and the basis
--    (each month's deficit, or the cumulative deficit). A surplus earns nothing. Read by those who see cost figures
--    (pt_money_ok); changed only by a super admin through cf_rates_set(p), with the app's checks (cfCheck). Every change is
--    kept in cf_rates_audit, which cannot be changed.
-- 3. cf_features() tells the app this update is in.
-- Needs schema-update-v16.sql (pt_screens, pt_money_ok). Additive. Safe to run twice. Undo: schema-rollback-v37.sql.

do $$
declare scr text[];
begin
  if to_regprocedure('public.pt_screens()') is null or to_regprocedure('public.pt_money_ok()') is null then
    raise exception 'Run the Roles and rights update (schema-update-v16.sql, STAGE-13-SETUP) first, then this update'; end if;
  scr := pt_screens();
  if not ('cfd' = any(scr)) then
    execute format('create or replace function pt_screens() returns text[] language sql immutable as $f$ select %L::text[] $f$', (scr || 'cfd'::text)::text); end if;
end $$;

create table if not exists cf_rates (
  month text primary key check (month ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  rate numeric(7,3) not null check (rate >= 0 and rate <= 100),
  updated_by uuid references profiles(id), updated_at timestamptz not null default now());
create table if not exists cf_settings (
  id int primary key check (id = 1),
  fc_avg numeric(7,3) check (fc_avg is null or (fc_avg >= 0 and fc_avg <= 100)),
  basis text not null default 'month' check (basis in ('month','cum')),
  updated_by uuid references profiles(id), updated_name text, updated_at timestamptz not null default now());
insert into cf_settings (id, fc_avg, basis) values (1, null, 'month') on conflict (id) do nothing;
create table if not exists cf_rates_audit (
  id bigserial primary key,
  changes text[] not null default '{}',
  note text check (note is null or length(note) <= 300),
  by_user uuid references profiles(id), by_name text,
  at_time timestamptz not null default now());

alter table cf_rates enable row level security;
alter table cf_settings enable row level security;
alter table cf_rates_audit enable row level security;
drop policy if exists cfr_read on cf_rates;
create policy cfr_read on cf_rates for select using (pt_money_ok());
drop policy if exists cfs_read on cf_settings;
create policy cfs_read on cf_settings for select using (pt_money_ok());
drop policy if exists cfa_read on cf_rates_audit;
create policy cfa_read on cf_rates_audit for select using (pt_money_ok());
drop trigger if exists trg_cfa_append on cf_rates_audit;
create trigger trg_cfa_append before update or delete on cf_rates_audit for each row execute function pt_append_only();
drop trigger if exists trg_cfa_truncate on cf_rates_audit;
create trigger trg_cfa_truncate before truncate on cf_rates_audit execute function pt_no_truncate();
revoke all on cf_rates, cf_settings, cf_rates_audit from anon;
revoke insert, update, delete, truncate on cf_rates, cf_settings, cf_rates_audit from authenticated;
grant select on cf_rates, cf_settings, cf_rates_audit to authenticated;

-- p: {rates: {"2026-09": 6.25, "2026-10": null (removes the month's rate)}, fc_avg: number or null, basis: 'month' | 'cum', note}
create or replace function cf_rates_set(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); m text; v jsonb; r numeric; old numeric; ch text[] := '{}'; s cf_settings; avg numeric; b text := coalesce(p ->> 'basis', 'month');
begin
  if me is null or role_of(me) is distinct from 'sa' then raise exception 'Only a super admin sets the interest rates' using errcode = '42501'; end if;
  if b not in ('month','cum') then raise exception 'Choose the finance cost basis'; end if;
  if p ? 'rates' and jsonb_typeof(p -> 'rates') is distinct from 'object' then raise exception 'The rates are given month by month'; end if;
  if jsonb_typeof(p -> 'fc_avg') = 'number' then avg := (p ->> 'fc_avg')::numeric;
  elsif p ? 'fc_avg' and jsonb_typeof(p -> 'fc_avg') is distinct from 'null' then raise exception 'The forecast average is a rate from 0 to 100 %% per annum'; end if;
  if avg is not null and (avg < 0 or avg > 100) then raise exception 'The forecast average is a rate from 0 to 100 %% per annum'; end if;
  if length(coalesce(p ->> 'note', '')) > 300 then raise exception 'A comment is 300 characters at most'; end if;
  for m, v in select * from jsonb_each(coalesce(p -> 'rates', '{}'::jsonb)) loop
    if m !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'A month looks like 2026-09'; end if;
    select rate into old from cf_rates where month = m;
    if jsonb_typeof(v) = 'null' then
      if old is not null then delete from cf_rates where month = m; ch := ch || format('%s %s -> none', m, old); end if;
    elsif jsonb_typeof(v) = 'number' then
      r := round((v #>> '{}')::numeric, 3);
      if r < 0 or r > 100 then raise exception '%: a rate from 0 to 100 %% per annum', m; end if;
      if old is distinct from r then
        insert into cf_rates (month, rate, updated_by, updated_at) values (m, r, me, now())
        on conflict (month) do update set rate = excluded.rate, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
        ch := ch || format('%s %s -> %s', m, coalesce(old::text, 'none'), r); end if;
    else raise exception '%: a rate from 0 to 100 %% per annum', m; end if;
  end loop;
  select * into s from cf_settings where id = 1 for update;
  if s.fc_avg is distinct from round(avg, 3) then ch := ch || format('forecast average %s -> %s', coalesce(s.fc_avg::text, 'none'), coalesce(round(avg, 3)::text, 'none')); end if;
  if s.basis is distinct from b then ch := ch || format('basis %s -> %s', s.basis, b); end if;
  insert into cf_settings (id, fc_avg, basis, updated_by, updated_name, updated_at) values (1, round(avg, 3), b, me, name_of(me), now())
  on conflict (id) do update set fc_avg = excluded.fc_avg, basis = excluded.basis, updated_by = excluded.updated_by, updated_name = excluded.updated_name, updated_at = excluded.updated_at;
  insert into cf_rates_audit (changes, note, by_user, by_name) values (ch, nullif(btrim(coalesce(p ->> 'note', '')), ''), me, name_of(me));
  return jsonb_build_object('changes', to_jsonb(ch));
end $$;

create or replace function cf_features() returns jsonb language sql stable as $$ select jsonb_build_object('finance_cost_rates', true) $$;
revoke execute on function cf_rates_set(jsonb), cf_features() from public, anon;
grant execute on function cf_rates_set(jsonb), cf_features() to authenticated;
