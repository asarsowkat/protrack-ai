-- ProTrack schema rollback v30: takes the intermediate milestones and progress by phase off the server (back to v3.22).
-- key_milestone_act and release_act_km are removed: nobody can add or remove intermediate milestones, and the app saves
-- reports through release_act_bl again (without key_ms and phase_tbl). pt_phases() goes back to the seven phases; an
-- internal weightage that gives Energization a weight must be changed before it can be saved again.
-- Everything is kept: key_milestones and key_milestone_audit with their contents, and the key_ms and phase_tbl already
-- saved in report figures. Run schema-update-v30.sql again to use them again. To remove the tables as well (not
-- undoable), run separately: drop table key_milestone_audit, key_milestones;
-- Safe to run twice.

drop function if exists release_act_km(jsonb);
drop function if exists key_milestone_act(jsonb);
drop function if exists pt_phase_tbl(text, text, text, text);
drop function if exists pt_key_ms(text, text, text, text);
drop function if exists pt_km_update(text, text, date);
create or replace function pt_phases() returns text[] language sql immutable as $$
  select array['GEN','DES','MAT','CON','INS','TC','CLO'] $$;
