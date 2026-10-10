# v3.2 setup: activity quantities in the daily report

This takes about 5 minutes. **Do not** upload a new `config.js`.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v11.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select count(*) as installed from pg_proc where proname in ('dpr_act','pt_dpr_over') and (proname <> 'dpr_act' or pronargs = 5);
   ```

   Expect **2**.

The update adds one table for the justifications and lets the review step accept them. Nothing existing changes. Running it twice is safe.

## Step 2: Publish

Tell Claude "it showed 2". Claude merges the update, and **live.html** shows **v3.2** within about 2 minutes. Then press **Ctrl + F5**.

## Step 3: Try it on live.html (3 minutes)

| Who | Does | Expect |
|---|---|---|
| Foreman or site engineer | **Daily Reports → New report**, choose an activity | Total quantity (scope), executed up to yesterday, balance, balance duration and plan for today |
| Foreman | Enters an actual quantity larger than the balance and submits | An amber note says the quantity is beyond the scope; the report is accepted |
| Site engineer | Opens it from **Daily reports** (marked "Beyond scope") and presses **Mark as reviewed** | Asked to justify the quantity variation; after writing it, the report is reviewed and the justification shows in the report and its audit trail |
| Site manager | Approves | Approved. If the quantity was changed after the review, approval is refused until it is justified again |

## If something goes wrong

| What you see | What to do |
|---|---|
| "The server refused this … (the server needs the v11 database update)" when reviewing | Step 1 has not run. Run `schema-update-v11.sql` |
| "Justify the quantity variation … for: …" | Intended. Write a few words for each activity listed |
| "has not been justified by the reviewer" when approving | Intended. Return the report to the site engineer |

**To undo:** run `schema-rollback-v11.sql`. Reviews then work as in v3.1, without justifications. Every justification already recorded is kept.
