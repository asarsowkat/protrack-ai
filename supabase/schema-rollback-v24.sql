-- ProTrack schema rollback v24: takes the delay events register off the server (back to the v3.18 server rules).
-- delay_act, delay_import and delay_features() are removed, so nobody can add, change, delete or upload delay events on
-- the server: live.html still lists the events, and a save answers "The server refused this".
-- The right delay.keep leaves Settings -> Roles and rights and the screen 'dly' leaves Screens by role.
-- Everything is kept: delay_events and delay_audit with every event and every change, any setting of delay.keep a super
-- admin made, and import_batches accepting the kind 'delays'. Run schema-update-v24.sql again to use them again.
-- To remove the data as well (not undoable), run separately: drop table delay_audit; drop table delay_events;
-- Safe to run twice.
-- v3.28.2: safe to run even if schema-update-v24.sql was never applied (the table delay_events is not on the database): then it changes
-- nothing and its result says so. Otherwise it runs the rollback below, unchanged. The result is one row.

do $pt_rollback$
declare applied boolean := to_regclass('public.delay_events') is not null;
begin
  if not applied then
    perform set_config('protrack.rollback', 'schema-update-v24.sql is not on this database (never run, or already undone): nothing to undo, nothing was changed.', false);
    return;
  end if;
  execute $pt_rollback_body$
drop function if exists delay_features();
drop function if exists delay_import(jsonb);
drop function if exists delay_act(jsonb);
drop function if exists pt_dly_write(text, uuid, jsonb, text, text);
drop function if exists pt_dly_log(delay_events, text, text, jsonb);
drop function if exists pt_dly_merge(text, uuid, jsonb);
drop function if exists pt_dly_keys();
drop function if exists pt_dly_label(text);
drop function if exists pt_dly_numtext(text);
drop function if exists pt_dly_num(text);
drop function if exists pt_dly_nokey(text);
drop function if exists pt_dly_status(text);
-- pt_dly_keeper is kept: the delay-docs read policy kept by schema-rollback-v26.sql calls it

-- the right and the screen leave the lists (the rest stays as it is)
do $$
declare cur text[] := pt_rights(); scr text[] := pt_screens(); src text;
begin
  if 'delay.keep' = any(cur) then
    execute format('create or replace function pt_rights() returns text[] language sql immutable as $f$ select %L::text[] $f$', array_remove(cur, 'delay.keep')::text);
  end if;
  if 'dly' = any(scr) then
    execute format('create or replace function pt_screens() returns text[] language sql immutable as $f$ select %L::text[] $f$', array_remove(scr, 'dly')::text);
  end if;
  select prosrc into src from pg_proc where proname = 'pt_right_default' and pronamespace = 'public'::regnamespace and pronargs = 2;
  if position('delay.keep' in src) > 0 then
    src := regexp_replace(src, E'when ''delay.keep''\\s+then base = ''plan''\\s*\n\\s*', '');
    execute format('create or replace function pt_right_default(base text, k text) returns boolean language sql immutable as $f$%s$f$', src);
  end if;
end $$;
$pt_rollback_body$;
  perform set_config('protrack.rollback', 'schema-update-v24.sql undone.', false);
end $pt_rollback$;
select current_setting('protrack.rollback', true) as result;
