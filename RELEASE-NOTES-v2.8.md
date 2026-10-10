# ProTrackAI v2.8: Tender register, PE numbers, and stages 1 to 5 aligned to your process (October 2026)

Built from your process description and your answers of 10 October 2026:

- **Who records:** the costing coordinator records stages 1 to 4 for now. Tender may record them later through an interface with their new application.
- **Who approves:** you, as Head of Planning and Cost Control, approve stages 1 to 5.
- **PE numbers:** ProTrackAI proposes each PE number, and a super admin can change it. Duplicates are refused. A cancelled project's number can go to another L1 project.

## What changed

### Tender register (Projects & Handover)

This menu item was marked Planned; it is now live. The register has one row per project, showing:
- the PE number and the TE number
- client, location and region
- expected value
- status (Pre-award, Active, Cancelled and so on) and current lifecycle stage

Below the table is the **PE number history**, which cannot be edited or deleted.

**Registering an L1 project** (costing coordinator, Head of Planning and Cost Control, or super admin):
1. Enter the TE number, project name, region, client, location, expected value and the date Tender notified you.
2. ProTrackAI fills in the PE number:
   - a number released by a cancelled project comes first, oldest release first
   - otherwise, the next number after the highest PE number ever used
3. Only a super admin can type a different number. Anyone else always gets the number ProTrackAI works out at the moment of saving. If someone took the proposed number a second earlier, the message says so.
4. The project starts as **Pre-award**:
   - The costing coordinator who registered it owns stages 1 to 4.
   - Heads and coordinators are given access to it.
   - Recording the **award date** makes it **Active**.
   - Recording the **contract signing date** makes stage 4 due 7 days later. If someone sets stage 4's due date by hand, that date is kept.

**PE number rules, enforced on the server:**
- A TE number is registered once. TE2231 and te2231 count as the same.
- PE-5, PE-05 and PE-005 count as the same number.
- No two live projects can hold the same PE number. A database index refuses a duplicate even from the database console or a hand-made project in Settings.
- **Cancel** (Head or super admin, reason required):
  - The project becomes Cancelled and read-only, including its stages. Nothing is deleted.
  - Its PE number is released.
  - The next project that receives that number gets a separate record (for example `PE-001-R2`) and is shown as PE-001. The history shows both TE numbers against PE-001.
- **Reinstate** (super admin, reason required): the project returns to its earlier status. If its number has gone to another project since, you must give it a new one.
- **Change PE number** (super admin, reason required): the old number is released.
- Browsers cannot write TE numbers, PE numbers or cancellations to the database directly, even a super admin's. Only the register can.

### Designations

In **Settings → Users and access**, a super admin can tick two designations on a person. A designation sits on top of the person's role; it does not replace it.

| Designation | Can do |
|---|---|
| Costing coordinator | Registers L1 projects and keeps their Tender details; owns stages 1 to 4 of the projects they register |
| Head of Planning and Cost Control | Approves, returns and marks not applicable stages 1 to 5; assigns their owners; cancels projects |

### Stages 1 to 5 follow your process

| # | Stage | Required items |
|---|---|---|
| 1 | Tender L1 notification | TE number, name, region, client, location; expected value |
| 2 | PE number allocation | PE number allocated against the TE number (optional: Tender informed) |
| 3 | Award, finance WBS and SAP activation | Notice of award; higher-level WBS in SAP; finance WBS sent to Tender for the advance bank guarantee charges; SAP team activated only that WBS; contract signed |
| 4 | Kick-off and handover to Planning | Kick-off held by Tender; tender documents handed over; costing file with detailed breakup handed over (optional: minutes). Due 7 days after contract signing |
| 5 | Costing review, finance pack and SAP upload | Site management, installation, mechanical and civil breakups checked; project brief; cash flow; brief, cash flow and signed contract sent to Finance/Treasury; costing uploaded to SAP with the standard template (optional: missing items received from Tender) |

- **Approvals:**
  - Stages 1 to 5: the Head of Planning and Cost Control, or a super admin.
  - Stages 6 to 12: unchanged, a project manager on the project or a super admin.
  - Nobody approves their own submission.
- **Evidence:**
  - Stage 1 shows the TE details.
  - Stage 2 shows the PE number and who allocated it.
  - Stage 3 shows the award and signing dates.
  - Stage 4 shows whether a costing file is loaded.
  - The SAP steps show no evidence, because ProTrackAI has no SAP connection; the owner ticks them when done.

**Stages already worked on keep their work:**
- **Not started:** takes the new checklist.
- **In progress:** keeps every tick. Items with the same meaning carry their tick over (award, contract signed, documents handed over, PE number). Old items that no longer apply stay listed as optional, marked as from the earlier checklist.
- **Awaiting approval, Complete or Not applicable:** not touched.
- Each update is written to the stage history.

## Other changes
- **Server backup (Settings → System):** now also includes each project's lifecycle stages, stage history and register history.
- **Settings → Projects:**
  - offers the status **Pre-award**
  - shows a cancelled project as Cancelled, and saving it there keeps it cancelled
  - refuses a new project code that is already a live PE number
- **Project titles** show the PE number. For older projects this is their project code, as before.
- **Actions and approvals** leaves out cancelled projects.

## Database: `schema-update-v7.sql`
- **New columns on projects:** te_number, pe_number, client, location, expected_value_m, notified_on, award_on, contract_signed_on, cancelled_on, cancel_reason, registered_by, registered_at. They are empty for existing projects.
- **New tables:**
  - `pcc_designations`
  - `register_audit` (append-only)
- **New functions:**
  - `tender_act`, the only way to register, update, cancel, reinstate or change a PE number
  - `pe_proposal`
  - `pcc_designate`
- **Replaced function:** `lifecycle_act`. Stages 6 to 12 behave exactly as before.
- **One-time update** of open stage 1 to 5 checklists, as described above.
- **Nothing existing is deleted.** Running it twice is safe.
- **Rollback:** `schema-rollback-v7.sql` puts back the v6 rules and keeps every record.

## Verified

| Suite | Checks | Result |
|---|---|---|
| Database: Tender register, PE numbers, stages 1 to 5, rollback (`test_v7.py`) | 104 | 104 pass |
| Database: lifecycle (`test_v6.py`), imports (`test_v5.py`), reports (`test_v4.py`) | 53 + 64 + 125 | all pass |
| Server mode, end to end through the app (Tender scenarios added) | 98 | 98 pass |
| Tender register in demo mode (`tender_demo.py`) | 62 | 62 pass |
| Lifecycle, actions and dashboards in demo mode | 36 | 36 pass |
| Imports in demo mode | 34 | 34 pass |
| Regression, demo date and live date (with your PE-329 XER) | 77 + 77 | all pass, 2 skipped each |
| Functional suites / formula reference / backup and restore | 59 / 23 / 10 | all pass |
| Demo page: regression / lifecycle / Tender register | 77 / 36 / 62 | one expected difference (its own storage key) |

**Expected changes in the checks:**
- one fewer Planned menu item
- stage 1 is now called "Tender L1 notification"

**Stages 6 to 12 unchanged:** I also ran the v6 lifecycle tests with v7 installed. Every stage 6 to 12 check still passes. The 8 that differ are all on stages 1 and 4, where a project manager no longer approves and the old checklist items are gone, as intended.

**Not verified here:** Supabase itself (a local stand-in was used) and your live project.

**Not included:** an interface for Tender's new application, and importing the TE list from Excel. Both can come later.
