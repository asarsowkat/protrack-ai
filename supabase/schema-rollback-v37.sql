-- ProTrack schema rollback v37 (ProTrackAI v3.32): undo schema-update-v37.sql.
-- The super admin can no longer set the finance cost rates and nobody reads them: the Cashflow Dashboard still shows inflow,
-- outflow and the net, without a finance cost. The screen 'cfd' leaves pt_screens(). The tables and what they hold are kept,
-- so running v37 again brings the rates back. Safe to run when v37 was never applied: then it changes nothing.

do $$
declare scr text[];
begin
  if to_regprocedure('public.pt_screens()') is not null then
    scr := pt_screens();
    if 'cfd' = any(scr) then
      execute format('create or replace function pt_screens() returns text[] language sql immutable as $f$ select %L::text[] $f$', array_remove(scr, 'cfd')::text); end if;
  end if;
end $$;
drop function if exists cf_rates_set(jsonb);
drop function if exists cf_features();
do $$ begin
  if to_regclass('public.cf_rates') is not null then revoke select on cf_rates, cf_settings, cf_rates_audit from authenticated; end if;
end $$;
