-- ProTrack schema rollback v32: takes BOQ Engine's writes off the server (back to v3.24).
-- boq_save is removed: nobody can change BOQ Engine records on the server. The upload policy of the bucket boq-drawings
-- is removed; files stay readable. Everything is kept: the boq_* tables with their contents, the audit and the files.
-- The five boq rights stay in pt_rights() (a role's saved setting for them is harmless). Run schema-update-v32.sql again
-- to use them again. To remove the tables as well (not undoable), run separately:
-- drop table boq_audit, boq_master, boq_handoffs, boq_estimates, boq_assumptions, boq_specifications, boq_calculations, boq_dimensions, boq_drawings, boq_structures, boq_packages;
-- Safe to run twice.

drop function if exists boq_save(jsonb);
drop policy if exists protrack_boq_add on storage.objects;
