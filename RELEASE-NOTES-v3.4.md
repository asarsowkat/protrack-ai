# ProTrackAI v3.4: the project document rack (October 2026)

Built from your specification of 13 October 2026 (sections 4 and 5), with your answers:
- files are stored in your Supabase project
- the costing engineer keeps Row 1
- the rack opens from Project overview → Documents

## What changed

### Three rows of box files for every project
- **Where to find it:** **Projects & Handover → Project document rack**, or **Project overview → Documents** (no longer marked Planned).
- **The rows:**

| Row | Kept by | Default box files |
|---|---|---|
| 1 Contract & Commercial | Costing engineer | 10: contract agreement, scope, tender and BOQ, deliverables, correspondence, claims and EOT, change orders, bonds and insurance, subcontracts, commercial records |
| 2 Planning & Scheduling | Planning engineer | 12: approved baseline, current P6 schedule, weekly and monthly reports, lookaheads, recovery, resources, delay and risk, progress measurement, milestones, engineering and procurement schedules, schedule reference |
| 3 Cost Control & Costing | Costing engineer | 14: tender estimate, Rev 0 budget, monthly budget, costing and rates, actual and commitments, EAC, cash flow, invoices, VO, change orders, earned value, management reports, POs and subcontracts, cost revisions |

- **Keepers:** the Head of Planning and Cost Control and super admins keep all three rows.
- **Who sees which row:**
  - Project managers, executives and other office roles see all three rows.
  - Site engineers and site managers see the Planning row only.
  - Foremen see none.
  - The server and the storage rules enforce this, not just the screen.

### How the boxes look
- **Colours by row:** navy and steel-blue for Contract, teal, blue and blue-grey for Planning, charcoal, deep blue and muted gold for Cost.
- **Every box also has** an icon, a big label (BASELINE, CURRENT P6, WEEKLY REPORTS, MONTHLY REPORTS, TENDER, REV 0, MONTHLY BUDGET, EAC, CASH FLOW, INVOICES, VO, CHANGE ORDERS …), its code, name and document count. Colour is never the only signal.
- **Badges on each box:** the latest reporting period ("Week 41", "Sep 2026"), the latest revision, "Rev 0 kept" or "Baseline kept", and the latest status.

### Inside a box
- **Expected contents:** the list from your specification, with a tick against what has been filed.
- **Documents:** title, contents, reference, revision, period, status and file, with filters and search.
- **Upload:** files up to 50 MB. Accepted types are PDF, Office files, P6 XER and XML, MPP, CSV, images, ZIP, TXT, MSG/EML and drawings.
- **Opening a document:** preview (PDF, images, text), download, upload a new revision, change the status, correct the details, and the full history.
- **Statuses:** Draft, Submitted, Issued, Approved, Certified, Rejected, Paid, Superseded, For information. Rejecting or marking superseded needs a comment.
- **Nothing is overwritten or deleted:**
  - A new revision is a new file, linked to the one it replaces.
  - The **approved baseline** box and the **Rev 0** box always list every revision.
  - A working schedule goes in Current P6, never into the baseline box.
- **Compare reporting periods** (weekly and monthly report boxes): pick two periods to see the released planned and actual progress, SPI, design, procurement and forecast finish side by side, with the documents filed for each.
- **Milestones box:** the milestone register with status.
- **Cost boxes:** tender, Rev 0, latest approved budget, actual, commitments, approved change orders, pending variations and EAC, each on its own line with its source (the released cost report or the change order log).
- **Missing data:** where ProTrackAI has no data, it says **"Data unavailable"**; no figure is invented.

### Live figures on each row
- **Planning:** planned and actual progress, SPI, forecast finish, next milestone, high warnings and the last released progress.
- **Cost:** the eight financial measures above.
- **Contract:** contract value, change orders and claims logged, and EOT status.

### Arranging the boxes
- **Who can:** the people who keep a row.
- **Arrange boxes:** move boxes left or right, and add a box file to their row.
- **Box settings:** rename or hide a box. Hidden boxes keep their documents; "Show hidden boxes" brings them back.
- **What stays the same:** a box always stays in its row and follows that row's rules, and every change is in the history.

### Records only
Box files are containers for source documents. Uploading a P6 file does not import it, uploading a costing file does not change a budget, and filing a VO does not approve anything. Those still go through their own screens, and the box says so with a link where it helps.

### Backups
The server backup now includes the boxes, documents and their history. The files themselves stay in Supabase Storage and are not in the backup file.

## Database: `schema-update-v13.sql`
- **New tables:** `doc_boxes`, `documents` (a file can never be changed or deleted, even from the database console) and `doc_audit` (append-only).
- **New functions:** `doc_act` (the only way to add documents and change boxes), `pt_doc_can` and `pt_doc_row` (who may read and keep each row).
- **Storage:** a private bucket `project-docs` with a 50 MB limit per file, and two access rules on it, one to read and one to add. There is no rule to change or delete a file.
- **Nothing existing changes.** Safe to run twice.
- **Rollback:** `schema-rollback-v13.sql` stops new uploads and keeps everything, still readable.

## Verified

| Suite | Checks | Result |
|---|---|---|
| Database: storage rules per row and role, file types, folders, registering, revisions, reads, status and details, files that cannot change, boxes, rollback (`test_v13.py`) | 75 | 75 pass |
| Earlier database suites (v4, v10, v11, v12) with the extended test stub | 125 / 51 / 46 / 44 | all pass |
| Server mode, end to end through the app (v13 applied mid-run; uploads and signed downloads through a Storage stand-in) | 174 | 174 pass |
| Document rack in demo mode (`docs_demo.py`), app and demo page | 44 + 44 | all pass |
| Cost / quantities / issues / released reporting, app and demo page | 28 / 28 / 60 / 53 each | all pass |
| RASA / Tender register / lifecycle / imports, app and demo page | 32 / 62 / 36 / 34 | all pass |
| Regression, demo date and live date (with your PE-329 XER) | 77 + 77 | all pass, 2 skipped each |
| Functional suites / formula reference / backup and restore | 59 / 23 / 10 | all pass |
| Demo page: regression and functional suites | 77 / 54 | one expected difference each, as before |

**No existing check had to change.**

**Not verified here:**
- Supabase itself, including Supabase Storage. A local stand-in imitates the two Storage tables the rules use. The first upload on live.html is the real test.
- Your live project.

**In the demo,** files are kept in your browser only, up to 10 MB each, and the sample documents are placeholders.

## Still open
- **Sections 1 to 3 of your specification** were not included. Send them if they change anything here.
- **Commercial role:** Row 1 is kept by the costing engineer, as you chose. A separate Contract & Commercial Engineer role can be added later.
