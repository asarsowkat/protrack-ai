# v3.6 setup: internal weightage, updated schedules, internal and client reporting

This takes about 15 minutes. **Do not** upload a new `config.js`.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v15.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select (select count(*) from pg_proc where proname in ('phase_setup_save','schedule_update_commit','pt_rel_sched','pt_sched_summary')) + (select count(*) from information_schema.tables where table_schema='public' and table_name in ('project_phase_setup','schedule_updates','schedule_update_rows')) as installed;
   ```

   Expect **7**: four functions and three tables.

**What the update does:**
- keeps each project's internal weightage by phase
- keeps the updated schedules you upload, for good
- adds client reports
- makes the approver validate any difference between a report and the updated schedule

Nothing existing changes, and running it twice is safe.

## Step 2: Publish

Tell Claude "it showed 7". Claude merges the update, and **live.html** shows **v3.6** within about 2 minutes. Then press **Ctrl + F5**.

## Step 3: Set the internal weightage (planning engineer, once per project)

1. **Planning & Scheduling → Baselines and P6 import**, and choose the project.
2. In **Internal weightage by phase**, enter the % agreed with management for each phase. The total must show **100.00%**.
3. Press **Save weightage**.

## Step 4: Upload the updated schedule (planning engineer, each week or month)

1. On the same page, in **Updated schedule**:
   - Tick **Client weightage**. Your schedules are loaded with the client weightage.
   - Press **Choose updated XER** and select the P6 export.
2. Check the preview:
   - **Data date:** taken from the file.
   - **Client weighting taken from:** the weighting resource. It is usually already right.
   - **Phase taken from:** "Main WBS branch". Your main WBS branches are the seven phases, so each is suggested automatically. Change any that are wrong.
   - **The figures:** client and internal planned and actual %, by phase, and the TCC, PAC and FAC dates.
3. Press **Save updated schedule**. It is listed under **Updates loaded**.

## Step 5: Try it on live.html (5 minutes)

| Who | Does | Expect |
|---|---|---|
| Anyone | **Projects & Handover → Project overview** for that project | Progress says "internal weightage, schedule of …" |
| Planning engineer | **Planning & Scheduling → Internal Reporting → Open** | The banner names the updated schedule; progress and milestone dates are filled from it |
| Planning engineer | Changes the actual % (with a reason) and submits | "Differs from the updated schedule" with the difference listed |
| Planning section manager | **Actions and approvals** → opens it → ticks **I have checked these differences**, writes a note → **Approve and release** | Released; the validation is shown in the report |
| Planning engineer | **Planning & Scheduling → Client Reporting → Open** → writes the notes → submits | Client figures, phases, milestones and look-ahead from the schedule |
| Planning section manager | Approves the client report, then **Print or save as PDF** or **Export to Excel** | A client report with client-weighted figures only |

## If something goes wrong

| What you see | What to do |
|---|---|
| Amber box: "Internal weightage and updated schedules need the v15 database update" | Step 1 has not run. Run `schema-update-v15.sql` |
| "The internal weightage must add up to 100%" | Correct the figures so the total shows 100.00% |
| "… weighted activities have no phase" | In the preview, give every main WBS branch a phase |
| "This report differs from the updated schedule … Validate the differences" | The approver ticks the check box and writes a note before approving |
| "Give a reason for changing the internal weightage" | Schedules were already reported with it. Write the reason in the box above **Save weightage** |

**To undo:** run `schema-rollback-v15.sql`. It goes back to the v3.5 rules. Every weightage, updated schedule, client report and validation is kept and stays readable.
