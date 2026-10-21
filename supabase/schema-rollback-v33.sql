-- ProTrack schema rollback v33: E&P progress is no longer saved with reports on the server (back to v3.25).
-- release_act_km goes back to the v30 version; pt_ep_tbl and ep_features are removed, so the app stops sending figures.ep.
-- The E&P tables already saved in report figures are kept. Safe to run twice.

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
                                                 'phase_tbl', coalesce(pt_phase_tbl(rel.project_id, rel.kind, rel.period_type, rel.period), 'null'::jsonb))
   where id = rel.id returning * into rel;
  return to_jsonb(rel);
end $$;
drop function if exists ep_features();
drop function if exists pt_ep_tbl(text, text, text, text);
