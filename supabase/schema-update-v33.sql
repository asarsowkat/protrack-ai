-- ProTrack schema update v33 (ProTrackAI v3.26): engineering and procurement (E&P) progress inside the internal and
-- client reports, weekly and monthly.
-- 1. pt_ep_tbl(project, kind, period type, period): each engineering and procurement activity of the project's baseline
--    with its plan (baseline progress at the schedule's data date), actual %, actual start and finish, forecast finish and
--    slip, from the updated schedule in force at the end of the period (with client weightage for a client report), as the
--    app's epReportStats(). Engineering and procurement totals weighted by the activity budget (cost, else price weight,
--    else manhours × 19, else 1), as the app's bacOf(). No updated schedule: the baseline plan only, no actual.
-- 2. release_act_km (v30) is replaced: it also takes figures.ep out before release_act_bl sees it, and writes the server's
--    own E&P table into the saved figures of an internal or client report. Approval freezes it.
-- 3. ep_features() tells the app this update is in.
-- There is no separate E&P upload; the screen "E&P progress" is replaced by the tab in each report.
-- Needs schema-update-v30.sql (release_act_km). Additive. Safe to run twice. Undo: schema-rollback-v33.sql.

do $$ begin
  if to_regprocedure('public.release_act_km(jsonb)') is null then raise exception 'Run schema-update-v30.sql (STAGE-26-SETUP) first, then this update'; end if;
end $$;

create or replace function pt_ep_tbl(pid text, k text, pt text, per text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare u schedule_updates; dd date; rows jsonb; sumf jsonb;
begin
  if not exists (select 1 from activities where project_id = pid and cls in ('ENG','PRC')) then return jsonb_build_object('none', true); end if;
  select * into u from schedule_updates where id = pt_km_update(pid, case when k = 'client' then 'client' end, pt_period_end(per, pt));
  dd := coalesce(u.data_date, pt_period_end(per, pt));
  with x as (
    select a.id, a.name, a.cls, coalesce(nullif(a.budget_cost, 0), nullif(a.price_weight, 0), nullif(a.budget_mh, 0) * 19, 1) w, a.bs, a.bf,
           round(pt_plan_frac(a.bs, a.bf, dd) * 100, 2) plan, r.act_id is not null in_s,
           case when r.act_id is not null then round(least(100, greatest(0, coalesce(r.pct, 0))), 2) end pct, r.as_d, r.af, coalesce(r.af, r.ef) ff
      from activities a left join schedule_update_rows r on r.update_id = u.id and r.act_id = a.id
     where a.project_id = pid and a.cls in ('ENG','PRC'))
  select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'cls', cls, 'w', w, 'plan', plan, 'bs', bs, 'bf', bf, 'src', case when in_s then 'sched' else 'none' end,
           'pct', pct, 'as', as_d, 'af', af, 'ff', ff, 'slip', case when ff is not null and bf is not null then ff - bf end) order by id) into rows from x;
  select jsonb_object_agg(g, jsonb_build_object('n', n, 'pct', case when w > 0 then round(wp / w, 2) end, 'plan', case when w > 0 then round(wl / w, 2) end, 'late', late, 'done', done)) into sumf
    from (select g, count(*) n, sum((e ->> 'w')::numeric) w, sum((e ->> 'w')::numeric * (e ->> 'pct')::numeric) wp, sum((e ->> 'w')::numeric * (e ->> 'plan')::numeric) wl,
                 count(*) filter (where (e ->> 'slip')::int > 0 and (e ->> 'pct')::numeric < 100) late, count(*) filter (where (e ->> 'pct')::numeric >= 100) done
            from jsonb_array_elements(coalesce(rows, '[]'::jsonb)) e, lateral (values (e ->> 'cls'), ('all')) v(g)
           where e ->> 'src' = 'sched' group by g) s;
  return jsonb_build_object('dd', dd, 'update_id', u.id, 'file', coalesce(u.file_name, ''), 'weightage', u.weightage, 'rows', coalesce(rows, '[]'::jsonb),
    'ENG', coalesce(sumf -> 'ENG', '{"n":0,"late":0,"done":0}'::jsonb), 'PRC', coalesce(sumf -> 'PRC', '{"n":0,"late":0,"done":0}'::jsonb), 'all', coalesce(sumf -> 'all', '{"n":0,"late":0,"done":0}'::jsonb),
    'missing', (select count(*) from jsonb_array_elements(coalesce(rows, '[]'::jsonb)) e where e ->> 'src' <> 'sched'), 'stale', u.id is not null and dd < pt_period_end(per, pt) - 8);
end $$;

-- release_act_km: from schema-update-v30.sql; also takes out and writes figures.ep
create or replace function release_act_km(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a text := p ->> 'action'; f jsonb := p -> 'figures'; res jsonb; rel report_releases;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if jsonb_typeof(f) = 'object' then p := jsonb_set(p, '{figures}', f - 'key_ms' - 'phase_tbl' - 'ep'); end if;
  res := release_act_bl(p);
  if a is distinct from 'save' then return res; end if;
  select * into rel from report_releases where id = (res ->> 'id')::uuid for update;
  if rel.id is null or rel.kind not in ('planning','client') then return res; end if;
  update report_releases
     set figures = figures || jsonb_build_object('key_ms', pt_key_ms(rel.project_id, rel.kind, rel.period_type, rel.period),
                                                 'phase_tbl', coalesce(pt_phase_tbl(rel.project_id, rel.kind, rel.period_type, rel.period), 'null'::jsonb),
                                                 'ep', pt_ep_tbl(rel.project_id, rel.kind, rel.period_type, rel.period))
   where id = rel.id returning * into rel;
  return to_jsonb(rel);
end $$;

create or replace function ep_features() returns jsonb language sql stable as $$ select jsonb_build_object('ep_in_reports', true) $$;
revoke execute on function pt_ep_tbl(text, text, text, text) from public, anon;
grant execute on function ep_features(), release_act_km(jsonb) to authenticated;
