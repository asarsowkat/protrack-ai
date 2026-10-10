# v3.3 setup: monthly cost report in the company format

This takes about 5 minutes. **Do not** upload a new `config.js`.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v12.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select count(*) as installed from pg_proc where proname in ('release_act','pt_cost_wbs');
   ```

   Expect **2**.

The update changes no tables. It lets cost reports carry WBS lines and works out their figures on the server. Running it twice is safe.

## Step 2: Publish

Tell Claude "it showed 2". Claude merges the update, and **live.html** shows **v3.3** within about 2 minutes. Then press **Ctrl + F5**.

## Step 3: Try it on live.html (3 minutes)

| Who | Does | Expect |
|---|---|---|
| Costing engineer | **Cost Control → Monthly cost report**, this month, **Prepare** | The form in the company format, one row per WBS head |
| Costing engineer | **Fill from Excel (company format)** with your monthly sheet for that project | The lines, TCC, POC and contract value filled in; any difference between the file's Overall row and its lines is pointed out |
| Costing engineer | Adds a justification to each line with a supplement or saving, then **Submit for approval** | Submitted (without the justifications it is refused, naming the lines) |
| You | Approve it | Released |
| A project manager or executive | **Home → Executive report → Project view** | "Cost report by WBS head", with **Export to Excel** |

**The first report:** enter the previous version (C) once. From the next month, C comes from the released report.

## If something goes wrong

| What you see | What to do |
|---|---|
| "the server needs the v12 database update" when saving | Step 1 has not run. Run `schema-update-v12.sql` |
| "Give a justification for each WBS line with a supplement or saving" | Intended. Fill in the justification for the lines named |
| A draft from the quick upload shows totals only | Press **Use the company format by WBS head** |

**To undo:** run `schema-rollback-v12.sql`. Cost reports then work by totals only, as in v3.2. Every report already saved, including those by WBS head, is kept and readable.
