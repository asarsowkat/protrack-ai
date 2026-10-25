# v3.40 setup: delete an uploaded tender costing file

This takes about 3 minutes. **Do not** upload a new `config.js`. It needs v42 (Budget & Cost Management stage 4, STAGE-36-SETUP). Try it on a staging copy first: this update has not yet been run on a database.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `supabase/schema-update-v44.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select bcm_features() ->> 'version' as version, bcm_features() ->> 'file_delete' as file_delete, (select count(*) from pg_policies where policyname = 'protrack_bcm_del') as delete_rule;
   ```

   Expect **44**, **true** and **1**.

**What the update does:**
- **Delete** in Budget & Cost Management → Tender File Intake removes an uploaded tender costing file:
  - its record and every line read from it, with their classification, splits and sheet roles;
  - the duplicate groups that used its lines become obsolete.
- **Who:** the person who uploaded the file, or a reviewer (bcm.review), with a reason.
- **Refused:** while the batch is withdrawn, while the file is being read, and while a budget version prepared from the batch is not rejected or cancelled. When people have decided lines of the file, the app asks to confirm first.
- **Kept:** the classification history, and the audit log entry "File deleted" with the file's name, SHA-256, size and the reason.
- **The stored workbook:** the app removes it from the private bucket `bcm-tender`. The bucket allows that only for a workbook no file record points to any more.

## Step 2: Check it (1 minute)

1. Sign in as a costing engineer and reload the page.
2. **Budget & Cost Management → Tender File Intake**, choose a batch, and press **Delete** on a test file. Give the reason and confirm.
3. Check: the file is gone from the batch, and **Audit Log** shows "File deleted" with the reason. Upload the same file again: it is accepted.

## To undo

Run `supabase/schema-rollback-v44.sql`. The app then shows no Delete button. Files already deleted stay deleted, and their audit log entries are kept.
