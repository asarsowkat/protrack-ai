# v3.50 setup: client invoice formats

This takes about 5 minutes. **Do not** upload a new `config.js`. It needs v52 (STAGE-46-SETUP), which needs v51 (STAGE-45-SETUP).

It passed 43 checks on a test copy of the full schema (PGlite), but has not yet been run on Supabase, so try it on a staging copy first.

**It also fixes reading stored files.** If v47 (STAGE-41) is installed, files in storage (report photos, project documents, delay documents, BoQ drawings, tender files) cannot be read until this update runs.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `supabase/schema-update-v53.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select cib_features() ->> 'version' as version, (select public from storage.buckets where id = 'cib-formats') as bucket_public;
   ```

   Expect **53** and **false**.

**What the update adds:**
- **The table `cib_formats`:** each format's name, client, workbook, map and history.
- **The private bucket `cib-formats`:** the workbooks, .xlsx only, up to 25 MB each.
- **Who reads and keeps formats:**
  - everyone who sees billing figures reads them (not foremen);
  - those with `cib.setup` keep them.
- **The export** of an invoice is noted in the audit trail.
- **The fix** to the storage read rule.

No new right or screen.

## Step 2: Keep the first format (3 minutes)

1. **Invoices & Cash Flow → Client Invoice Builder → Invoice formats**.
2. Upload a certified invoice workbook of the client (.xlsx). Its figures are not used.
3. Check the map:
   - **Sheets:** *Fill* for the tax invoice, cover page, summary and breakdown sheets. *Keep as it is* for the rest. *Take out* only for a sheet that no other sheet refers to.
   - **Breakdown tables:** the component of each sheet, and *Rows from the Schedule-C*.
   - **Invoice header cells:** the field of each cell, or *Nothing*.
4. Choose the client (or *Any client*) and save.

## Step 3: Export

On an invoice, choose the format beside **Excel invoice** and press it. ProTrack then shows:
- the rows it rebuilt;
- whether the workbook's own totals agree with the invoice.

Read any difference before sending the file. A difference usually means the client's payment formula differs from the approved invoicing rules.

## To undo

Run `supabase/schema-rollback-v53.sql`. Formats can no longer be read, and invoices are exported in the ProTrackAI layout. The table, the bucket, the stored workbooks and the storage read fix stay.
