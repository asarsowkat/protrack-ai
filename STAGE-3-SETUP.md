# Phase 3: controlled imports (ProTrackAI v2.6)

This adds the **Import centre** and makes every upload checked, previewed, reconciled and saved all-or-nothing. It covers the invoice register, the costing file, the P6 baseline and weekly progress. It takes about 15 minutes.

**Do not** upload a new `config.js`. Keep the one already on GitHub.

## Step 1: Update the database (5 minutes)

1. Supabase → **SQL Editor** → **New query**.
2. Open `schema-update-v5.sql` from this package in Notepad. Select all, copy, and paste it into the editor.
3. Press **Run**.
   - The expected result is **"Success. No rows returned"**.
   - Lines saying "already exists, skipping" are normal.
4. Check it worked. Open a new query, paste this and press Run:

   ```sql
   select count(*) as functions_installed from pg_proc
   where proname in ('import_commit','log_import_failure','import_progress','pt_num','pt_date');
   ```

   Expect **5**.

The update only adds things. It deletes no table, column or row. Earlier imports stay, numbered from IMP-000001. Running it a second time is safe.

## Step 2: Publish the website

Tell Claude "Step 1 done, it showed 5". Claude then merges the prepared update on GitHub.

Or do it yourself:

1. Open the pull request on github.com/asarsowkat/protrack-ai.
2. Press **Merge pull request**, then **Confirm**.
3. Wait 2 minutes, then press **Ctrl + F5** on the site.
4. Check that **Settings → System** shows **v2.6**.

## Step 3: Test (10 minutes)

| Who | Does | Expect |
|---|---|---|
| Costing engineer | Imports & Integrations → Import centre | The page opens and earlier uploads are listed |
| Costing engineer | Uploads an invoice register with one deliberately wrong row (for example currency USD, or the same invoice number twice) | The preview shows the refused row with its reason. **Apply** stays grey until the box is ticked. |
| Costing engineer | Presses **Download exception report** | A spreadsheet with the refused row, its sheet row number and its reason |
| Costing engineer | Ticks the box, adds a note, presses Apply | Saved. The Import centre shows the batch as **Committed with difference**, with their name and the note. |
| Costing engineer | Uploads exactly the same file again | "Same content as the last load, so nothing changed" |
| Planning engineer | Uploads the weekly progress file | Applied in one batch; the batch appears in the Import centre |
| Foreman | Looks at the menu | No Import centre |

## If something goes wrong

| What you see | What to do |
|---|---|
| "Could not find the function public.import_commit" | Step 1 did not run on this project. Run `schema-update-v5.sql` again. |
| An upload shows **Failed** | Nothing was saved and the previous data is unchanged. Open the batch for the reason, fix it, and upload again. |
| "Only Excel (.xlsx, .xls), CSV …" | Save the file as a plain Excel workbook (.xlsx) and upload that. |

**To undo** (keeps all data):

1. Run `schema-rollback-v5.sql` in the SQL Editor.
2. Ask Claude to put back v2.5, or revert the merge on GitHub.

## Not included

SAP ECC Excel exports are not included yet. They are planned once a sample export and the Finance rules are agreed. Any direct SAP or S/4HANA connection stays switched off.
