# v2.8 setup: Tender register, PE numbers and stages 1 to 5

This takes about 10 minutes. **Do not** upload a new `config.js`.

## Step 1: Update the database (5 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v7.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
   - A notice saying "the PE uniqueness index was not created" means two of your existing projects share a code. Tell Claude: ProTrackAI still checks every new number, but the extra database guard is off until that is fixed.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select count(*) as installed from pg_proc where proname in ('tender_act','pe_proposal','pcc_designate','pt_pe_canon','pt_lc_boss');
   ```

   Expect **5**.

The update only adds columns, tables and functions. It also changes the stage 1 to 5 checklists that are not started or in progress, keeping every tick. Running it twice is safe.

## Step 2: Publish

Tell Claude "it showed 5". Claude merges the update, and your site shows **v2.8** within about 2 minutes. Then press **Ctrl + F5** on the site.

## Step 3: Name the people (2 minutes)

1. **Settings → Users and access**, then open your own name. Tick **Head of Planning and Cost Control** and save.
2. Open your costing coordinator. Tick **Costing coordinator** and save.
   - Give them **Project access** to the projects they should see.
   - Projects they register later are added to their access automatically.

## Step 4: Test (3 minutes)

| Who | Does | Expect |
|---|---|---|
| Costing coordinator | **Projects & Handover → Tender register → Register an L1 project** | The PE number is filled in, for example PE-330 after your PE-329, and cannot be edited |
| Costing coordinator | Enters a TE number and name, then presses **Register** | A new row shows **Pre-award**. The project overview shows stages 1 to 4 owned by the coordinator |
| Costing coordinator | Registers the same TE number again | Refused: "already registered" |
| Costing coordinator | Ticks stage 1 and presses **Submit for approval** | You see it under **Actions and approvals → Mine** |
| A project manager | Opens that stage | No Approve button. Stages 1 to 5 are yours |
| You | Press **Approve** | Stage 1 becomes Complete |
| Costing coordinator | In the register, opens the project and enters the contract signing date | Stage 4 is due 7 days later |
| You | Cancel a test project with a reason | It shows **Cancelled**, and its PE number becomes the next proposal |

You can try all of this first, without touching live data, on `demo.html`. There, Asarudeen is the Head and Priya Raman is the costing coordinator.

## If something goes wrong

| What you see | What to do |
|---|---|
| Amber box: "The Tender register needs the v7 database update" | Step 1 has not run. Run `schema-update-v7.sql` |
| "Only the costing coordinator, the Head of Planning and Cost Control or a super admin can register…" | Tick the designation on that person (Step 3) |
| "… is already given to a live project" | That PE number is in use. Leave the proposal, or, as super admin, type a free number |
| "Tender details, PE numbers and cancellations are recorded in the Tender register" | Intended: these change only through the register |

**To undo:** run `schema-rollback-v7.sql`. It puts back the v6 rules and keeps every project, TE number, PE history entry and stage.
