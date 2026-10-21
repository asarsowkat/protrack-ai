-- ProTrack schema rollback v28: back to the v3.20 cash-out forecast on the server (schema-update-v27.sql).
-- cashout_act is the v27 function again, so the material PO terms and the head treatments can no longer be changed.
-- Everything is kept: co_mat_po and co_heads with their contents (live.html still reads them). Run schema-update-v28.sql
-- again to change them again. To remove them as well (not undoable), run separately: drop table co_mat_po, co_heads;
-- Safe to run twice.
-- v3.28.2: safe to run even if schema-update-v28.sql was never applied (the table co_mat_po is not on the database): then it changes
-- nothing and its result says so. Otherwise it runs the rollback below, unchanged. The result is one row.

do $pt_rollback$
declare applied boolean := to_regclass('public.co_mat_po') is not null;
begin
  if not applied then
    perform set_config('protrack.rollback', 'schema-update-v28.sql is not on this database (never run, or already undone): nothing to undo, nothing was changed.', false);
    return;
  end if;
  execute $pt_rollback_body$
do $$ begin
  if to_regprocedure('public.cashout_act_v27(jsonb)') is not null then
    drop function if exists cashout_act(jsonb);
    alter function cashout_act_v27(jsonb) rename to cashout_act;
    grant execute on function cashout_act(jsonb) to authenticated;
  end if;
end $$;
drop function if exists pt_co_mat_ms(jsonb, numeric);
create or replace function cashout_features() returns jsonb language sql immutable as $$ select '{"version":27,"cashout":true}'::jsonb $$;
$pt_rollback_body$;
  perform set_config('protrack.rollback', 'schema-update-v28.sql undone.', false);
end $pt_rollback$;
select current_setting('protrack.rollback', true) as result;
