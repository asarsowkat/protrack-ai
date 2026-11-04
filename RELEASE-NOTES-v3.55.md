# ProTrackAI v3.55: the cash-out forecast's calculation and backup in the export

For any project, the cash-out forecast export now explains how its figures are reached and where each one comes from, so the forecast can be checked by hand or handed to an auditor.

## Excel export (one project): two new sheets

**Method**, the second sheet: the forecast step by step, with this project's figures, each step naming the sheet that backs it up.

| Step | Calculation | Backup |
|---|---|---|
| 1. Approved current budget | Rev-0 + approved supplements, latest monthly cost report released up to the cutoff | Budget |
| 2. Actual cumulative cash-out | Finance's cumulative at the cutoff; monthly actual = cumulative − previous | Monthly cash-out, Uploads and corrections |
| 3a. Subcontract PO milestones still to pay | Sum of the net of each unpaid milestone at invoice or planned date + payment days | PO payment schedule |
| 3b. Material PO milestones still to pay | Sum of net of each unpaid milestone at its tracking stage or P6 date + payment days | Material POs |
| 3c. Cost report heads | Sum of (EAC − actual) of the heads without POs, spread to the P6 forecast finish | Cost heads |
| 3d. Not yet ordered | Sum of ETC of the PO heads, spread the same way | Cost heads |
| 3e. Other cash-out lines | Sum of remaining, spread over their months | Other lines |
| 3f. Cost booked, not yet paid | when Finance paid less than the cost booked, the gap, next month | Reconciliation bridge |
| 3. Forecast remaining | 3a + … + 3f | Forecast by source |
| 4. Forecast at completion | 2 + 3 | |
| 5. Headroom, utilization | 1 − 4; 4 ÷ 1; 2 ÷ 1 | |
| 6. Reconciliation | 2 − paid PO milestones − cost booked − other lines paid; unexplained above the tolerance | Reconciliation bridge, Exceptions |
| 7. Cross-check | cost report EAC without the excluded heads, gap noted over 5% | Cost heads |
| 8. Status | the first that applies, and all that apply | Exceptions |

**Forecast by source**, after Monthly cash-out: the forecast month by month, one row per source (each subcontract PO, each material PO, the cost report heads, not yet ordered, each other line, the payable) with its Method step, a total per source and per month, and a check that the total equals the forecast remaining.

## PDF export

The Method table follows the key figures.

## Also in this release

The RASA item in the side menu now opens the RASA assistant.

No change to how the forecast is calculated. No server change: the export is built in the browser from the same figures.

## Checks

`tests/cashout_p6_demo.js`: two new checks (25, 26). The Method sheet's steps add up (3 = 3a + … + 3f, 4 = 2 + 3, 5 = 1 − 4, 6 = 2 − 6a − 6b − 6c) and agree with the Summary sheet. The Forecast by source total equals the forecast remaining, month by month and in total.
