-- ProTrack schema rollback v28: back to the v3.20 cash-out forecast on the server (schema-update-v27.sql).
-- cashout_act is the v27 function again, so the material PO terms and the head treatments can no longer be changed.
-- Everything is kept: co_mat_po and co_heads with their contents (live.html still reads them). Run schema-update-v28.sql
-- again to change them again. To remove them as well (not undoable), run separately: drop table co_mat_po, co_heads;
-- Safe to run twice.

do $$ begin
  if to_regprocedure('public.cashout_act_v27(jsonb)') is not null then
    drop function if exists cashout_act(jsonb);
    alter function cashout_act_v27(jsonb) rename to cashout_act;
    grant execute on function cashout_act(jsonb) to authenticated;
  end if;
end $$;
drop function if exists pt_co_mat_ms(jsonb, numeric);
create or replace function cashout_features() returns jsonb language sql immutable as $$ select '{"version":27,"cashout":true}'::jsonb $$;
