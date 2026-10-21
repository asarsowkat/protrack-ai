-- ProTrack schema rollback v30: takes the intermediate milestones and progress by phase off the server (back to v3.22).
-- key_milestone_act and release_act_km are removed: nobody can add or remove intermediate milestones, and the app saves
-- reports through release_act_bl again (without key_ms and phase_tbl). pt_phases() goes back to the seven phases; an
-- internal weightage that gives Energization a weight must be changed before it can be saved again.
-- Everything is kept: key_milestones and key_milestone_audit with their contents, and the key_ms and phase_tbl already
-- saved in report figures. Run schema-update-v30.sql again to use them again. To remove the tables as well (not
-- undoable), run separately: drop table key_milestone_audit, key_milestones;
-- Safe to run twice.
-- v3.28.2: safe to run even if schema-update-v30.sql was never applied (the table key_milestones is not on the database): then it changes
-- nothing and its result says so. Otherwise it runs the rollback below, unchanged. The result is one row.

do $pt_rollback$
declare applied boolean := to_regclass('public.key_milestones') is not null;
begin
  if not applied then
    perform set_config('protrack.rollback', 'schema-update-v30.sql is not on this database (never run, or already undone): nothing to undo, nothing was changed.', false);
    return;
  end if;
  execute $pt_rollback_body$
drop function if exists release_act_km(jsonb);
drop function if exists key_milestone_act(jsonb);
drop function if exists pt_phase_tbl(text, text, text, text);
drop function if exists pt_key_ms(text, text, text, text);
drop function if exists pt_km_update(text, text, date);
create or replace function pt_phases() returns text[] language sql immutable as $$
  select array['GEN','DES','MAT','CON','INS','TC','CLO'] $$;
$pt_rollback_body$;
  perform set_config('protrack.rollback', 'schema-update-v30.sql undone.', false);
end $pt_rollback$;
select current_setting('protrack.rollback', true) as result;
