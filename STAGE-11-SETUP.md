# v3.5 setup: the progress release dashboard and regional approval

This takes about 10 minutes. **Do not** upload a new `config.js`.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v14.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select (select count(*) from pg_proc where proname in ('release_setup','pt_rel_approver','pt_rel_plan_calc','pt_rel_decider')) + (select count(*) from release_settings) as installed;
   ```

   Expect **5**: four functions and one setting.

**What the update does:**
- lets each region's planning section manager approve that region's progress releases
- adds the optional project manager review (switched off)
- works out the dashboard figures on the server

Nothing existing changes, and running it twice is safe. Until you name a planning section manager for a region, the Head of Planning and Cost Control approves that region's releases, exactly as now.

## Step 2: Publish

Tell Claude "it showed 5". Claude merges the update, and **live.html** shows **v3.5** within about 2 minutes. Then press **Ctrl + F5**.

## Step 3: Name the planning section managers (5 minutes, super admin)

1. **Give each section manager access.** In **Administration → Users and access**, open (or add) each regional planning section manager.
   - Role: **Planning Engineer**. Title: e.g. "Planning Section Manager, Central".
   - Tick **every project of their region**. A planning user sees projects one by one, so tick new projects too when they are added.
2. **Name them.** Go to **Administration → Approval matrix**, scroll to **Progress release approval**, and pick the person under **Add** for their region.
   - A region can have more than one.
   - The ✕ next to a name removes it.
3. **Leave the box** "The project manager reviews each progress release…" **unticked** for now. Tick it later if management wants the project manager to review first.

## Step 4: Try it on live.html (5 minutes)

| Who | Does | Expect |
|---|---|---|
| Planning engineer | **Planning & Scheduling → Progress releases → Open** | The release fills the screen, with the KPI cards and seven tabs |
| Planning engineer | Fills **Milestones**, **Progress** (external %), **Manpower** and **Energization**, then **Save draft** | The delays, variance, SPI and manpower totals appear; the KPI colours change |
| Planning engineer | **Submit for approval** | The Approval tab names the section manager for the region |
| Planning section manager | **Projects & Handover → Actions and approvals**: "approve or reject" | Opens the release |
| Planning section manager | Types **Management remarks** (Release notes tab) → **Approve and release** | Released; the remarks show in **Executive report → Project view** |
| A project manager | Tries to approve | No button; the server refuses too |

## If something goes wrong

| What you see | What to do |
|---|---|
| Amber box in Approval matrix: "Regional approval needs the v14 database update" | Step 1 has not run. Run `schema-update-v14.sql` |
| The section manager has no Approve button | Check they have the project ticked (Step 3, part 1) and are named for that project's region (Step 3, part 2) |
| "You submitted this version, so someone else must approve it" | Intended: nobody approves their own submission |
| "The project manager must review this progress release before it is approved" | The project manager review is ticked; the project manager reviews first, or untick it |

**To undo:** run `schema-rollback-v14.sql`. The Head approves progress releases again, as in v3.4. All figures, remarks and names are kept.
