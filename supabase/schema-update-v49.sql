-- ProTrack schema update v49 (ProTrackAI v3.46): client report formats for Word reports.
-- crf_save checks two more page sources, the report's revision record ('auto:revisions') and the invoice register
-- ('auto:invoices'), a page's level (1 heading, 2 sub-heading: 2.1, 2.2 …) and its orientation (portrait or landscape), and the
-- style's table heading colours, header line and page orientation. The formats keep them as they are (jsonb); nothing else
-- changes. Needs schema-update-v48.sql. Safe to run twice. Undo: schema-rollback-v49.sql (back to the v48 checks).

do $$ begin
  if to_regprocedure('public.pt_crf_check(jsonb)') is null then raise exception 'Run schema-update-v48.sql (STAGE-42-SETUP) first, then this update'; end if;
end $$;

create or replace function pt_crf_check(p jsonb) returns text language plpgsql immutable as $$
declare s jsonb; keys text[] := '{}'; k text; src text;
begin
  if length(btrim(coalesce(p ->> 'name', ''))) < 3 or length(p ->> 'name') > 120 then return 'Give the format a name (3 to 120 characters)'; end if;
  if jsonb_typeof(p -> 'sections') is distinct from 'array' or jsonb_array_length(p -> 'sections') = 0 then return 'Add at least one page'; end if;
  if jsonb_array_length(p -> 'sections') > 80 then return 'At most 80 pages in a format'; end if;
  if jsonb_typeof(p -> 'periods') is distinct from 'array' or jsonb_array_length(p -> 'periods') = 0 then return 'Choose weekly, monthly or both'; end if;
  if coalesce(p #>> '{style,c1}', '') !~ '^[0-9A-Fa-f]{6}$' or coalesce(p #>> '{style,c2}', '') !~ '^[0-9A-Fa-f]{6}$'
     or coalesce(p #>> '{style,th}', '') !~ '^([0-9A-Fa-f]{6})?$' or coalesce(p #>> '{style,tht}', '') !~ '^([0-9A-Fa-f]{6})?$' then return 'The colours are 6-digit hex codes, for example 40916C'; end if;
  if length(coalesce(p #>> '{style,footer}', '')) > 200 or length(coalesce(p #>> '{style,header}', '')) > 200 then return 'The header and footer are 200 characters at most'; end if;
  if coalesce(p #>> '{style,orient}', 'landscape') not in ('portrait','landscape') then return 'The page orientation is portrait or landscape'; end if;
  for s in select * from jsonb_array_elements(p -> 'sections') loop
    k := s ->> 'key'; src := s ->> 'src';
    if k is null or k = any(keys) then return 'Each page needs its own key'; end if; keys := keys || k;
    if length(btrim(coalesce(s ->> 'title', ''))) = 0 or length(s ->> 'title') > 120 then return 'Each page needs a title of up to 120 characters'; end if;
    if src is null or src !~ '^(auto:(cover|contents|info|summary|scurve|phases|baselines|milestones|keyms|ep|look|manpower|issues|contract|photos|thanks|revisions|invoices|note:(summary|achieved|next|issues|remarks))|manual:(text|table|images))$' then
      return format('Page "%s": unknown source', s ->> 'title'); end if;
    if coalesce(s ->> 'lvl', '1') not in ('1','2') then return format('Page "%s": the level is 1 (heading) or 2 (sub-heading)', s ->> 'title'); end if;
    if coalesce(s ->> 'orient', 'portrait') not in ('portrait','landscape') then return format('Page "%s": portrait or landscape', s ->> 'title'); end if;
    if src = 'manual:table' and (jsonb_typeof(s -> 'cols') is distinct from 'array' or jsonb_array_length(s -> 'cols') not between 1 and 12) then return format('Page "%s": give 1 to 12 column headings', s ->> 'title'); end if;
    if length(coalesce(s ->> 'hint', '')) > 300 then return format('Page "%s": the guidance is 300 characters at most', s ->> 'title'); end if;
  end loop;
  return null;
end $$;
revoke execute on function pt_crf_check(jsonb) from public, anon;
create or replace function crf_features() returns jsonb language sql stable as $$ select jsonb_build_object('version', 49, 'client_report_formats', true, 'word_formats', true) $$;
grant execute on function crf_features() to authenticated;
