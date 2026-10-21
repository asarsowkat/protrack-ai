# v3.29 setup: the budget supplement log by user field and category

This takes about 5 minutes. **Do not** upload a new `config.js`. It needs the v20 update (STAGE-16-SETUP). Try this on a staging copy first: this update has not yet been run on a database.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v35.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select supp_features(), jsonb_array_length(pt_supp_lists() -> 'uf') as user_fields, jsonb_array_length(pt_supp_lists() -> 'cats') as categories;
   ```

   Expect `{"version": 35, "supplement_log": true}`, **19** and **24**.

**What the update does:**
- **New columns** on the budget supplement log: user field, unified category, WBS group, WBS ID and WBS description. The old fixed list of seven categories is lifted; rows already there are not changed.
- **The lists:** one row with the user fields and the categories with their unified category. Everyone signed in reads it; only a super admin changes it (`supp_lists_set`). Cont. Value must stay in the list.
- **Changes on the screen** (`supp_update`): add, change and remove rows of a project's latest log, or start this month's version from it. Only someone with the right to upload logs, on a project they can access. Each change is kept in `supp_audit`, which cannot be changed.
- **Uploads** (`log_import`) check each row against the lists, fill the unified category and refuse what does not fit, with the reason.
- **Budget change for the cost report** (`pt_supp_approved`): −(the amounts of the rows that are not Cont. Value). Logs uploaded before the update keep their rule.

## Step 2: Check the lists (1 minute, super admin)

1. Sign in as the super admin and reload the page.
2. **Settings → Supplement lists**: the user fields and the categories with their unified category. Add what the company uses with **Add**, remove what it does not with ✕. Each change is saved at once.

## Step 3: Check (2 minutes)

- As the costing engineer or costing coordinator, open **Cost Control → Logs → Budget supplements**, pick a project and press **Download the template**. Fill a row with a user field and a category of the list and upload it as this month's log.
- The row shows in one of Supplement, Savings, VO Cost or VO Price, and the **Net value** is its amount. A row with a category that is not in the list is refused with the reason.
- **Edit in the grid** (v3.30): change an amount, add a row with **Add row**, delete one with ✕, then **Save** (give a reason for the deletion): each change is listed under *Changes on this screen*.
- As the super admin, choose *All projects in scope* and filter by region or unified category.

## To undo

Run `schema-rollback-v35.sql`. Nobody can change rows on the screen or the lists any more, and uploads go back to the earlier layout. The new columns, the lists and the history are kept, so running v35 again brings everything back. Rows saved in the new layout then count in the budget by their signed amounts, as the earlier rule does.
