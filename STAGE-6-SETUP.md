# v3.0 setup: released reporting

This takes about 10 minutes. **Do not** upload a new `config.js`.

## Step 1: Update the database (3 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v9.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select count(*) as installed from pg_proc where proname in ('release_act','log_import','pt_supp_approved','pt_release_staff');
   ```

   Expect **4**.

The update only adds tables and functions, and lets import batches record the two logs. Running it twice is safe.

## Step 2: Publish

Tell Claude "it showed 4". Claude merges the update, and **live.html** shows **v3.0** within about 2 minutes. Then press **Ctrl + F5**.

The main address keeps showing sample data until go-live. The sample data includes released reports and logs, so you can show the new screens there.

## Step 3: Try it on live.html (5 minutes)

| Who | Does | Expect |
|---|---|---|
| Planning engineer | **Planning & Scheduling → Progress releases**, this month, **Prepare** beside a project. Changes one figure with a reason, adds key issues, then **Submit for approval** | It shows **Awaiting approval** |
| You | **Actions and approvals → Mine**, open it, **Approve and release** | It shows **Released rev 0** |
| A project manager or executive | **Home → Executive report (released)** | That project's released progress and key issues. Projects not released show **Not released** |
| Costing engineer | **Cost Control → Monthly cost report**: types the Rev-0 budget, actual, commitments and forecast to complete, then submits | Approved budget, EAC and VAC are worked out |
| Costing engineer or coordinator | **Claims & Variations → Change order and claim log**: downloads the template, fills it in, chooses the month, uploads | The log for that month, with totals |
| Costing engineer or coordinator | **Cost Control → Budget supplements**: uploads the supplement log | Approved supplements are added to the budget in the next cost report |

## If something goes wrong

| What you see | What to do |
|---|---|
| Amber box: "Releases need the v9 database update" | Step 1 has not run. Run `schema-update-v9.sql` |
| "You submitted this version, so someone else must approve it" | Intended. Ask another super admin or the Head |
| "This period is already released; use Revise" | Intended. Press **Start a new revision** and give a reason |
| An upload refuses rows | Read the reason beside each row, fix the file, or tick the box to save the others |

**To undo:** run `schema-rollback-v9.sql`. It removes the writing functions and keeps every release and log.
