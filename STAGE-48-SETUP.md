# v3.53 setup: site photos on the daily reports

This takes about 3 minutes. **Do not** upload a new `config.js`. It needs v47 (STAGE-41-SETUP) and v53 (STAGE-47-SETUP, which fixes reading stored files).

It passed 37 checks on a test copy of the full schema (PGlite), but has not yet been run on Supabase, so try it on a staging copy first.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `supabase/schema-update-v54.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select media_features() ->> 'version' as version, media_features() ->> 'dpr_media' as dpr_media;
   ```

   Expect **54** and **true**.

**What the update adds:**
- **Daily report photos in `report_media`:** kind `dpr`, one set per daily report, photos only, at most 20, in the private bucket `report-media`.
- **Who changes them:** whoever may edit the daily report (`pt_dpr_edit`, the rule of `dpr_save`). Nobody once the report is approved or rejected.
- **Who reads them:** everyone who sees the project, so the planning engineer can pick them for the weekly and monthly reports.

No new right, bucket or screen. Until this update runs, the daily report form says *"Site photos need the v54 database update"* and offers no photo buttons.

## Step 2: Try it (1 minute)

1. As a foreman: **New report**, add two photos under **Site photos**, give one a caption, **Save draft**.
2. Open the report: the photos show under **Site photos**. Press **Preview all**.
3. Submit it. As the planning engineer: **Internal report** → this week → **Photos & videos**. The photos are listed under **Pick from the daily reports of this week** once the daily report is submitted. Tick one and press **Add selected to this report**.

## To undo

Run `supabase/schema-rollback-v54.sql`. Daily reports no longer keep photos: their records are removed, and the weekly and monthly reports keep the copies they took. The files stay in `report-media` under `<project>/dpr/`, where an administrator can delete them in Storage.
