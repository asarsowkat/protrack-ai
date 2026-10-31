-- ProTrack schema rollback v45 (ProTrackAI v3.41): undo schema-update-v45.sql.
-- Nobody can save, agree or approve a cost plan any more and nobody reads them: the MER still shows every figure that does not
-- need a cost plan (its planned POC shows "—"), and the areas of concern and the stock value stay in the released reports.
-- The screens 'cplan' and 'mer' leave pt_screens(). The table cost_plans and what it holds are kept, so running v45 again
-- brings the plans back. Safe to run when v45 was never applied: then it changes nothing.

do $$
declare scr text[];
begin
  if to_regprocedure('public.pt_screens()') is not null then
    scr := pt_screens();
    if 'cplan' = any(scr) or 'mer' = any(scr) then
      execute format('create or replace function pt_screens() returns text[] language sql immutable as $f$ select %L::text[] $f$', array_remove(array_remove(scr, 'cplan'), 'mer')::text); end if;
  end if;
end $$;
drop function if exists cost_plan_save(jsonb);
drop function if exists cost_plan_act(jsonb);
drop function if exists cost_plan_features();
drop function if exists cp_months(jsonb, numeric, numeric, text);
drop function if exists cp_num(jsonb, text);
do $$ begin
  if to_regclass('public.cost_plans') is not null then revoke select on cost_plans from authenticated; end if;
end $$;
