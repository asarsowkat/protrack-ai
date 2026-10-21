-- ProTrack schema rollback v27: takes the cash-out forecast's writes off the server (back to v3.19.2).
-- cashout_act and cashout_features() are removed, so nobody can import Finance cash-out, change payment terms, other
-- lines, scenarios or versions; live.html still shows what is kept, read-only. The right cashout.keep leaves Settings ->
-- Roles and rights and the screen 'cout' leaves Screens by role.
-- Everything is kept: every co_ table with its records, the audit, the import batches and the PO values revised through
-- the module (purchase_orders.po_value is not put back). Run schema-update-v27.sql again to use them again.
-- To remove the data as well (not undoable), run separately:
-- drop table co_audit, co_reviews, co_versions, co_scenarios, co_other_lines, co_po_terms, co_opening, co_actuals, co_batches, co_maps;
-- Safe to run twice.
-- v3.28.2: safe to run even if schema-update-v27.sql was never applied (the table co_batches is not on the database): then it changes
-- nothing and its result says so. Otherwise it runs the rollback below, unchanged. The result is one row.

do $pt_rollback$
declare applied boolean := to_regclass('public.co_batches') is not null;
begin
  if not applied then
    perform set_config('protrack.rollback', 'schema-update-v27.sql is not on this database (never run, or already undone): nothing to undo, nothing was changed.', false);
    return;
  end if;
  execute $pt_rollback_body$
drop function if exists cashout_features();
drop function if exists cashout_act(jsonb);
drop function if exists pt_co_ms(jsonb, numeric);
drop function if exists pt_co_pay_date(jsonb);
drop function if exists pt_co_num(text);
drop function if exists pt_co_log(text, text, text, jsonb);
drop function if exists pt_co_publisher(uuid);
drop function if exists pt_co_approver(uuid);
drop function if exists pt_co_uploader(uuid);
drop function if exists pt_co_keeper(uuid, text);

do $$
declare cur text[] := pt_rights(); scr text[] := pt_screens(); src text;
begin
  if 'cashout.keep' = any(cur) then
    execute format('create or replace function pt_rights() returns text[] language sql immutable as $f$ select %L::text[] $f$', array_remove(cur, 'cashout.keep')::text); end if;
  if 'cout' = any(scr) then
    execute format('create or replace function pt_screens() returns text[] language sql immutable as $f$ select %L::text[] $f$', array_remove(scr, 'cout')::text); end if;
  select prosrc into src from pg_proc where proname = 'pt_right_default' and pronamespace = 'public'::regnamespace and pronargs = 2;
  if position('cashout.keep' in src) > 0 then
    src := regexp_replace(src, E'when ''cashout.keep''\\s+then base = ''costing''\\s*\n\\s*', '');
    execute format('create or replace function pt_right_default(base text, k text) returns boolean language sql immutable as $f$%s$f$', src);
  end if;
end $$;
$pt_rollback_body$;
  perform set_config('protrack.rollback', 'schema-update-v27.sql undone.', false);
end $pt_rollback$;
select current_setting('protrack.rollback', true) as result;
