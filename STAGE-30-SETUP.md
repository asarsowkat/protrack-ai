# v3.31 setup: a version on each budget supplement row

This takes about 3 minutes. **Do not** upload a new `config.js`. It needs the v35 update (STAGE-29-SETUP). Try it on a staging copy first: this update has been run only on a test database so far.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v36.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select supp_features(), (select count(*) from budget_supplements where version is null) as rows_without_version;
   ```

   Expect `{"version": 36, "row_version": true, "supplement_log": true}` and **0**.

**What the update does:**
- **A version on each row:** the month the supplement applies to, whatever its WF date. A WF approved in SAP on 5 October whose values management approved in September is in the **Sep-26** version.
- **Rows already logged** get the first month their supplement number appears in the project's logs, so every report gives the same figures as before the update.
- **The cost report** of a month counts the rows of the project's log whose version is up to that month. A supplement entered later, with an earlier version, counts in its own month.
- **Uploads** are the whole log of the project as of the month of the upload: each row keeps its version (blank: the month of the upload), none after it. An upload for a month before the project's latest log is refused.
- **Changes on the screen** (`supp_update`) keep and change the version like the other fields, in the history.

## Step 2: Check (1 minute)

- Reload the live app. **Cost Control → Budget supplements**: the yellow note about the v36 update is gone.
- Choose one project, **Edit in the grid**, add a row with **Version** last month and a WF date this month, and **Save**.
- Choose that **Version** with **Show: This version only**: the row is there. The monthly cost report of last month counts it in the budget change.

## To undo

Run `schema-rollback-v36.sql`. A row's version is the month of its log again, and uploads and the screen stop storing it. The column and its values are kept, so running v36 again brings everything back.
