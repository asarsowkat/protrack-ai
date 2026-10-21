# v3.9 setup: material tracking in released reports, and executive report layouts on the server

This takes about 10 minutes. **Do not** upload a new `config.js`. The v17 update (STAGE-14-SETUP) must be in first.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v18.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
   - If it says **"Run schema-update-v17.sql (Material Tracking) first"**, do STAGE-14-SETUP first, then run this again.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select (select count(*) from pg_proc where proname in ('pt_mat_snapshot','pt_xr_layout_ok')) + (select count(*) from information_schema.tables where table_schema='public' and table_name in ('xr_layout_default','xr_layouts')) + (select count(*) from information_schema.columns where table_schema='public' and table_name='report_releases' and column_name='mat_snapshot') as installed;
   ```

   Expect **5**: two functions, two tables and one column.

**What the update does:**
- when an internal report is approved, saves the project's material status with it, like the open issues. Only monitored materials, from the latest updated schedule, with the same rules as the Material tracking page. A released version keeps it and it cannot be changed
- keeps the layout of the **Executive report (released)** on the server:
  - one default for everyone, which only super admins can change, with each change in the Change log
  - one layout per person, which only that person can read and change

Nothing else changes, and running it twice is safe.

## Step 2: Publish

Tell Claude "it showed 5". Claude merges the update, and **live.html** shows **v3.9** within about 2 minutes. Then press **Ctrl + F5**.

## Step 3: Check it (5 minutes)

| Do | Expect |
|---|---|
| As a super admin: **Home → Executive report (released) → Summary → Customise this report → Default for everyone**, hide one section | The report hides it. "Last changed by" shows your name |
| Sign in as someone else (another browser or computer) and open the same report | The section is hidden for them too |
| As that person: **Customise this report**, move a section up | Their report keeps it, on any computer they sign in from. The super admin's view does not change |
| As that person: **Reset to the default** | Back to the super admin's default |
| Approve a submitted internal report of a project with Material tracking set up | **Executive report (released)** for that period shows the project in **Material tracking** and the **Materials delivered** tile |

Reports approved **before** this update have no material status saved with them. For those projects, the Executive report shows **"Not in the released report"** until the next report is approved. Released versions are never changed afterwards.

## If something goes wrong

| What you see | What to do |
|---|---|
| Amber box on the Executive report: "… need the v18 database update" | Step 1 has not run. Run `schema-update-v18.sql` |
| "The layout was not saved on the server" | The page shows what the server keeps. A person who is not a super admin cannot change the default |
| "This report layout is not valid" | Press **Reset to the default** and customise again |
| A project shows "Not in the released report" | Its report for that period was approved before the update, or Material tracking was not set up when it was approved |

**To undo:** run `schema-rollback-v18.sql`. It goes back to v3.8:
- approving an internal report no longer saves the material status
- layouts are kept in each browser again, and the Executive report shows the amber box

Everything already saved (the material status of released reports and every layout) is kept. It comes back if `schema-update-v18.sql` is run again.
