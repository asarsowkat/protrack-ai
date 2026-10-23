# ProTrackAI v3.37: Budget & Cost Management stage 3, financial controls (October 2026)

Built from your request to establish stage 3 of Budget & Cost Management. It covers:
- counting each cost once;
- reconciling the tender files;
- splitting combined lines;
- approving budget versions;
- importing the budgets of existing projects with their actual SAP WBS IDs.

Budget Versions, Duplicate & Backup Analysis, Reconciliation Centre and Approval History are now open in the menu. Cost Summary and SAP Export & Import stay planned for stage 4.

## What changed

### Duplicate & Backup Analysis
- **Run the analysis** on a tender batch. ProTrack proposes two things.
- **The role of each sheet:**
  - authoritative summary or detailed cost breakdown (these count);
  - supporting backup, alternative quotation, previous revision or reference (kept and shown, never added).
  - The basis is given. For example: "Summary row 2 takes its amount from Salaries backup F5", a hidden calculation sheet, or the sheet of the file's control total.
- **The candidates:**
  - the same line twice;
  - the same quantity, rate and amount under another description;
  - similar lines with a different specification (630 against 300 mm2; shown for information only);
  - a summary line equal to another sheet's total or linked to it, with its backup lines;
  - totals repeated in several places.
  - Several signals are used together: the file fingerprint, sheet and section, description, quantity, unit, rate, amount, technical attributes and formula links between sheets.
- **A reviewer (bcm.review) decides each candidate:**
  - **Valid independent cost**;
  - **Duplicate** (tick the line that counts);
  - **Supporting backup only** (the summary line counts), or **Count the backup lines instead**;
  - **Superseded revision**;
  - **Excluded with justification**.
  - A reason is needed except for a valid cost. A decision can be reopened with a reason.
- **Nothing is deleted.** A decision only says which lines stop counting. Each line in a candidate shows whether it counts and why.

### Split allocations
- **A combined line** (supply and installation, material and labour) is split in its line view into WBS elements and cost types. Enter amounts or percentages; percentages become exact amounts, and the rounding goes to the last row.
- **The allocations must add up to the line.** The method is recorded: Source breakdown (prefilled from a breakdown in the file), Approved allocation rule, or Manual with its basis written down. No percentage is assumed.
- **Someone other than the proposer approves it.** The line then counts by its allocations. An approved split can be rejected with a reason.

### Reconciliation Centre
- **Accepted total:** each valid cost once.
- **Not counted:** backups, duplicates, other sheet roles and exclusions.
- **Unresolved:** counting lines not classified yet.
- **Ready for a budget version:** yes, or the list of what is left to do.
- **Each file:** its control total against the lines counted, the variance and the tolerance. The tolerance is set by currency and project type: the larger of an amount and a percentage, 1 and 0.01% by default.
- **A variance is explained with a reason.** It is never adjusted away.
- **Accepted amounts by WBS and cost type,** with the SAP WBS ID and user field. Splits count by their allocations.
- **The checks of the specification:**
  - source-to-detail differences;
  - missing descriptions, quantities, rates and amounts;
  - formula errors and missing formula results;
  - negative amounts;
  - quantity × rate differences;
  - repeated totals;
  - unclassified value and invalid WBS mappings;
  - other currencies and waiting splits;
  - materially different amounts for the same item across files.
- **Changes from the previous revision** of the same tender, item by item.
- **On the server:** the server's own figures and check are shown next to the browser's.

### Budget Versions
- **The kinds:** Tender estimate, Rev 0, Revised Rev 0 and Approved revision. Each is numbered within its kind.
- **From a classified tender:** choose the batch, the kind and the justification. On the server, the server works out the figures itself and refuses a batch that is not ready. It is ready when:
  - every counting line is resolved;
  - every candidate is decided and every role confirmed;
  - every splitting is approved;
  - every control total matches, or its variance is explained;
  - no line is in another currency, and none is on an element that is no longer approved.
  - The lines are one per WBS and cost type, with the SAP WBS ID of the project and the user field.
- **Imported for an existing project.** This is what you asked about: the projects already running with a budget in SAP.
  - The workbook has one row per SAP WBS element: SAP WBS ID, WBS code (optional), description, user field, cost type (optional), and one amount column per budget (Tender, Rev 0, Revised Rev 0 …). You choose which column the version takes.
  - The SAP WBS IDs are kept exactly as written. A row is linked to a master element where its WBS code or SAP WBS ID matches.
  - Refused, with the reason on each row: a repeated ID, an amount that is not a number, a user field outside the list, a row without an ID. The lines must also add up to the total row of the file.
  - **Download the template** gives the layout.
- **The approval steps:**
  - **Draft**: prepared by a costing engineer (bcm.budget).
  - **Submitted**.
  - **Under Review**: by a reviewer who did not prepare or submit it.
  - **Approved in ProTrackAI**: by a budget approver (bcm.budget.approve: the Head of Planning and Cost Control, or someone the super admin gives it to), never the preparer or submitter.
  - Reject or cancel with a reason.
  - The lines cannot change once the version leaves the draft; a correction is a new version.
- **Each version shows:**
  - its lines and history;
  - the comparison with the previous approved version (total, and lines added, removed or changed);
  - an Excel export.
- **The page shows** the current and the previous approved budget, the approved Tender estimate, and the versions waiting.
- **Approved in ProTrackAI is not loaded in SAP.** The SAP loading workbook and its confirmation with the SAP reference come with stage 4.

### Approval History, and the overview
- **Approval History** lists every approval and decision with who and when: master data, mappings, sheet roles, duplicates, splits, explanations and budget versions.
- **The overview** now counts duplicate candidates, reconciliation variances and pending budget approvals. The earlier caveat that a backup sheet and its summary line were both counted is replaced: the accepted total is in the Reconciliation Centre.

## Setup
STAGE-35-SETUP.md:
1. Run `supabase/schema-update-v41.sql` and the check (expect 41, 6, 7).
2. Try the analysis, a split, the reconciliation and a budget version on one tender; import one existing project's budget.

## Verified
| Check | Result |
|---|---|
| `supabase/tests/test_v41.py`, PostgreSQL 16 with every update v2 to v41. It covers: <ul><li>the roles proposed and confirmed (a confirmed role kept by a new analysis)</li><li>candidates saved, decided (reason needed; the lines that stop counting worked out by the server), reopened, made obsolete</li><li>a backup counted in detail</li><li>splits that must add up, approved by someone else, rejected</li><li>explanations</li><li>`bcm_totals` before and after (2,501,000 counted, by WBS and cost type)</li><li>a version from a batch refused while not ready, then made with SAP WBS IDs</li><li>imports: repeated IDs, amounts, user fields, unapproved elements, the file total</li><li>each step by a different person, reject and cancel with a reason, the previous approved version</li><li>frozen lines</li><li>rollback and again</li></ul> | 77 of 77 |
| `tests/bcm_demo3.py` (new), the demo page through the screens: <ul><li>the menu</li><li>the analysis on three test workbooks (a summary with its backup sheet, the same cable written twice, a combined line with its breakdown sheet)</li><li>the roles and five candidates, each decision and a reopening</li><li>backup lines counted instead</li><li>two splits (amounts, and percentages to exact amounts), refused when they do not add up or approved by the proposer</li><li>the Reconciliation Centre (3,113,000 counted, the control total within tolerance, by WBS)</li><li>a Tender estimate prepared, submitted, reviewed and approved by three people</li><li>the import of an existing project's budget (rows refused with reasons; Rev 0 and Revised Rev 0 with their SAP WBS IDs and the decimal kept)</li><li>the comparison, the export, reject and cancel</li><li>Approval History and the overview</li></ul> | 50 of 50 |
| `tests/bcm_e2e.py`, the live app against the database v2 to v41. All the earlier checks, plus stage 3 on the server: <ul><li>analysis stored</li><li>decisions and their reasons</li><li>a split refused for its proposer and approved by someone else</li><li>the server's totals</li><li>a version through its four steps, each refused for the wrong person</li><li>the lines unchangeable</li><li>an import with the SAP WBS IDs as written</li><li>Approval History</li></ul> | 53 of 53 |
| `tests/bcm_demo.py` (stages 1 and 2, the menu check updated) | 67 of 67 |
| `tests/bcm_engine_test.cjs`, with 25 new checks of the stage 3 functions | 99 of 99 |
| The 25 console acceptance scripts, on this version and on v3.36, with the real SheetJS | The same results as v3.36 for all 25 (for example, budget supplements 57 of 57 and Cashflow Dashboard 28 of 28) |

**Not verified:** your real budget workbooks. The import reads the layout above. If your SAP budget file is laid out differently (for example several sheets, or one column per cost element), send one and the import will be adapted to it.
