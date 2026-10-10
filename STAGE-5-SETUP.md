# Phase 5: governed RASA answers (ProTrackAI v2.9)

This takes about 5 minutes. **Do not** upload a new `config.js`.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v8.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select count(*) as installed from pg_policies where policyname in ('inv_read','uh_read','ib_read') and qual like '%pt_money_ok%';
   ```

   Expect **3**.

The update changes only who can read invoice and costing rows: foremen, site engineers and site managers no longer receive them. No data changes, and running it twice is safe.

## Step 2: Publish

Tell Claude "it showed 3". Claude merges the update, and your site shows **v2.9** within about 2 minutes. Then press **Ctrl + F5** on the site.

## Step 3: Test (3 minutes)

| Who | Asks RASA | Expect |
|---|---|---|
| You | "EAC forecast" | The answer, then a **Based on** line naming the daily reports (count, dates, approved), the baseline, the rates and the data date |
| You | "What are the accruals?" | **No evidence in ProTrackAI**: accruals are not tracked |
| You | "What is waiting for me" | Your items from Actions and approvals |
| You | "Tender register" | Pre-award count and the next PE number |
| A foreman or site engineer | "Invoiceable value" | **Not available for your role**, with no SAR figures |
| Anyone | A question RASA can't answer from the records, such as "What colour is the site office?" | **No evidence in ProTrackAI for that question**, saying no project data is sent to any outside AI service |

Settings → System now has a row **RASA and outside AI** stating the policy.

## If something goes wrong

| What you see | What to do |
|---|---|
| A site manager's executive summary shows invoiced SAR 0 | Tell Claude; it should be hidden for that role |
| The check shows fewer than 3 | Step 1 has not fully run. Run `schema-update-v8.sql` again |

**To undo:** run `schema-rollback-v8.sql`. It puts back the previous read rules. No data is touched.
