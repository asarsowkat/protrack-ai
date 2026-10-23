# v3.38 setup: Budget & Cost Management stage 4 (reporting and SAP preparation)

This takes about 15 minutes. **Do not** upload a new `config.js`. It needs v41 (STAGE-35-SETUP).

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `supabase/schema-update-v42.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select bcm_features() ->> 'version' as version, (select count(*) from pg_proc where proname in ('bcm_sap_tpl','bcm_sap_import','bcm_sap_export','pt_bcm_sap_bad','pt_bcm_sap_content','pt_bcm_reads_ver','pt_bcm_reads_sr')) as functions, (select count(*) from information_schema.tables where table_schema = 'public' and table_name in ('bcm_sap_tpls','bcm_sap_reports','bcm_sap_lines','bcm_sap_exports')) as tables;
   ```

   Expect **42**, **7** and **4**.

**What the update does:**
- **Four new tables**, read under the same project rules as the rest of the module:
  - the monthly SAP reports and their rows, frozen when imported;
  - the column templates of the reports;
  - the SAP loading workbooks and their confirmations.
- **Two new rights** (Settings → Roles and rights):
  - **bcm.sap.import**: import the monthly SAP reports and keep their column templates. Costing engineers have it by default.
  - **bcm.sap**: the **SAP authorized user**. This person prepares the SAP loading workbook of an approved budget version, and records **SAP Loading Confirmed** with the SAP reference. **Nobody has it by default: the super admin gives it** to the person who loads budgets in SAP.
- **The server checks every report row** (numbers, dates within the period, repeated WBS elements, the total row) and works out the figures by WBS element itself.
- **The server makes the content of the loading workbook.** It refuses a version that is not approved, a Tender estimate, or an amount without a valid SAP WBS ID of the project. It also refuses while another version of the project waits for its confirmation.
- **A fix of v3.37:** the lines of a budget version are now read only by people who see the project. Before this, someone with cost figures outside the project could read them.
- **Nothing is sent to SAP**, and no loading is simulated.
- **Running the update twice is safe.**

## Step 2: Give the SAP right (1 minute)

Settings → Roles and rights: give **bcm.sap** to the person who loads budgets in SAP (or keep it with the super admin).

## Step 3: Try it on one project (10 minutes)

1. **SAP Export & Import → SAP reports (import)**:
   - Choose the **period** (year and month).
   - Choose the Excel file exported from SAP:
     - by WBS element, as **S_ALR_87013558** gives (Object or WBS element, Budget, Actual, Commitment);
     - actual cost line items, as **CJI3** gives (WBS element, posting date, value);
     - open commitment line items, as **CJI5** gives.
   - Check the kind of report, the columns and the totals. If your columns have other names, choose them under **Columns** and press **Save these columns as a template**; the next month, pick the template.
   - Every problem is listed with its row. Correct the file before importing.
   - Press **Import and freeze**. A new report for the same month and kind replaces the earlier one, which is kept as Superseded.
2. **Cost Summary**: choose the period. It shows the 24 columns by SAP WBS element, with the levels above. Filter by status (Over budget, At risk, SAP budget differs …), then export to Excel. Hover a column heading for its definition.
3. **SAP Export & Import → SAP loading (export)**, as the SAP authorized user:
   - **Prepare the SAP loading workbook** of an approved Rev 0 (or revision). The workbook downloads with six sheets: Header, WBS Elements, Original Budget, Supplements & Returns, Control Totals, Approvals & Checks. The version becomes **Ready for SAP Loading**.
   - Give it to the SAP team. Once they have loaded it, enter the **SAP reference** and the date, then press **Record SAP Loading Confirmed**.
   - If they could not load it, press **Return** with the reason. The version goes back to Approved in ProTrackAI.
   - The next revision goes as **Supplements & Returns** against the version last loaded.

## If something goes wrong

| What you see | What to do |
|---|---|
| **Stage 4 needs the v42 database update** | Run Step 1 |
| **No header row naming the WBS element and an amount column …** | The sheet needs a WBS element (or Object) column and Budget, Actual, Commitment or Value. Choose the columns by hand under **Columns** |
| **Row n: posted on …, after (or before) the period** | Choose the right period, or tick **Postings to the end of the period** for a report that runs from the start of the project |
| **This file is already imported** | The same file is never taken twice |
| **Only a SAP authorized user (bcm.sap) …** | Step 2 |
| **Not every amount has a valid SAP WBS ID of the project: …** | Correct the SAP WBS segments in WBS Mapping Master, or the IDs in the imported budget, and make a new version |
| **… is waiting for its SAP loading confirmation** | Confirm or return that version first |

## To undo

Run `supabase/schema-rollback-v42.sql`. This removes the stage 4 functions, so nothing more can be imported, prepared or confirmed. The reports, workbooks, confirmations and stored files stay, so running v42 again brings everything back. The v3.37 read fix stays.
