-- ProTrack schema rollback v29: takes Reporting status's writes off the server (back to v3.21).
-- reporting_act and reporting_features() are removed: nobody can send reminders, exempt projects or change the rules on
-- the server. Everything is kept: rs_config, rs_exemptions and rs_reminders with their contents, still readable.
-- Run schema-update-v29.sql again to use them again. To remove them as well (not undoable), run separately:
-- drop table rs_reminders, rs_exemptions, rs_config;
-- Safe to run twice.

drop function if exists reporting_features();
drop function if exists reporting_act(jsonb);
drop function if exists pt_rs_reminder_ok(uuid, text);
