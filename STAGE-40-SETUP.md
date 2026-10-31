# v3.42 setup: the cost plans in bulk from Excel

This takes about 3 minutes. **Do not** upload a new `config.js`. It needs v45 (the cost plan, STAGE-39-SETUP). Try it on a staging copy first: this update has not yet been run on a database.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `supabase/schema-update-v46.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select cost_plan_features() ->> 'version' as version, cost_plan_features() ->> 'bulk_import' as bulk_import, (select count(*) from information_schema.columns where table_name = 'cost_plans' and column_name = 'plan_act') as actual_poc;
   ```

   Expect **46**, **true** and **1**.

**What the update does:**
- **Cost Control → Cost plan → Bulk upload (Excel):** a super admin or the costing coordinator uploads one workbook with the cost plans of many projects:
  - **COST PLAN (I):** budget, contract value and the planned cost of each month;
  - **COST PLAN (F):** actual POC at the end of last year, target POC at year end, approval reference and the POC % of each month;
  - **ACTUAL POC:** the POC % reached in each month.
- `cost_plan_import` saves the rows together, each with the same rights and checks as a single save. A refused row refuses the whole upload and names the row. Each saved plan returns to Draft, with "Bulk upload: file name" in its history.
- The actual POC of a month is used where that month has no released cost report.

## Step 2: Check it (1 minute)

1. Sign in as the costing coordinator (or a super admin) and reload the page.
2. **Cost Control → Cost plan → Download the template.** Change one project's planned cost for a month.
3. **Upload the cost plans (Excel).** The preview shows one **Change** row and **No change** for the rest. Press **Save the 1 new or changed plan**.
4. From v3.43 the actual POC has its own monthly file: under **Actual POC upload**, choose last month, **Download the month's template**, enter one project's POC in the month and upload it. Press **Save the actual POC of … for 1 project**.
5. Open that project's plan: the internal plan shows **Draft** with the new figures, the uploaded actual is marked **u**, and the history has both uploads.

## To undo

Run `supabase/schema-rollback-v46.sql`. The bulk upload is then refused and a single save no longer takes the actual POC. The uploaded actual POC is kept and still used; running v46 again brings the upload back.
