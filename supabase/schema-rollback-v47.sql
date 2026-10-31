-- ProTrack schema rollback v47 (ProTrackAI v3.44): undo schema-update-v47.sql.
-- Logos, customers and report photos and videos can no longer be changed, and nobody reads them: the exports print the
-- company name without a logo and the reports show no photos. The tables, the bucket report-media and the stored files are
-- kept, so running v47 again brings everything back. Safe to run when v47 was never applied: then it changes nothing.

drop policy if exists protrack_rm_read on storage.objects;
drop policy if exists protrack_rm_add on storage.objects;
drop policy if exists protrack_rm_del on storage.objects;
drop function if exists report_media_act(jsonb);
drop function if exists branding_set(jsonb);
drop function if exists customer_act(jsonb);
drop function if exists media_features();
drop function if exists pt_rm_gone(uuid, text);
drop function if exists pt_rm_can(uuid, text, text, text);
do $$ begin
  if to_regclass('public.report_media') is not null then revoke select on report_media from authenticated; end if;
  if to_regclass('public.pt_branding') is not null then revoke select on pt_branding, customers from authenticated; end if;
end $$;
