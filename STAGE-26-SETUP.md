# v3.23 setup: intermediate milestones and progress by phase, on the server

This takes about 5 minutes. **Do not** upload a new `config.js`.

Run these first:
- the v17 update (STAGE-14-SETUP, material tracking and the schedule rows' WBS);
- the v22 update (STAGE-18-SETUP, actual against baselines).

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v30.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select (select count(*) from pg_tables where tablename in ('key_milestones','key_milestone_audit')) + (select count(*) from pg_proc where proname in ('key_milestone_act','pt_key_ms','pt_phase_tbl','release_act_km','pt_km_update')) + array_length(pt_phases(), 1) as installed;
   ```

   Expect **15**: two tables, five functions and the eight phases.

**What the update does:**
- **`pt_phases()`:** lists eight phases; energization is a phase of its own.
  - The internal weightage can give it a weight.
  - Updated schedules uploaded from now on report it in their summary.
- **`key_milestones`:** each project's intermediate milestones.
  - **Who adds and removes them:** a planning engineer of the project or a super admin, through `key_milestone_act`.
  - **What each one is:** an activity or WBS element of the latest updated schedule.
  - **Removing:** a removed milestone is kept, marked inactive. Every change is in `key_milestone_audit`.
- **`pt_key_ms`** and **`pt_phase_tbl`:** work out a report's milestones (baseline, forecast, actual, delay) and its progress by phase, including the daily-report comparison of the site phases, from the updated schedule in force at the end of the period.
- **`release_act_km`:** saves an internal or client report through `release_act_bl` and writes the server's own figures into it. Approval freezes them.

## Step 2: Publish

Tell Claude "it showed 15". Claude publishes v3.23, and **live.html** uses it within about 2 minutes. Then press **Ctrl + F5**.

## Step 3: Check it (3 minutes)

| Do | Expect |
|---|---|
| As a planning engineer: **Internal Reporting**, a project with an updated schedule, a new period → **Milestones** → **Add a milestone**, a WBS element, finish | The preview shows baseline, forecast and delay. After saving, it is listed with its status. |
| The same with a P6 milestone ID | Its own baseline and forecast or actual |
| **Progress** tab | Every phase with internal weight, planned, actual, weighted shares and the overall internal progress. Construction and installation show the daily reports and the difference. |
| **Save draft**, submit; as the section planning manager, approve | The released report keeps the milestones and the table. Removing a milestone afterwards does not change it. |
| **Client Reporting**, the same project → Milestones and Progress by phase | Only the milestones for the client; phases weighted by the schedule's own weighting |
| As a site engineer, try to add a milestone | Refused: only the planning engineers of the project or a super admin |

**To undo:** run `schema-rollback-v30.sql`.
- Nobody can add or remove intermediate milestones.
- Reports save as in v3.22.
- The phases go back to seven.
- Everything already saved is kept.
