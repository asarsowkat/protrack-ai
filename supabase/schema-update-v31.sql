-- ProTrack schema update v31 (ProTrackAI v3.24): BOQ Engine, the module (specification section 1).
-- The screen 'boq' joins pt_screens(), so the super admin can show or hide BOQ Engine for a role in Settings → Role access
-- and the server keeps that choice (rights_save). Who sees it by default is worked out by the app: management, planning,
-- costing and project managers. BOQ Engine stores nothing yet; its tables come with the sections that follow.
-- Needs schema-update-v16.sql (Roles and rights, pt_screens; STAGE-13-SETUP). Additive. Safe to run twice. Undo: schema-rollback-v31.sql.

do $$
declare scr text[];
begin
  if to_regprocedure('public.pt_screens()') is null then raise exception 'Run the Roles and rights update (pt_screens) first, then this update'; end if;
  scr := pt_screens();
  if not ('boq' = any(scr)) then
    execute format('create or replace function pt_screens() returns text[] language sql immutable as $f$ select %L::text[] $f$', (scr || 'boq'::text)::text); end if;
end $$;
