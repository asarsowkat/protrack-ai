# ProTrackAI v3.35: Budget & Cost Management, Automatic WBS Classification (stages 1 and 2) (October 2026)

Built from your development prompt for the Automatic WBS Classification Engine. This release delivers **stage 1 (foundation)** and **stage 2 (classification)** of its implementation order. Stages 3 and 4 are listed at the end, as planned, not built.

## Where it is
A new menu, **Budget & Cost Management**, right after Cost Control. Cost Control is unchanged.

| Page | In this release |
|---|---|
| Budget Overview | **Yes** |
| Tender File Intake | **Yes** |
| Automatic WBS Classification | **Yes** |
| Classification Review | **Yes** |
| WBS Mapping Master | **Yes** |
| Mapping Learning History | **Yes** |
| Audit Log | **Yes** |
| Duplicate & Backup Analysis, Reconciliation Centre, Budget Versions | Planned: stage 3 (shown as planned in the menu) |
| Cost Summary, SAP Export & Import, Approval History | Planned: stage 4 |

## What it does

### Tender File Intake
- **One batch per tender submission.** It records the project, tender reference, revision, reporting currency and project type.
- **Several workbooks at once**, as .xlsx, .xls or .xlsm, up to 25 MB each. Macros are never run: an .xlsm is read as data.
- **Each file is checked before anything is stored:**
  - Its extension, and whether its content really is an Excel workbook.
  - Its size, and whether it is password-protected or damaged.
  - A file that fails is refused with the reason.
- **Fingerprinted (SHA-256) and stored unchanged** in a private bucket. The same file is never taken twice in a project.
- **Read sheet by sheet**, hidden sheets included:
  - The header row is found by its words (Item, Description, Scope, Particulars, Qty, UOM, Rate, Unit Price, Amount, Total, Extended Price, Currency and others), not assumed in row 1.
  - Two-row headers under a merged heading are understood.
  - Section headings, subtotals (including SUM formulas) and grand totals are recognised.
  - Material and labour amount columns are kept as a breakdown.
  - An amount linked to another sheet says which sheet and cell.
  - Each file's control total is taken from a summary sheet's grand total, or the only grand total. If there are several, a person chooses.
- **Every non-empty row is kept** with its sheet, row, cell references, original texts and values, and formula. It also records whether the amount came from a formula, and any problem:
  - formula result missing;
  - formula error;
  - missing amount or a text where a number belongs;
  - negative amount;
  - quantity × rate differing from the amount;
  - hidden row.
- **Stored lines never change.** Reading a file again (for example after a column mapping) is a new run beside the old one.
- **A processing log** for each file and sheet. Other file actions:
  - **Map columns**, for a sheet whose header was not found, from a preview of the stored file.
  - **Read again**.
  - **Verify reading**: the stored file is read again and compared with what was stored.
  - **View lines**.

### Normalization
- Case, punctuation, abbreviations (S&I, xfmr, swgr, T&C and more), units (cu.m → m³, Nos → No.), currencies (SR, US$, €) and spelling variants are normalized. An administrator can add to the lists.
- The original description is kept.
- Technical attributes (kV, mm², cores, MVA, diameter, grade, XLPE) are read. "630 sq.mm XLPE cable 132kV" and "XLPE cable 630mm2 132kV" read the same; a 13.8 kV cable is never treated as the same item.

### Classification, in four layers
1. **Approved mappings**: exact on the normalized description, an alias or the item code. A project mapping comes first, then a project-type mapping, then a global one. 100%.
2. **Approved rules**:
   - What a rule matches: phrases in the description and its section headings, units and project type.
   - 38 starting rules cover the specification's examples. For instance, "Supply of rebar" → Civil Works → Rebar with cost type Material; "Rebar fixing crew" → Civil manpower with cost type Manpower.
3. **Similarity** to the approved master and the approved mappings. It is a word match computed in ProTrack, not an AI, and it only ever proposes.
4. **Exceptions:**
   - Conflicting mappings or rules go to review; ProTrack never picks one.
   - Combined supply-and-install lines go to **Split Required**; no split is invented.
   - Lines go to review when they are at or above the value limit for their currency, when the element always needs review (Financing, Contingency, Management Reserve), when they have a data problem, or when the cost type is not set.
   - Lines below 80% are **Unclassified**.

**Automatic classification** happens only from an approved mapping or rule, at or above 95%, below the value limit, with a cost type, for an element that does not need review and a line with no data problem. **The server checks every one of these again** and refuses an automatic classification that does not meet them.

The WBS destination is kept apart from the cost type. Only approved, active, postable elements in force are destinations; nobody, and no engine, creates a code. A person's decision is never overwritten by a new run.

**No outside AI is called.** ProTrack does not send company data to an outside service, as you set. If an AI provider is ever approved, it can be added only as a server function, and its output is checked against the approved master the same way. The tests show that invalid, invented, failed or amount-giving outputs are refused and the line stays for a person.

### Classification Review and the workspace
- **Progress:**
  - total source lines and extracted cost lines;
  - automatic, awaiting review, confirmed and unclassified lines;
  - total, accepted and unresolved amounts, by currency and exact.
- **High-value and mandatory lines** waiting are shown on top.
- **The table:**
  - filters by status, WBS, confidence band, source file, amount range and text;
  - sorting, 50 lines a page, and selecting lines.
- **Bulk confirmation** takes only clean proposals. High-value, mandatory, conflicting, combined and flagged lines are confirmed one by one; the toast says how many were left and why. A **bulk reassignment** (WBS, cost type, reason) of such a line only proposes the new WBS.
- **Each line** opens with:
  - its source (file, sheet, row, cells, formula, breakdown, section headings, data flags);
  - the rows around it in the sheet;
  - the normalized text and attributes;
  - the proposal with its reason and evidence;
  - the candidate destinations compared;
  - its history.
- **Decisions:**
  - confirm;
  - confirm with another WBS and cost type (an override, which needs a reason);
  - reject;
  - exclude with a reason;
  - correct the description or the row kind (the source stays as read);
  - undo, which is a new recorded action.
- **Export** of the exception list or of all lines to Excel, with the source references and reasons. Each export has an About sheet saying it is not an approved budget and nothing went to SAP.

### Learning from approved decisions
- A reviewer can choose to remember a decision as a mapping for **this project**, **this project type** or **all projects**. The default is a one-time correction.
- The mapping waits in **Mapping Learning History** until **someone else** with `bcm.approve` approves it. Conflicts with approved mappings are shown before approval. A mapping can be expired.
- Every version of every mapping, rule and WBS element is kept, so a past classification can be reproduced. Each classification records the mapping or rule and its version, and the engine version.
- **A performance report:**
  - automatic rate, proposals accepted as proposed, and override rate;
  - the most frequent unresolved descriptions and the most frequent corrections;
  - the same by project type.
  - It is measured on reviewed lines only, and labelled as not a model accuracy.

### WBS Mapping Master
- **A searchable, expandable tree.** Each element has its code, parent and description, plus:
  - aliases, keywords and cost category;
  - project types, optional SAP WBS and effective dates;
  - active, postable and always-reviewed flags;
  - its version.
- **Every change is a proposal** (`bcm.master`). The version in force stays until someone else approves the change (`bcm.approve`). Approve all waiting approves parents first.
- **Rules** have their phrases (all, any, none), priority and strength.
- **Thresholds and value limits** by currency and project type, and **word lists**. Changes are proposals.
- **Excel export, and import of a WBS master workbook.** Rows with a blank or repeated code, an unknown parent or a wrong date are refused with the reason; valid rows become proposals.
- **The starting master** (the specification's working definitions) arrives on the server as proposals of "System seed". Your company checks and approves it before anything is classified (STAGE-33-SETUP, step 3).

### Rights and security
- Four new rights: `bcm.upload` and `bcm.review` (costing engineers by default), `bcm.master` and `bcm.approve`. The Head of Planning and Cost Control holds review, master and approve by position.
- The module needs the cost-figures right, so foremen never see it.
- **On the server:**
  - Every action is checked by the database, by project access and right.
  - Nobody writes a table directly.
  - Source lines, histories and the audit log cannot be changed or deleted, even by the database owner.
  - The original files are in a private bucket.
  - Company costing data is not kept in the browser on the live site: it is read from the server and held in memory.

## Setup
STAGE-33-SETUP.md:
1. Run `supabase/schema-update-v39.sql` and the check (expect 39, 6, 88).
2. Give `bcm.master` and `bcm.approve` to two different people.
3. Check, correct and approve the starting WBS master and rules.
4. Upload a first tender.

## Verified
| Check | Result |
|---|---|
| `supabase/tests/test_v39.py`, PostgreSQL 16 with schema and every update v2 to v39. It covers: <ul><li>rights and project access</li><li>master data proposed and approved by different people, versioned and validated</li><li>the starting master waiting</li><li>batches and storage rules</li><li>the same file refused</li><li>lines frozen even for the owner</li><li>runs</li><li>every server check of an automatic classification</li><li>people's decisions kept</li><li>bulk confirmation and reassignment</li><li>undo, corrections, mappings proposed by reviewers</li><li>read access by project and cost right</li><li>withdrawal</li><li>rollback and again</li></ul> | 105 of 105 |
| `tests/bcm_engine_test.cjs`, the engine taken from live.html, run in Node 22 with the real SheetJS 0.18.5 on the test workbooks of `tests/fixtures/bcm` (made by `make_fixtures.py`, all test data, covering the 15 cases of the specification). It covers: <ul><li>exact money</li><li>file checks</li><li>.xls and .xlsm</li><li>headers found anywhere, two-row headers, hidden sheets, merged headings</li><li>formula subtotals and control totals</li><li>backup links and breakdowns</li><li>negatives, currencies, missing formula results</li><li>header mapping</li><li>fingerprint</li><li>normalization and attributes</li><li>the specification's classification examples</li><li>value limits, combined costs, mandatory review</li><li>only approved, active, postable, in-force elements</li><li>mapping scope, precedence, conflicts, expiry, aliases</li><li>rule conflicts and thresholds</li><li>similarity never automatic</li><li>five kinds of failed or invalid AI output</li></ul> | 74 of 74 |
| `tests/bcm_demo.py`, the demo page in Chromium. It covers: <ul><li>the menu (Cost Control unchanged)</li><li>eleven workbooks uploaded at once</li><li>refusals with reasons, the same file refused</li><li>stored originals</li><li>the classification results</li><li>column mapping and a second run</li><li>verify reading</li><li>the review progress</li><li>the line view</li><li>individual and bulk confirmation</li><li>an override with a reason and a project mapping proposed by a costing engineer, approved by the super admin, then used automatically for Rev 1</li><li>exclude, undo, corrected description</li><li>the exception export</li><li>a WBS change approved by someone else, its history</li><li>WBS import with invalid codes</li><li>thresholds</li><li>a foreman without the module</li><li>Cost Control, earned value, the costing sheet, logs, BOQ Engine and releases still opening</li><li>the audit log</li></ul> | 55 of 55 |
| `tests/bcm_e2e.py`, the live app against the database v2 to v39, through the stand-in Supabase with its storage. It covers: <ul><li>nothing classified before approval (and the reason)</li><li>the file stored in the private bucket and its rows exact on the server</li><li>the approver approving the starting master and rules</li><li>the classification on the server</li><li>the server refusing an automatic high-value line</li><li>bulk confirmation, override and mapping proposal on the server</li><li>approval by someone else and its use for Rev 1</li><li>the same file refused by the server</li><li>verify reading from storage</li><li>a planner and a foreman refused</li></ul> | 27 of 27 |
| The 25 console acceptance scripts in `tests/*.js`, on this version and on main, run with the real SheetJS | **The same results as main for all 25.** For example: budget supplements 57 of 57, invoices and cash inflow 28 of 28, Cashflow Dashboard 28 of 28, cash-out on P6 and the cost report 24 of 24, contract value 25 of 25. The remaining failures need libraries that cannot be loaded here (PowerPoint, PDF, PDF reading) and fail on main too |
| `tests/mail_e2e.py` (v3.34 emails, server mode), as a regression | 27 of 27 |

**Not verified:**
- The update on Supabase itself (only on PostgreSQL 16 with a stand-in for Supabase).
- Your company's real tender files. The test workbooks are made to cover the specification's cases; real files will show layouts the header detection does not know yet, which is what Map columns is for.
- Classification quality on your tenders. The thresholds are the specification's starting values; calibrate them on reviewed historical tenders.

## Limitations
- **Where the reading happens.** The file is read in the browser of the person who uploads it, with the same SheetJS the app already uses. The server stores the original and checks the lines and every classification rule, but does not read the file itself. **Verify reading** lets anyone read the stored file again and compare.
- **A formula without a stored result is not recalculated.** It is flagged, and its amount stays missing.
- **Mapping performance needs reviewed lines.** It is measured only where people have reviewed lines; no model accuracy is claimed.
- **Large tenders.** A 5,000-line workbook is read in about 1.5 seconds and classified in about 3.5 seconds (measured with the same engine in Node on this test machine). On the demo page the browser's own storage holds only a few thousand lines in all; the live site keeps them on the server.

## Planned: stage 3, financial controls
- **Duplicate & Backup Analysis:**
  - exact and similar duplicates, and the same item in several places;
  - backup sheets already counted in a summary;
  - repeated totals and revisions;
  - relationships between files (summary, breakdown, backup, alternative quotation, previous revision, reference only), confirmed by a person.
  - Until then, the totals count a backup sheet's lines and the summary line they support both; the overview says so.
- **Reconciliation Centre:** source, classification and allocation variances, with configurable tolerances by currency and project.
- **Split allocations** of combined lines, against documented breakdowns, approved, and reconciling to the line.
- **Budget versions** (Tender, Rev 0, Revised Rev 0, approved revisions), immutable, with segregated approvals.

## Planned: stage 4, reporting and SAP preparation
- The WBS cost summary, with the 24 columns and the definitions of the specification.
- Monthly SAP ECC report import, with its own templates, validation and frozen snapshots.
- The SAP-ready loading workbook (6 sheets), with configurable templates to be confirmed by the SAP team.
- SAP loading confirmation, recorded only by an authorized user with the SAP reference.

No SAP connection exists or is simulated. Direct S/4HANA integration waits for go-live and authorization.
