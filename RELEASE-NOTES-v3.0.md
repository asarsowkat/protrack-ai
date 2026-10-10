# ProTrackAI v3.0: released reporting (October 2026)

Built from your requirement of 10 October 2026 and your answers:
- releases need your approval before management sees them
- monthly actual cost and commitments may be typed or uploaded
- build the logs now with your field list and adjust when the sample VO log arrives

## What changed

### Daily reports are input; management reads released versions
- **Progress releases** (Planning & Scheduling → Progress releases), weekly and monthly, prepared by the planning engineer:
  - ProTrackAI fills in what it computes now: planned and actual progress, SPI, design and procurement progress against plan, forecast finish, productivity and workforce.
  - The engineer reviews it and may change any figure, but only with a reason. The computed value and the reason are kept with the release.
  - Comments: progress summary, key issues (site, design, procurement), next actions.
- **Monthly cost reports** (Cost Control → Monthly cost report), prepared by the costing engineer or costing coordinator:
  - Inputs: Rev-0 budget, actual cost to date, commitments and forecast cost to complete. They are typed, or uploaded for several projects with the template; each uploaded row becomes that project's draft.
  - The server works out the rest the same way every month:
    - approved budget = Rev-0 + approved supplements
    - EAC = actual + forecast to complete
    - VAC = approved budget − EAC
  - The form shows these figures as you type.
- **Approval:**
  - Every release is submitted to the Head of Planning and Cost Control (or a super admin), who approves or returns it with a comment.
  - Nobody approves their own submission.
  - Releases waiting, and releases returned for fixing, show in Actions and approvals.
- **A released version never changes,** even from the database console. A correction is a new revision with a reason. Management keeps seeing the released revision until the new one is approved, and the old one is kept as superseded.

### Executive report (Home)
- **Choose Monthly or Weekly and the period.** The report reads only released versions:
  - progress and key issues per project
  - for months: released cost (Rev-0 budget, approved supplements, approved budget, actual, commitments, EAC, VAC), change orders and claims, and budget supplements by category
- **Missing releases:** a project without a release shows "Not released". Live figures are never filled in.
- **Weekly reports** carry progress only.
- **The previous executive summary** is now **Live summary (working data)**, with a note pointing to the released report.

### Change order and claim log, budget supplement log
- **Uploaded monthly per project** by the costing engineer or costing coordinator: Claims & Variations → Change order and claim log, and Cost Control → Budget supplements.
- **Change order and claim log fields:** reference, type (VO or Claim), description, submission status and date, client approval status, estimated price and cost, expected price to be approved, price and cost considered internally, change in Rev-0 budget, internal workflow status, overall approval status with the client, remarks.
- **Budget supplement log:** each supplement is categorised as Project execution, Under estimate, External factor, Saudization, Finance, Claims or Change order. Only Approved supplements are added to the budget in the cost report.
- **Controlled uploads:**
  - all-or-nothing, as numbered import batches
  - refused rows must be acknowledged before the rest is saved
  - the same file for the same month is not loaded twice
  - every month is kept and can be shown later
- **Column headings are matched loosely,** so your own headings are likely to work. The template is offered either way.

### Elsewhere
- **Cost Control dashboard:** budget supplements and commitments now come from the last released cost report. Accruals stay "Not tracked yet".
- **RASA** answers from released data and the logs, and names them in its "Based on" line:
  - commitments and actual cost from SAP, from the released cost reports
  - change orders and claims, from the latest logs
  - "the monthly report", from the released progress
- **Menus:**
  - Variation register, Claims register and Budget revisions are no longer marked Planned.
  - "Commitments and accruals" is now just "Accruals" (planned).

## Database: `schema-update-v9.sql`
- **New tables:**
  - `report_releases`
  - `release_audit` (append-only)
  - `co_log` and `budget_supplements` (one full copy per monthly upload, append-only)
- **New functions:** `release_act` and `log_import`, the only ways to write them.
- **Other changes:** import batches accept the two log kinds.
- **Who reads what:**
  - Cost reports and both logs reach only roles that may see cost.
  - Drafts are visible only to the preparers and the Head.
- **Nothing existing changes.** Safe to run twice.
- **Rollback:** `schema-rollback-v9.sql` removes the writing functions and keeps every release and log, still readable.

## Verified

| Suite | Checks | Result |
|---|---|---|
| Database: releases, approval, revisions, formulas, logs, rollback (`test_v9.py`) | 79 | 79 pass |
| Server mode, end to end through the app (release, cost and log scenarios added) | 119 | 119 pass |
| Released reporting in demo mode (`release_demo.py`), app and demo page | 53 + 53 | all pass |
| RASA / Tender register / lifecycle / imports in demo mode | 32 / 62 / 36 / 34 | all pass |
| Regression, demo date and live date (with your PE-329 XER) | 77 + 77 | all pass, 2 skipped each |
| Functional suites / formula reference / backup and restore | 59 / 23 / 10 | all pass |
| Demo page: regression | 77 | one expected difference (its own storage key) |

**Checks changed on purpose:**
- **Planned menu items:** three fewer.
- **Cost dashboard:** "Not tracked yet" now applies to accruals only.
- **RASA:** answers commitments, SAP actual cost and variations from the released reports and logs instead of "No evidence".

**Not verified here:** Supabase itself (a local stand-in was used) and your live project.

## Still open
- **Your sample VO log:** I'll match the columns and statuses to it when you send it.
- **Cost detail:** cost reports are at project level. A breakdown by cost category (site management, installation, mechanical, civil) can be added if you want it.
- **SAP files:** an SAP export can replace the template once you share a sample. ProTrackAI still has no SAP connection.
