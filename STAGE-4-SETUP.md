# Phase 4: lifecycle, actions and dashboards (ProTrackAI v2.7)

Version 2.7 adds three things:

- **The governed 12-stage project lifecycle.** Each stage has an owner, due date, required deliverables, approval and history.
- **Actions and approvals:** one list of everything waiting on someone.
- **Two dashboards:** the Planning dashboard and the Cost Control dashboard.

It takes about 15 minutes. **Do not** upload a new `config.js`.

## Step 1: Update the database (5 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v6.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the two lines, without the ``` marks:

   ```sql
   select count(*) as installed from pg_proc where proname in ('lifecycle_act','pt_lc_template','pt_lc_approver','pt_lc_dept');
   ```

   Expect **4**.

The update only adds two tables and their functions. No existing table, column or row is changed. Running it twice is safe.

## Step 2: Publish

Tell Claude "it showed 4". Claude merges the prepared update, and your site shows **v2.7** within about 2 minutes. Then press **Ctrl + F5** on the site.

## Step 3: Set up each project (5 minutes per project)

1. Go to **Projects & Handover → Project overview** and pick the project. You see 12 stages, all **Not started**.
   - On the server nothing is filled in for you: a stage only shows what someone recorded.
2. As project manager, open each stage that is under way. Choose the **owner** and **due date**, then press **Save changes**.
   - For a stage that does not apply, press **Not applicable** and give a reason.
3. The owner opens the stage, ticks the deliverables that are done and fills in the next action.
   - When every **Required** box is ticked, the owner presses **Submit for approval**.

## Step 4: Test (5 minutes)

| Who | Does | Expect |
|---|---|---|
| Owner (for example the planning engineer, stage 6) | Ticks all required deliverables and presses **Submit for approval** | The stage turns amber: **Awaiting approval** |
| Owner | Looks for an Approve button | There is none |
| Project manager | Opens **Actions and approvals** | Sees "Stage 6 … approve or return" under **Mine** |
| Project manager | Presses **Approve** | The stage turns green: **Complete**. The history shows both people. |
| Foreman | Opens a stage | Read-only |
| Costing engineer | Opens the **Cost Control dashboard** | Commitments and accruals say **Not tracked yet**. The reconciliation shows the last costing file and invoice register batches. |
| Site engineer | Looks at the menu | No Planning or Cost Control dashboard |

## If something goes wrong

| What you see | What to do |
|---|---|
| Amber box: "Lifecycle tracking needs the v6 database update" | Step 1 has not run on this project. Run `schema-update-v6.sql`. |
| "You submitted this stage, so someone else must approve it" | This is intended. Ask another project manager or a super admin. |
| "Required deliverables are not done" | Tick each Required item, or have the project manager mark the stage Not applicable. |

**To undo:** run `schema-rollback-v6.sql`. It removes the functions and keeps every stage and its history.
