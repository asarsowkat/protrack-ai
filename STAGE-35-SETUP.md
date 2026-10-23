# v3.37 setup: Budget & Cost Management stage 3 (financial controls)

This takes about 15 minutes. **Do not** upload a new `config.js`. It needs v39 (STAGE-33-SETUP) and v40 (STAGE-34-SETUP).

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `supabase/schema-update-v41.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select bcm_features() ->> 'version' as version, (select count(*) from pg_proc where proname in ('bcm_stage3','bcm_version_act','bcm_totals','pt_bcm_eval','pt_bcm_sap_id','pt_bcm_tol')) as functions, (select count(*) from information_schema.tables where table_schema = 'public' and table_name in ('bcm_roles','bcm_dups','bcm_alloc','bcm_recon_notes','bcm_versions','bcm_version_lines','bcm_version_hist')) as tables;
   ```

   Expect **41**, **6** and **7**.

**What the update does:**
- **Seven new tables**, read under the same project rules as the rest of the module:
  - sheet roles, duplicate and backup candidates, split allocations, reconciliation explanations;
  - budget versions, their lines and their history.
- **Two new rights** (Settings → Roles and rights):
  - **bcm.budget**: prepare, import and submit budget versions. Costing engineers have it by default.
  - **bcm.budget.approve**: approve budget versions. It comes with the position **Head of Planning and Cost Control**; the super admin can give it to someone else.
- **The server works out the budget figures itself** (`bcm_totals`). It refuses a budget version from a batch that is not ready, whatever the browser sends:
  - every counting line classified (or split, with the split approved);
  - every duplicate or backup candidate decided, and every sheet role confirmed;
  - each control total matched within the tolerance, or the variance explained;
  - no line in another currency, no line on an element that is no longer approved.
- **Different people at each step.** Someone who prepared or submitted a version cannot review or approve it. A split is approved by someone other than the person who proposed it.
- **Nothing is deleted.** A decision only says which lines stop counting. The lines of a version cannot be changed once it leaves the draft; a correction is a new version.
- **Approved in ProTrackAI is not loaded in SAP.** The SAP loading workbook and its confirmation come in stage 4.
- **Running the update twice is safe.**

## Step 2: Try it on one tender (10 minutes)

1. **Duplicate & Backup Analysis**: choose the project and the tender batch, then press **Run the analysis**.
   - Check the **sheet roles**. Only an authoritative summary and a detailed cost breakdown count; a supporting backup, an alternative quotation, a previous revision and a reference sheet are kept but not added. A reviewer presses **Confirm the roles shown**.
   - Decide each **candidate**:
     - **Duplicate**: tick the line that counts.
     - **Supporting backup only**: the summary line counts. **Count the backup lines instead** does the reverse.
     - **Valid independent cost**, **Superseded revision** or **Excluded with justification**.
   - Every decision except a valid cost needs a reason. A decision can be reopened with a reason.
2. **Split a combined line** (supply and installation): open it in Classification Review, then **Propose a split**.
   - The allocations must add up to the line. Use the breakdown in the source file where there is one.
   - Someone else approves it.
3. **Reconciliation Centre**: the accepted total (each valid cost once), each file's control total against the lines counted, the amounts by WBS with their SAP WBS IDs, and the checks.
   - A variance is explained with a reason. It is never adjusted away.
4. **Budget Versions**:
   - **From a classified tender**: choose the batch and the kind (Tender estimate, Rev 0, Revised Rev 0, Approved revision), give the justification, then press **Prepare the draft version**.
   - **For an existing project**: press **Choose the budget workbook**. Use one row per SAP WBS element, with these columns: SAP WBS ID, WBS code (optional), Description, User field, Cost type (optional), and one column of amounts per budget (Tender, Rev 0, Revised Rev 0 …). Choose the amount column, check the rows, then press **Import as a draft version**. **Download the template** gives the layout.
   - Then: **Submit** (the preparer), **Take under review** (a reviewer), **Approve in ProTrackAI** (a budget approver). Each version shows its comparison with the previous approved version and exports to Excel.
5. **Approval History** lists every decision with who and when.

## If something goes wrong

| What you see | What to do |
|---|---|
| **Stage 3 needs the v41 database update** | Run Step 1 |
| **The batch is not ready for a budget version: …** | Do what the message lists, then look at the Reconciliation Centre |
| **You prepared or submitted this version, so someone else reviews it** | Another reviewer or approver does that step |
| **Line n: … is twice in the file** | Each SAP WBS ID (with its cost type) appears once in an import |
| **Line n: the user field … is not in the user field list** | Add it in Settings → Supplement lists, or correct the file |
| **The lines add up to …, not the total … stated in the file** | Check the file's total row, or clear the total box |
| **No header row naming the SAP WBS …** | The import needs a column named SAP WBS ID (or WBS element) and a Description or WBS code column |

## To undo

Run `supabase/schema-rollback-v41.sql`. This removes the stage 3 functions, so nothing more can be decided or approved. The tables and their records stay, so running v41 again brings everything back.
