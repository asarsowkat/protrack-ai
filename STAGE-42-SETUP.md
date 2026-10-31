# v3.45 setup: client report formats

This takes about 3 minutes. **Do not** upload a new `config.js`. It needs v47 (logos and customers, STAGE-41-SETUP). Try it on a staging copy first: this update has not yet been run on a database.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `supabase/schema-update-v48.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select crf_features() ->> 'version' as version, (select count(*) from pg_policies where policyname in ('crf_read','crfp_read','crx_read')) as read_rules, (select count(*) from pg_trigger where tgname like 'trg_crx_%') as log_locks;
   ```

   Expect **48**, **3** and **2**.

**What the update does:**
- **Settings → Client report formats** (super admin): each customer's client report format (`client_report_formats`).
- **The format a project uses:** a project can use another format than its customer's (`client_report_format_picks`), set by those who prepare client reports.
- **The export log:** every PowerPoint, Word or PDF of a client report is logged (`client_report_exports`), and the log cannot be changed.
- **No change for entered pages:** the pages the planning engineer enters travel with the client report as before.

## Step 2: Check it (2 minutes)

1. Sign in as the super admin and reload the page. Open **Settings → Client report formats → Draft a format from a client's PowerPoint** and choose the client's report. Check the pages, set the customer and save.
2. Sign in as a planning engineer and open a client report of that customer → **Client format and export**. Enter one page (for example the HSE table) and press **Save draft**.
3. Press **Export: PowerPoint, Word, PDF**. Read the disclaimer and the pages not updated, choose PowerPoint and a review copy, and press **Generate**. The pages not updated are marked in the file, and the export is listed in the tab.

## To undo

Run `supabase/schema-rollback-v48.sql`. Every client report then uses the ProTrack standard format and exports are not logged. The tables are kept; running v48 again brings the formats back.
