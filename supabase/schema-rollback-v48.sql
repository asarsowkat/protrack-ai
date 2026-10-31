-- ProTrack schema rollback v48 (ProTrackAI v3.45): undo schema-update-v48.sql.
-- Client report formats can no longer be read or changed: every client report uses the ProTrack standard format, and exports
-- are no longer logged. The pages entered in client reports stay with the reports. The tables are kept, so running v48 again
-- brings the formats, the choices and the export log back. Safe to run when v48 was never applied: then it changes nothing.

drop function if exists crf_save(jsonb);
drop function if exists crf_pick(jsonb);
drop function if exists crx_log(jsonb);
drop function if exists crf_features();
drop function if exists pt_crf_check(jsonb);
do $$ begin
  if to_regclass('public.client_report_formats') is not null then
    revoke select on client_report_formats, client_report_format_picks, client_report_exports from authenticated; end if;
end $$;
