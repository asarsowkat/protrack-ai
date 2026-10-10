# ProTrackAI v3.2: activity quantities in the daily report (October 2026)

Built from your requirement of 10 October 2026.

## What changed

### New report: the activity's quantities
When the foreman or site engineer chooses an activity, the report shows:

| Figure | How it is worked out |
|---|---|
| Total quantity (scope) | The activity's quantity from the baseline |
| Executed up to yesterday | Progress before ProTrackAI (from the baseline import) + every submitted, reviewed or approved daily report before the report date |
| Balance | Scope − executed up to yesterday |
| Balance duration | Working days (Friday off) from the report date to the activity's planned finish |
| Plan for today | Balance ÷ balance duration. Before the planned start it is 0; after the planned finish the whole balance is due |

- **Actual quantity today:** the foreman or site engineer enters it. The field was called "Quantity executed".
- **Total to date:** the form shows the total to date with today, as a share of the scope.
- **Other reports for the same date:** quantities already reported for that date count towards the total, and the form says so.
- **Changing the date** recalculates the figures.
- **The submitted report** shows the same figures as at its date.

### Quantity beyond the scope
- **Accepted:** if the total to date with today goes beyond the scope, the quantity is still accepted. The form shows an amber note with how much over.
- **Flagged for the reviewer:** a notification is raised and the report list marks it "Beyond scope".
- **Justified at review:** the site engineer, or whoever reviews it, must write a justification for each such activity before **Mark as reviewed**. A few words at least, for example a re-measurement, a drawing revision or an instruction received.
- **Kept with the report:** the justification is stored with this report's quantity, the total to date and the scope, and appears in the audit trail. It cannot be changed or deleted.
- **Checked again at approval:** if the quantity is changed after the review, the site manager cannot approve until it is justified again (return the report to the engineer).
- **Return and reject** need no justification.
- **On the server:** these rules are checked by the server as well as in the app.
- **Calculations unchanged:** progress and earned value still count an activity as at most 100% complete, as before.

### Backups
- **Server backup:** now also holds the progress and cost releases, the change order, claim and supplement logs, the issue register and the quantity justifications. The v3.0 and v3.1 backups did not include them.

## Database: `schema-update-v11.sql`
- **New table:** `dpr_qty_just` (append-only), readable by people on the project.
- **New helper:** `pt_dpr_over`, which finds the activities beyond their scope on a report.
- **Changed function:** `dpr_act` gains an optional last argument for the justifications. Its other rules are unchanged.
- **Existing reports and history are untouched.** Safe to run twice.
- **Rollback:** `schema-rollback-v11.sql` restores the v4 review function and keeps every justification.

## Verified

| Suite | Checks | Result |
|---|---|---|
| Database: within and beyond the scope, justification rules, edit after review, same-day reports, drafts and rejected reports not counted, who reads, rollback (`test_v11.py`) | 46 | 46 pass |
| Server mode, end to end through the app (v10 and v11 applied mid-run; quantity scenarios and fuller backup added) | 149 | 149 pass |
| Activity quantities and the review rule in demo mode (`qty_demo.py`), app and demo page | 28 + 28 | all pass |
| Issue register / released reporting, app and demo page | 60 + 60 / 53 + 53 | all pass |
| RASA / Tender register / lifecycle / imports, app and demo page | 32 / 62 / 36 / 34 | all pass |
| Regression, demo date and live date (with your PE-329 XER) | 77 + 77 | all pass, 2 skipped each |
| Functional suites / formula reference / backup and restore | 59 / 23 / 10 | all pass |
| Demo page: regression and functional suites | 77 / 54 | one expected difference each, as before (fixed storage key and date mode) |

**No existing check had to change.** The server backup check now counts reports instead of expecting exactly four, because the new scenario adds a report.

**Not verified here:** Supabase itself (a local stand-in was used) and your live project.

## Still open
- **The productivity index** still uses the planned rate (quantity per manhour), not today's plan. Tell me if you also want the plan achievement (actual ÷ plan for today) shown on reports and scorecards.
