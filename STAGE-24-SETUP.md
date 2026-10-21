# v3.21 setup: the cash-out forecast from the material POs and the cost report, on the server

This takes about 5 minutes. **Do not** upload a new `config.js`. Two updates must be in first:
- v17 (STAGE-14-SETUP, Material Tracking)
- v27 (STAGE-23-SETUP, the cash-out forecast)

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v28.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select (select count(*) from pg_tables where tablename in ('co_mat_po','co_heads')) + (select count(*) from pg_proc where proname in ('cashout_act','cashout_act_v27','pt_co_mat_ms')) + (select count(*) from pg_policies where tablename in ('co_mat_po','co_heads')) + ((cashout_features() ->> 'version') = '28')::int as installed;
   ```

   Expect **8**: two tables, three functions, two read rules and the version.

**What the update does:**
- **`co_mat_po`:** the value, currency, payment terms and milestones of each PO number in Material tracking.
  - A PO number that is not in Material tracking for the project is refused.
  - A changed value needs its revision reference and reason.
  - A paid milestone keeps what was paid, unless the costing coordinator, the Head or a super admin changes it with a reason.
  - At approval, the page sends each milestone's date (from the latest updated schedule). The server keeps it as the milestone's baseline.
- **`co_heads`:** how each WBS head of the monthly cost report enters the forecast (material POs, subcontract POs, cost report, excluded), and whether the ETC of the PO heads is included.
- **`cashout_act`:** gains these changes; every v27 action works as before (the v27 function is kept as `cashout_act_v27`).
- **Rights:** as in v27. The costing engineers of the project, the coordinator, the Head and super admins change; the coordinator, the Head and super admins approve; cost-figure viewers read the projects in their access.

## Step 2: Publish

Tell Claude "it showed 8". Claude publishes v3.21, and **live.html** uses it within about 2 minutes. Then press **Ctrl + F5**.

## Step 3: Check it (3 minutes)

| Do | Expect |
|---|---|
| As a costing engineer: **Materials & Procurement → Material tracking**. Under a PO number, **Add payment terms**. Enter the value, **Use a standard schedule**, save | Saved. Material tracking shows the PO value and *4 payment milestones* |
| As the coordinator: open the same PO, **Approve the payment terms** | Each milestone shows its baseline date |
| **Cash-out forecast → PO payment schedules → Cost report heads**: set *Electrical Manpower* to *Subcontract POs*, save | Saved; the forecast no longer counts it from the cost report |
| Change the PO value without a revision reference | Refused: "The PO value changed: give the revision reference and the reason" |

**To undo:** run `schema-rollback-v28.sql`. `cashout_act` is the v27 function again, and the material PO terms and head treatments are kept, read-only.
