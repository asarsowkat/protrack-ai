# v3.20 setup: the cash-out forecast, on the server

This takes about 15 minutes. **Do not** upload a new `config.js`. Two earlier updates must be in first:
- v7 (STAGE-4B-SETUP, the costing coordinator and Head of Planning and Cost Control positions)
- v16 (STAGE-13-SETUP, roles and rights)

## Step 1: Update the database (3 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v27.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
   - If it says **"Run schema-update-v7.sql and schema-update-v16.sql (STAGE-13-SETUP) first"**, do the setup that is missing, then run this again.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select (select count(*) from pg_tables where tablename in ('co_actuals','co_batches','co_opening','co_po_terms','co_other_lines','co_versions','co_reviews','co_scenarios','co_maps','co_audit')) + (select count(*) from pg_proc where proname in ('cashout_act','cashout_features','pt_co_keeper','pt_co_uploader','pt_co_approver','pt_co_publisher','pt_co_ms')) + ('cashout.keep' = any(pt_rights()))::int + ('cout' = any(pt_screens()))::int + pt_right_default('costing','cashout.keep')::int as installed;
   ```

   Expect **20**: ten tables, seven functions, the new right, the new screen and the costing engineers' default.

**What the update does:**
- **Finance actuals** (`co_actuals`, `co_batches`):
  - the cumulative cash-out per project and month, in SAR
  - imported only by the super admin or the Head Office cost control coordinator, on the projects in their access
  - each import is recorded with its file fingerprint, cutoff, projects and counts; the same file is imported once
  - a period already imported with another amount needs the correction workflow (tick and reason); the original stays, marked superseded
  - an actual is never deleted or changed in any other way (the server refuses)
- **Payment terms** (`co_po_terms`):
  - each purchase order's milestones, kept by the new right *Keep the cash-out forecast of their projects*: costing engineers, the costing coordinator, the Head of Planning and Cost Control and super admins
  - the server applies the same rules as the page: percentages and amounts, dates, payment days, the evidence of a paid milestone, and no change to a paid milestone without an approver and a reason
  - approval (coordinator, Head or super admin) sets each milestone's baseline payment date
  - a PO revision changes `purchase_orders.po_value` and is recorded with its reference and reason
- **Other cash-out lines, scenarios, versions and reviews:**
  - kept as on the demo page
  - a version is reviewed by someone other than its author and published by the Head or a super admin
  - a published version can never change
  - an over-budget version is published only after the management review is recorded
- **Who reads:** everyone who sees cost figures, on the projects in their access only.
- **The audit:** every change is in `co_audit`, which cannot be changed.
- **The approved current budget** stays where it is: the released monthly cost reports. The update never changes a budget.

Running it twice is safe.

## Step 2: Publish

Tell Claude "it showed 20". Claude publishes v3.20, and **live.html** uses it within about 2 minutes. Then press **Ctrl + F5**.

Until the update is in, **Invoices & Cash Flow → Cash-out forecast** on live.html says it needs the v27 database update.

## Step 3: Check it (10 minutes)

| Do | Expect |
|---|---|
| As the costing coordinator: **Cash-out forecast → Finance actuals**. Tick a project, choose last month as the cutoff, **Download template**, fill one row and import it | "Imported FCO-…: 1 new". The month shows in *Actual cash-out* |
| Import the same file again | Refused: "This file was already imported" |
| Import a file with another amount for the same month, without the tick | Refused; with the tick and a reason, imported as a correction. The original is listed as *restated* |
| As a costing engineer: **PO payment schedules**, open a PO, **Use a standard schedule**, save | Saved, with the milestones *Draft*. As the coordinator: **Approve the payment terms**; each milestone shows its baseline date |
| Mark a milestone **Paid** without evidence | Refused: "a paid milestone needs its evidence" |
| As a project manager | The figures are shown; no import panel, and the PO terms are view only |
| On a project over its budget: save a version, review it as someone else, then publish it as the Head | Refused until **Record the review** is done; then published |

To see what the server saved (it only reads):

```sql
select project_id, period, cum, superseded_by is not null as superseded, reason, batch_id from co_actuals order by project_id, period, created_at;
```

## If something goes wrong

| What you see | What to do |
|---|---|
| "The cash-out forecast needs the v27 database update" | Step 1 has not run, or live.html was not refreshed. Run the check in step 1, then press Ctrl + F5 |
| "Only the super admin or the Head Office cost control coordinator imports Finance cash-out" | Mark the person as costing coordinator in Settings → Users and access (PCC checks) |
| "Budget Not Configured" on a project | No monthly cost report with an approved budget has been released for it. Release the cost report; the module never uses PO values as a budget |
| "pt_right_default does not have the expected shape" | The rights defaults were changed by hand on this database. Ask Claude for the one line to add |

**To undo:** run `schema-rollback-v27.sql`. Nobody can change cash-out data any more, and everything stays readable. Every record, import and audit entry is kept.
