-- ProTrack: undo schema update v6. Removes the lifecycle functions; keeps the lifecycle stages and their
-- history (nothing is deleted). Supabase -> SQL Editor -> New query -> paste -> Run. Safe to run twice.
drop function if exists lifecycle_act(jsonb);
drop function if exists pt_lc_approver(uuid, text);
drop function if exists pt_lc_template(int);
drop function if exists pt_lc_dept(int);
