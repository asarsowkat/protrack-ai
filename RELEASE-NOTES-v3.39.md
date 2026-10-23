# ProTrackAI v3.39: budget supplement and change request forms, approved through Approval Hub (October 2026)

Built from your request:
- all budget changes are recorded as budget supplements;
- the Budget Supplement / Returns Request and the Change Request are started in ProTrack and approved through Approval Hub;
- every approved WF goes into the budget supplement log by itself;
- the version (month) can be set by hand to the previous or the current month.

It follows the format you sent: the BRF sheet (AP/Planning-BRF, Rev. OCT.25), the Supplement Log, the Category sheet, the approval box and the Change Request Log.

## What changed

### Cost Control → Budget & change requests (new page)
- **The list** shows the forms of the projects in your scope, filtered by project, form and status, with counts of drafts, forms in Approval Hub, approved and rejected.
- **Starting a form:** planning and costing engineers (right **wf.initiate**) start a **Budget Supplement / Returns Request** (BR-01, BR-02 … per project) or a **Change Request** (CR-01 …).

### The Budget Supplement / Returns Request, in your layout
- **01. General Information:**
  - the budget revision reference (PE-262 | BR-07), the date and the overall WF (Supplement, Savings, or both);
  - the project name and number, client, region, contract number and contract start, prefilled from the project master.
- **02. Brief Description:**
  - one line per item: short description, category, user field, WBS (SAP WBS ID), supplement or saving, linked VO or claim, remarks;
  - the total value.
  - The lists are those of Settings → Supplement lists, so a line is valid for the log before it is submitted.
- **03. Budget Summary by user field.** The columns are as in your sheet:
  - **A** Tender, **B** Rev-0, **C** current budget, **D** actual cost, **E** commitment;
  - **F** balance (C − D − E), **G** ETC, **H** revised estimate (D + E + G);
  - **I** this request (C − H), the previous request, **J** cumulative approved (A − C), and the % variance from tender.

  It is prefilled from ProTrack:
  - Tender and Rev-0 from the approved budget versions;
  - the current budget as Rev-0 plus the budget supplement log;
  - actual and commitment from the latest SAP report;
  - the previous request from the last approved BRF.

  Any figure can be typed over.
- **04. Impact on Project Margin and Milestones:**
  - original and revised contract value; tender, Rev 0, current budget, this request and revised estimate, each with its gross profit %;
  - TCC, EOT approved before and in this request, revised completion and forecast finish;
  - progress and POC, including the POC after this WF.
- **05. Category wise Details:** previous, current and cumulative by unified category.
- **06. Approvals:** the chain of your approval box.
  - Always: Project Manager, Costing Manager, Portfolio Manager, Planning Manager, Regional Manager.
  - The **Vice President** is added when a line uses contingency.
  - The **Executive Vice President** is added when a line uses the management reserve.
- **Download the form (Excel)** gives the request in your layout, with the category details on a second sheet.

### The Change Request
- **The fields of your Change Request Log:**
  - CRF # (PE-262/ CR-01), submission date, detailed description, client reference;
  - price submitted, approved by the client and considered internally;
  - cost Rev 00 and current budget;
  - status of client approval, remarks.
- **The same checks as the change order log** (for example, a client approved price needs the client approval).

### Approval Hub
- **Submit to Approval Hub** puts the form in a queue. Its lines can no longer be changed.
- **The connection.** Approval Hub, or a small connector from IT:
  - takes each submission;
  - reports the WF number, each step, and the final decision (approved, rejected, or returned for correction).

  It uses a secret token the super admin makes on the **Approval Hub** tab. The token is shown once and can be renewed or switched off.
- **The specification for IT** is in **APPROVAL-HUB-INTEGRATION.md**.
- **Until the link is connected,** the **costing coordinator** (right **wf.record**) records the hub's decision on the form: WF number, date, approver, comment. The form says it was recorded by hand, and by whom.
- **A returned form** goes back to its preparer with the reason. Corrected and resubmitted, it keeps its WF number.
- **Every step is kept** in the form's history: prepared, submitted, received, decided, posted and version moved, each with who and when.

### Posted to the logs automatically
- **An approved Budget Supplement / Returns Request** is posted at once to the project's **budget supplement log**:
  - one row per line (BR-07/1, BR-07/2 …) with its user field, category, WBS, amount and the WF number;
  - the WF date is the approval date;
  - the version is the month of the approval, unless a month was asked on the form.
- **Moving the version:** the costing engineer or coordinator can move it to the **month before the approval** or any month up to the **current month**, with a reason. All the rows of the request move together, and the log's history says it.
- **Posted rows are protected.** Rows posted from a WF keep their amounts: on the log screen only their version and remarks change, and they cannot be removed there. A change is a new request.
- **An approved Change Request** is posted to the **change order and claim log** as a VO, with its prices, cost, client status and WF. If the log already has that reference, it gets the WF number and date.

### SAP reports: CN41
- **The SAP report import also reads CN41** (structure overview), the layout of the "PE-xxx-CN-41" sheet in your file: ID, Budget, Act.costs and Tot.cst.cm. The currency columns beside them are left out, and its levels are counted once.

## Setup
STAGE-37-SETUP.md:
1. Run `supabase/schema-update-v43.sql` and the check (expect 43, 8, 4).
2. Try one request and record its decision by hand.
3. Later, connect Approval Hub with the IT team (APPROVAL-HUB-INTEGRATION.md).

## Verified
| Check | Result |
|---|---|
| `supabase/tests/test_v43.py`, PostgreSQL 16 with every update v2 to v43. It covers: <ul><li>the rights and the coordinator's position</li><li>forms refused for a foreman and a project manager; numbering; a reference used twice</li><li>submission refused without lines, with a user field outside the list, with a zero amount</li><li>the chain with VP and EVP; the queue and its payload; no change after submission</li><li>the token: made by the super admin only, kept as a hash, a wrong token refused, switched off</li><li>Approval Hub played with the anon role: taking a submission once, the WF number and step, the approval</li><li>posting: three rows with the WF number, version and date; the log started by the WF; the budget change of the cost report</li><li>posted rows not removed, their amount not changed, their remarks changed</li><li>the version: who, the reason, the limits (month before the approval, this month), all rows moved, the log history</li><li>the link kept on a new log</li><li>decisions by hand: who, the WF number, dates, the version asked, returned and resubmitted with its WF, rejected, cancelled</li><li>change requests: the client price rule, added to the change order log, or its WF written on an existing row</li><li>read rules; the history never changed</li><li>rollback and again</li></ul> | 75 of 75 |
| `tests/wf_demo.py` (new), the demo page: <ul><li>the menu</li><li>a BRF in the company layout, sections 01 to 06, from the project master</li><li>three lines signed as in the log; the VP for contingency</li><li>the summary by user field (current, this request, revised estimate) and the category details</li><li>the Excel form</li><li>a line without description refused; submission; the planner cannot record</li><li>the coordinator's decision by hand (WF number needed), posted with the version</li><li>the rows protected on the log screen; the version moved with its reason</li><li>the EVP for the management reserve; a return with its reason and the resubmission with the same WF</li><li>a change request: the client price rule, approved into the change order log</li><li>the list, the Approval Hub tab, rights</li></ul> | 31 of 31 |
| `tests/wf_e2e.py` (new), the live app against the database v2 to v43: <ul><li>a BRF prepared and submitted on the server (queue, VP), no change after submission</li><li>the token made on the screen and shown once; Approval Hub (anon role) taking it, reporting the WF number, approving</li><li>the rows in the log at once and on the log screen</li><li>the version moved on the server; a posted row not removed</li><li>the link switched off; a change request recorded by hand into the change order log; refused for someone without wf.record</li><li>a project manager reads but does not start; a foreman sees nothing</li></ul> | 20 of 20 |
| `tests/bcm_engine_test.cjs`, with the SAP CN41 layout | 132 of 132 |
| `tests/bcm_demo.py`, `bcm_demo3.py`, `bcm_demo4.py`, `bcm_e2e.py`, `supabase/tests/test_v42.py` (Budget & Cost Management) | 67, 50, 35, 64 and 67, all passed |
| The 25 console acceptance scripts, on this version and on v3.38, with the real SheetJS | The same results as v3.38 for all 25 (for example, budget supplements 57 of 57) |

**Not verified:**
- **Approval Hub itself.** Its interface is not known yet; the link is built to be called by the hub or by IT's connector. Send its API documentation if it should be the other way round (ProTrack calling the hub).
- **Your Change Request form.** The Change Request uses the columns of your Change Request Log. If the Approval Hub CRF form has other fields, send it.
