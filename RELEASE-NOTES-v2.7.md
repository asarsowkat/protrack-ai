# ProTrackAI v2.7: Phase 4, workflow and dashboards (October 2026)

## What changed

### Governed project lifecycle

Project overview now shows twelve stages, from tender notification to final account and closeout, taken from the master prompt. They replace the seven-stage checklist from v2.3.

Each stage records:
- status: Not started, In progress, Awaiting approval, Complete or Not applicable
- department and owner
- due date, with an overdue flag
- required and optional deliverables, each with who ticked it and when
- next action, blockers and dependencies, and risks
- pending approver, submitted by, approved by
- full history

The rules, enforced in the app and again on the server (`lifecycle_act`):
- A stage is complete only when its owner submits it with every required deliverable ticked and an approver approves it. The approver is a project manager on that project or a super admin.
- **Nobody approves a stage they submitted.** A super admin needs a second super admin or a project manager.
- Return to the owner, Not applicable and Reopen all need a comment. Only a super admin reopens a closed stage, and approval is cleared when they do.
- Closed stages are read-only.
- The owner must have access to the project. Only the project manager or a super admin assigns the owner.
- **Evidence never completes anything.** Next to each deliverable ProTrackAI shows what it already holds, for example "120 activities in the baseline" or "10 reports in the last 7 days", but only the owner ticks the box. Opening a screen or uploading a file never moves a stage.
- History is append-only. It cannot be edited or deleted, even from the database console.
- Closing a project hides or deletes nothing.

The lifecycle reuses existing records: projects, people, project access, the project manager role, milestones, imports and reports. There is no parallel project or approval system. The daily-report approval matrix is unchanged.

### Actions and approvals

New under Projects & Handover. It is one list, built from the records themselves, of:
- daily reports waiting for review or approval, with the person they wait on
- returned reports to fix
- lifecycle stages awaiting approval or past their due date
- stages you own
- imports that failed and were never retried

**Mine** and **Everyone in scope** split the list. **Open** goes to the item; nothing is approved from the list itself. Foremen, site engineers and site managers see it too, for their own items.

### Planning dashboard

New under Planning & Scheduling. One row per project shows:
- current lifecycle stage
- the baseline: activities, when it was loaded, and stage 6 status
- DCMA score
- SPI
- planned and actual progress
- the next milestone and its slip
- overdue milestones
- the last weekly engineering and procurement update, marked stale after 8 days
- late engineering and procurement items

The critical path is stated as calculated in Primavera P6. A dash means the data is not in ProTrackAI. Nothing is estimated in its place.

### Cost Control dashboard

New under Cost Control. These figures are shown side by side and never added together:
- contract value
- budget from the costing file
- earned value
- actual labour cost from daily reports
- forecast cost (EAC)
- CPI
- invoiceable, invoiced and collected

Approved budget revisions, commitments and accruals are labelled **Not tracked yet**. The dashboard states that actual cost here is not SAP actual cost.

**Source reconciliation** compares the budget and invoice register in ProTrackAI with the total of the last accepted costing file and invoice register in the Import centre. The planned menu item **Cost reconciliation** now opens it.

### Demo mode

Demo projects carry sample lifecycle states so the screens can be shown. On the server, every stage starts **Not started**.

## Behaviour changes to know about

- The Project overview's seven-stage checklist is replaced by the twelve governed stages.
- Foremen now have **Actions and approvals** in their menu, for returned reports.
- "Cost reconciliation" is no longer marked planned.
- No formula changed.

## Database: `schema-update-v6.sql`

- **New tables:** `lifecycle_stages` and `lifecycle_audit`, readable only by people with access to the project. Neither has write policies, so `lifecycle_act` is the only way in.
- **History is append-only.**
- **Nothing existing changed.**
- **Safe to run twice.**
- **Reversible:** `schema-rollback-v6.sql` removes the functions and keeps every stage and history entry.

## Verified

| Suite | Checks | Result |
|---|---|---|
| Database, lifecycle rules (`test_v6.py`) | 53 | 53 pass |
| Database, imports (`test_v5.py`) | 64 | 64 pass |
| Database, reports and audit (`test_v4.py`) | 125 | 125 pass |
| Server mode, end to end through the app | 78 | 78 pass |
| Lifecycle, actions and dashboards in demo mode (`lifecycle_demo.py`) | 36 | 36 pass |
| Imports in demo mode | 34 | 34 pass |
| Regression, demo date | 77 | 77 pass, 2 skipped |
| Regression, live date | 77 | 77 pass, 2 skipped |
| Functional suites | 59 | 59 pass |
| Formula reference | 23 | 23 pass |
| Backup and restore | 10 | 10 pass |

The 2 skipped regression checks need things this environment lacks: the export libraries (no internet access) and a PMXML sample file.

**Bug found and fixed by these tests:** before any owner was assigned, "is this person the owner?" came out as "unknown" instead of "no". That let a foreman edit an unowned stage. The server now treats a missing owner as "not the owner". This is the same kind of mistake as the one caught in v2.5, and it is now tested both ways.

**Regression and suite checks updated, on purpose:**
- seven stages became twelve
- the foreman menu now includes Actions
- one fewer planned menu item

**Not verified here:** Supabase itself (a local stand-in was used) and your live project.
