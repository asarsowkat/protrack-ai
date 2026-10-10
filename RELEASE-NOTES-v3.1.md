# ProTrackAI v3.1: issue register and released executive summary (October 2026)

Built from your requirement of 10 October 2026, with your company issue log as the model for the issue columns.

## What changed

### Executive report: Summary and Project view
- **Summary** (Home → Executive report (released)), built only from released versions, like the live summary:
  - **headline figures:** projects released, progress and SPI weighted by contract value, EAC and VAC, invoiced and collected, projects needing attention
  - **by region and by sector:** projects, value, released progress against plan, SPI, EAC, VAC, invoiced, collected, open issues and critical projects
  - **critical projects:** released SPI under 0.95, a negative VAC, a forecast finish more than 30 days after baseline, or an extremely high open issue. Each row says why and shows the main issue, with a button to the project view
  - **billing and collection:** invoiceable, invoiced, approved, collected, not yet invoiced and outstanding, as saved in each released cost report
  - **change order and claim status:** counts and expected price by client status (approved, partially approved, pending, rejected), from the logs
  - the progress, cost, change order and supplement tables by project from v3.0 stay below
- **Project view:** choose a project to see its released progress (design and procurement against plan, forecast finish, workforce), the planning engineer's comments and any changed figures with reasons, the issues saved with the release, cost and billing, its change orders, claims and supplements, and its release history.
- **Weekly reports** still carry progress only. Site staff still see no cost.

### Issue register (Projects & Handover → Issue register)
- **For issues beyond P6 and ProTrackAI's own data,** with the columns of your issue log:
  - data date, issue owner and sub owner, issue type, start date, description, impact (Extremely High, High, Medium, Low)
  - action taken, action required, priority by client and internal priority (A, B, C), action by
  - planned and forecast targets, status, closure date, remarks, schedule impact, cost impact
- **Who keeps them:**
  - The planning and costing engineers of a project add and update its issues, close and reopen them (reopening needs a reason).
  - The Head of Planning and Cost Control and super admins can keep any project's issues and mark them reviewed with a note.
  - Project managers, executives and regional managers see them. Site staff do not.
  - The server enforces all of this.
- **Review by region or sector:** open, extremely high, past target and not-reviewed counts by region and by sector. Tap a row to filter. You can also filter by impact, owner, type, reviewed and past target, and search.
- **Every change is kept** with who, when and which fields changed.
- **Excel:**
  - Upload your issue log as it is; its header row is recognised.
  - Rows are matched to existing issues by project and description, so the next upload updates them instead of duplicating them.
  - Refused rows are listed and must be confirmed before the rest is saved: another engineer's project, an unknown project, a missing description, a wrong impact.
  - Text such as "NA" in a date or priority column is kept in Remarks rather than refused.
  - Template and export to Excel.
- **Saved with the release:** when you approve a progress release, the project's open issues are saved with it and never change afterwards, so the executive report shows the issues as they were when released. The cost impact text is not saved with the release, because site staff can read progress releases.

### Billing in the monthly cost report
- **A new "Billing to date" section:** invoiceable, invoiced, approved and collected.
- **Filled in for you** from the invoice register and the invoiceable value; the costing engineer can change the figures.
- **Optional;** amounts cannot be negative.
- **Not used in EAC or VAC.** The cost formulas are unchanged.

### RASA
- **Questions about issues and bottlenecks** are answered from the issue register, for the whole scope or for a region or sector named in the question. The answer names the register as its source.

## Database: `schema-update-v10.sql`
- **New tables:**
  - `issues`
  - `issue_audit` (append-only)
- **Releases:** a new column, `issues_snapshot`, filled when a progress release is approved and frozen with the rest of the release.
- **New functions:** `issue_act` and `issue_import`, the only ways to write issues.
- **Changed function:** `release_act` saves the open issues at approval and refuses negative billing amounts. Its other behaviour and the cost formulas are unchanged.
- **Who reads what:**
  - Issues reach only people with access to the project, and not site staff.
  - Import batches accept the "issues" kind.
- **Nothing existing changes;** existing releases keep an empty issue list. Safe to run twice.
- **Rollback:** `schema-rollback-v10.sql` removes the issue functions and restores the v9 release functions. Issues, history and saved snapshots are kept.

## Verified

| Suite | Checks | Result |
|---|---|---|
| Database: issues, rights, upload, snapshot at approval, billing, rollback (`test_v10.py`) | 51 | 51 pass |
| Server mode, end to end through the app (v10 applied mid-run to a database in use; issue, upload, review, snapshot and billing scenarios added) | 136 | 136 pass |
| Issue register and executive summary in demo mode (`issues_demo.py`), app and demo page | 60 + 60 | all pass |
| Released reporting in demo mode (`release_demo.py`), app and demo page | 53 + 53 | all pass |
| RASA / Tender register / lifecycle / imports in demo mode, app and demo page | 32 / 62 / 36 / 34 | all pass |
| Regression, demo date and live date (with your PE-329 XER) | 77 + 77 | all pass, 2 skipped each |
| Functional suites / formula reference / backup and restore | 59 / 23 / 10 | all pass |
| Demo page: regression and functional suites | 77 / 54 | one expected difference each, the same as on the v3.0 demo page (its fixed storage key and date mode) |
| Your issue log, read by the upload (in this workspace only; not stored or published) | 721 rows | 713 accepted; refused: 7 blank continuation rows, 1 row with an unrecognised project code |

**No existing check had to change.**

**Not verified here:** Supabase itself (a local stand-in was used) and your live project.

## Still open
- **Your sample VO log:** columns and statuses will be matched when you send it.
- **Cost breakdown by category:** available if you want it.
- **Issue types and owners:** the lists follow your issue log. Typing a new value works, and the lists can be changed if you want them fixed.
