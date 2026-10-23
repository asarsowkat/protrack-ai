# ProTrackAI v3.38: Budget & Cost Management stage 4, reporting and SAP preparation (October 2026)

Built from your request to start stage 4 of Budget & Cost Management. With it every page of the module is open. Cost Summary and SAP Export & Import are no longer planned.

## What changed

### SAP reports (SAP Export & Import → SAP reports)
- **The monthly SAP ECC reports come in as Excel**, one per period (year and month) and kind:
  - **budget, actual and commitment by WBS element**, as S_ALR_87013558 gives;
  - **actual cost line items**, as CJI3 gives (posting date, document, value);
  - **open commitment line items**, as CJI5 gives.
- **How the file is read:**
  - The header is found below the title rows, by the column names SAP uses: Object or WBS Element, Budget, Actual, Commitment, Val.in Obj.Crcy, Posting Date, Purchasing Document …
  - The kind of report is recognised and can be changed.
  - "PE-555-04-001 Cables material" in one cell is split into the element and its description.
  - SAP dates (30.09.2026) and trailing minus signs (1,500.00-) are read.
- **Column templates:** choose the columns by hand when the names differ, and save them under a name. The next month, pick the template.
- **Every row is checked**, and each problem is listed with its row. Nothing is imported until the file is corrected. The checks:
  - an amount that is not a number;
  - another currency (ProTrack does not convert);
  - a row without a WBS element;
  - a WBS element repeated;
  - a posting outside the period;
  - a total row that does not match the rows.
- **Totals at each level are not counted twice.** A by-WBS report shows each level with the totals below it, so an element counts only what is not already in the elements below it.
- **Line items:**
  - Actual costs are by default the postings of the period.
  - Tick **to the end of the period** for a report that runs from the start of the project.
  - Commitments are what is open at the end of the period.
- **Frozen once imported:**
  - The rows never change. The server works out the figures by WBS element itself, and the original file is kept.
  - A new report for the same period and kind replaces the earlier one, which is kept as Superseded.
  - The same file is never taken twice.

### Cost Summary
- **The 24 columns, by SAP WBS element:**

  | Group | Columns |
  |---|---|
  | The element | SAP WBS ID, WBS code, description, level, user field |
  | Budgets in ProTrackAI | Tender estimate, Rev 0, approved revisions, current approved budget, pending budget changes |
  | SAP budget | SAP budget, ProTrack less SAP budget |
  | Costs | actual this period, actual to date, commitments, actual + commitments, remaining budget, % spent, % committed |
  | Forecast | estimate to complete, estimate at completion, variance at completion, VAC % |
  | Status | status |

- **Each heading shows its definition.** The Excel export has them on a Definitions sheet.
- **Where the figures come from:**
  - **Budgets:** the approved budget versions.
  - **Actual to date:** the latest by-WBS report up to the period, plus the actual line items of the months after it.
  - **Actual this period:** the line items of the period, or the difference between this month's and last month's by-WBS reports.
  - **Commitments:** the reports of the period; they are never carried over from an earlier month.
  - The page says which reports were used. A missing month is said, never filled in.
- **The estimate at completion** is the SAP forecast when the report has one. Otherwise it is budget-based: actual + commitments + what remains of the budget (never less than zero).
- **A level adds up its elements.** Its estimate at completion is the sum of its elements' estimates, so an overrun on one element is not hidden by an underrun on another.
- **The statuses:** Over budget, At risk (90% committed), SAP budget differs (the SAP budget is not the approved one), Not in the SAP report, Not in the approved budget (cost booked in SAP on an element with no budget).
- **Filters**, the levels above shown or hidden, and an Excel export with the 24 columns, the definitions and the sources.

### SAP loading workbook (SAP Export & Import → SAP loading)
- **Who:** only a **SAP authorized user** (the new right **bcm.sap**, given by the super admin) prepares the workbook of a version approved in ProTrackAI. A Tender estimate is not loaded.
- **The six sheets:**
  - **Header:** the project, the version, the total, the approvals and a content check. It also says that nothing was sent to SAP.
  - **WBS Elements:** each SAP WBS ID with its level, parent, description and user field, including the levels above.
  - **Original Budget:** used for the first loading of a project.
  - **Supplements & Returns:** used for later versions, against the version last loaded. It gives each change with its type.
  - **Control Totals:** by top-level element. It checks that previously loaded + supplements + returns = the new total.
  - **Approvals & Checks:** the history of the version and the checks.
- **What the server does:**
  - It makes the content and refuses an amount without a valid SAP WBS ID of the project (its PE number and the segments of each level).
  - It refuses a version that changes nothing.
  - It allows one waiting loading per project at a time.
- **After preparing:**
  - The version becomes **Ready for SAP Loading**.
  - Once the SAP team has loaded it, the SAP authorized user records **SAP Loading Confirmed** with the SAP reference and the date. Neither can be left empty, and the date cannot be in the future.
  - If SAP could not take it, **Return** it with the reason. The version goes back to Approved in ProTrackAI, and the workbook can be prepared again.
- **Every workbook is kept** with its status, the SAP reference, and who recorded it. It can be downloaded again.
- **Nothing is sent to SAP**, and no loading is simulated.

### Also
- **The overview** has a "Ready for SAP loading" tile instead of the planned one.
- **Approval History** lists the SAP loadings and returns.
- **A version's page** says whether it is ready for SAP loading or loaded, with its SAP reference.
- **A fix of v3.37:** the lines of a budget version are read only by people who see the project. Before this, someone with cost figures outside the project could read them.

## Setup
STAGE-36-SETUP.md:
1. Run `supabase/schema-update-v42.sql` and the check (expect 42, 7, 4).
2. Give **bcm.sap** to the person who loads budgets in SAP.
3. Import one month's SAP report, look at the Cost Summary, and prepare one loading workbook.

## Verified
| Check | Result |
|---|---|
| `supabase/tests/test_v42.py`, PostgreSQL 16 with every update v2 to v42. It covers: <ul><li>the rights and their defaults</li><li>templates (who, the WBS column, saved again by name)</li><li>imports refused, keeping nothing: a file not stored, a future period, an amount that is not a number, a repeated element, no WBS element, a total row that does not match, no amount column</li><li>the figures with totals at each level counted once</li><li>the same file refused; a report superseded and kept</li><li>rows that never change</li><li>line items: postings of the period, to the end of the period, commitments</li><li>read rules, including the v3.37 fix</li><li>the loading workbook refused for a Tender estimate, without bcm.sap, for a draft, for IDs of another project or with wrong digits, while another waits</li><li>the original budget; the confirmation (right, reference, dates)</li><li>supplements and returns against Rev 0</li><li>a return and a second workbook; an older version after a later one; a version changing nothing</li><li>the audit; rollback and again</li></ul> | 67 of 67 |
| `tests/bcm_demo4.py` (new), the demo page: <ul><li>the menu with every page open</li><li>Rev 0 of a PE-555 project imported and approved</li><li>the July and August by-WBS reports, the September CJI3 and CJI5 line items imported; the report with mistakes refused with each reason; the same file refused</li><li>a column template</li><li>a report opened</li><li>the Cost Summary: 24 columns, the project figures (8,380,000 budget, 4,968,500 actual, 2,470,000 commitments, EAC 8,793,500, VAC -413,500), the sources, the statuses, a filter, the Excel export, the actual of August from the difference of two reports</li><li>the loading workbook refused without bcm.sap; prepared (six sheets), confirmed with the SAP reference; the revision as supplements and returns, returned, prepared again and confirmed</li><li>the summary after the revision, Approval History, the overview, the audit</li></ul> | 35 of 35 |
| `tests/bcm_e2e.py`, the live app against the database v2 to v42. All the earlier checks, plus stage 4 on the server: <ul><li>four reports imported through the screen, the files in the bucket under sap/</li><li>the figures worked out by the server</li><li>a template</li><li>a report without its stored file, and a planner, refused</li><li>the Cost Summary from the server's records</li><li>the workbook refused without bcm.sap, made from the server's content with its check</li><li>the confirmation with the SAP reference</li><li>Approval History</li></ul> | 64 of 64 |
| `tests/bcm_demo.py` and `tests/bcm_demo3.py` (stages 1 to 3; the menu checks updated) | 67 of 67 and 50 of 50 |
| `supabase/tests/test_v41.py` | 77 of 77 |
| `tests/bcm_engine_test.cjs`, with 31 new checks of the stage 4 functions on the test reports `fixtures/bcm/20` to `24` | 130 of 130 |
| The 25 console acceptance scripts, on this version and on v3.37, with the real SheetJS | The same results as v3.37 for all 25 (for example, budget supplements 57 of 57) |

**Not verified:**
- **Your real SAP exports.** The import reads the usual S_ALR_87013558, CJI3 and CJI5 layouts. If yours differ, choose the columns once and save them as a template, or send one file and I will adapt it.
- **The specification's exact 24 columns and 6 sheets.** The original specification document was not available while building this release; the columns and sheets above follow its description. Send the specification again if any of them should change.
- **The loading workbook's layout for your SAP team.** Have them confirm it before the first real loading.
