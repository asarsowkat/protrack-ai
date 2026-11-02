# v3.54 setup: weather, constraints and recovery actions on the daily report

This takes about 2 minutes. **Do not** upload a new `config.js`. It needs v54 (STAGE-48-SETUP).

It passed 18 checks on a test copy of the full schema (PGlite), but has not yet been run on Supabase, so try it on a staging copy first.

The Daily Productivity Report, its previews and the approval email need no server change: they work as soon as the new `index.html` is published. This update only adds the three new fields of the daily report.

## Step 1: Update the database

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `supabase/schema-update-v55.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select media_features() ->> 'version' as version, media_features() ->> 'dpr_notes' as dpr_notes;
   ```

   Expect **55** and **true**.

**What the update adds:**
- **Three columns on `dprs`:** `weather` (60 characters), `issues_text` and `recovery_text` (1,000 characters each).
- **`dpr_notes_set`:** whoever may edit the daily report changes them, by the same rule as the photos (v54). Nobody changes them once the report is approved or rejected.

Until this update runs, the three fields are greyed out in the daily report form, with a note.

## Step 2: Try it

1. As a foreman: **New report**. Fill in **Weather**, **Major constraints / issues** and **Recovery actions / next steps**, then press **Preview report**.
2. Submit the report. Review and approve it as the site engineer and the site manager.
3. **Settings → Email** lists the approval email with its recipients. Open it to see the Daily Productivity Report as they receive it.

## To undo

Run `supabase/schema-rollback-v55.sql`. The three fields can no longer be changed; what was written stays in the columns and comes back if v55 is run again.
