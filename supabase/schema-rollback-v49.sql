-- ProTrack schema rollback v49 (ProTrackAI v3.46): undo schema-update-v49.sql.
-- crf_save goes back to the v48 checks: a format with a revision record or invoices page, a page level or orientation, or table
-- heading colours can no longer be saved (formats already saved keep them; the app reads them). Safe to run twice.

create or replace function pt_crf_check(p jsonb) returns text language plpgsql immutable as $$
declare s jsonb; keys text[] := '{}'; k text; src text;
begin
  if length(btrim(coalesce(p ->> 'name', ''))) < 3 or length(p ->> 'name') > 120 then return 'Give the format a name (3 to 120 characters)'; end if;
  if jsonb_typeof(p -> 'sections') is distinct from 'array' or jsonb_array_length(p -> 'sections') = 0 then return 'Add at least one page'; end if;
  if jsonb_array_length(p -> 'sections') > 80 then return 'At most 80 pages in a format'; end if;
  if jsonb_typeof(p -> 'periods') is distinct from 'array' or jsonb_array_length(p -> 'periods') = 0 then return 'Choose weekly, monthly or both'; end if;
  if coalesce(p #>> '{style,c1}', '') !~ '^[0-9A-Fa-f]{6}$' or coalesce(p #>> '{style,c2}', '') !~ '^[0-9A-Fa-f]{6}$' then return 'The colours are 6-digit hex codes, for example 40916C'; end if;
  if length(coalesce(p #>> '{style,footer}', '')) > 200 then return 'The footer is 200 characters at most'; end if;
  for s in select * from jsonb_array_elements(p -> 'sections') loop
    k := s ->> 'key'; src := s ->> 'src';
    if k is null or k = any(keys) then return 'Each page needs its own key'; end if; keys := keys || k;
    if length(btrim(coalesce(s ->> 'title', ''))) = 0 or length(s ->> 'title') > 120 then return 'Each page needs a title of up to 120 characters'; end if;
    if src is null or src !~ '^(auto:(cover|contents|info|summary|scurve|phases|baselines|milestones|keyms|ep|look|manpower|issues|contract|photos|thanks|note:(summary|achieved|next|issues|remarks))|manual:(text|table|images))$' then
      return format('Page "%s": unknown source', s ->> 'title'); end if;
    if src = 'manual:table' and (jsonb_typeof(s -> 'cols') is distinct from 'array' or jsonb_array_length(s -> 'cols') not between 1 and 12) then return format('Page "%s": give 1 to 12 column headings', s ->> 'title'); end if;
    if length(coalesce(s ->> 'hint', '')) > 300 then return format('Page "%s": the guidance is 300 characters at most', s ->> 'title'); end if;
  end loop;
  return null;
end $$;
revoke execute on function pt_crf_check(jsonb) from public, anon;
create or replace function crf_features() returns jsonb language sql stable as $$ select jsonb_build_object('version', 48, 'client_report_formats', true) $$;
grant execute on function crf_features() to authenticated;
