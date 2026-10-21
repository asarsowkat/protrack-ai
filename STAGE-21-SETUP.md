# v3.19.1 setup: the delay register's drop-down lists, on the server

This takes about 5 minutes. **Do not** upload a new `config.js`. The v24 update must be in first (STAGE-20-SETUP, the delay events register).

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v25.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
   - If it says **"Run schema-update-v24.sql (STAGE-20-SETUP) first"**, do STAGE-20-SETUP, then run this again.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select (select count(*) from pg_proc where proname in ('delay_lists_set','pt_dly_list','pt_dly_list_default')) + (select count(*) from delay_lists) + (select count(*) from pg_policies where tablename in ('delay_lists','delay_list_audit')) + (pt_dly_label('owner') = 'Claim owner')::int as installed;
   ```

   Expect **12**: three functions, the six lists, their two read rules and the new labels.

**What the update does:**
- **`delay_lists`** keeps six lists of the company workbook, starting with the workbook's items word for word: claim identification, entitlement, liability, concurrency, mitigation and claim owner. The event status list stays *Ongoing / Closed*: it decides the closing date and the claim duration.
- **Who changes a list:** the super admin only, in **Settings → Delay register lists**. The server checks it, whatever the page shows. It also checks:
  - 1 to 60 items per list
  - none empty, at most 200 characters
  - no two alike, whatever the case
- **History:** every change is kept in `delay_list_audit`, which cannot be changed.
- **Who reads the lists:** everyone signed in.
- **Saving an event or uploading the register:**
  - a value must be in its list; the list's spelling is kept
  - an event keeps a value removed from its list since
  - another value is refused: *"Liability party: "The client" is not in the list. A super admin can add it in Settings → Delay register lists"*

Nothing else changes. Running it twice is safe.

## Step 2: Publish

Tell Claude "it showed 12". Claude publishes v3.19.1, and **live.html** uses it within about 2 minutes. Then press **Ctrl + F5**.

Until the update is in, live.html uses the workbook's lists. Settings → Delay register lists says the lists need the v25 update and cannot be changed.

## Step 3: Check it (3 minutes)

| Do | Expect |
|---|---|
| As the super admin: **Settings → Delay register lists**. Under *Liability List*, add `Utility Company` | Saved. Reload (Ctrl + F5): it is still there, last in the list |
| As a planning engineer: open a delay event, choose **Utility Company** as the liability party, save | Saved |
| As the super admin, **Remove** Utility Company | Asks to confirm, saying one event keeps it. The event shows *Utility Company (not in the list)* and can still be saved |
| Upload a register with `The client` as the liability party | That row is refused: "Liability party: "The client" is not in the list…" |
| As a planning engineer, open Settings | Not offered: only the super admin changes the lists |

To see what the server holds (it only reads):

```sql
select key, items, (select name_of(updated_by)) as by, updated_at from delay_lists order by key;
```

## If something goes wrong

| What you see | What to do |
|---|---|
| "The lists need the v25 database update (see STAGE-21-SETUP)" | Step 1 has not run, or live.html was not refreshed. Run the check in step 1, then press Ctrl + F5 |
| "Only a super admin changes the lists" | Sign in as the super admin |
| "Run schema-update-v24.sql (STAGE-20-SETUP) first" | Do STAGE-20-SETUP, then run this update again |

**To undo:** run `schema-rollback-v25.sql`. It removes `delay_lists_set` and the list check. The events accept any value in those columns again, as in v24. The lists and their history are kept.
