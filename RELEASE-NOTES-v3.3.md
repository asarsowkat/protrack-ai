# ProTrackAI v3.3: monthly cost report in the company format (October 2026)

Built from your sample of 10 October 2026 (the PE-336 cost report layout).

## What changed

### The monthly cost report, one row per WBS head
- **Rows:** the 18 heads of your format, from SM Site Management, DE Design and TEC Testing through the electrical, mechanical and civil material, manpower and installation heads, SAD Saudization, FNE Financing, PC items and provisional sum, to CONT Contingency and MGT.RES Management Reserve. An **Overall** row adds them up.
- **Columns, as in your sheet:**

| Column | In ProTrackAI |
|---|---|
| A Tender, B1 Rev-0, B2 Revised Rev-0 (latest approved CRF) | Entered with the month of each, carried to the next report |
| C Prev. version | The current budget (D) of the last released cost report, line by line. Entered by hand only on the first report by WBS head |
| D Current budget, E Actual, F Commitment | Entered for the month |
| G Balance | D − E − F |
| H ETC | Entered |
| I EAC | E + F + H |
| J Supplement (−) / saving (+) | D − I, in brackets and red when negative |
| Justification | Per line, plus a note on the Overall row. **A line with a supplement or a saving needs a justification before the report can be submitted** |

- **Header:** planned and forecasted TCC and planned and actual POC, filled in from the month's released progress when there is one.
- **Contract value and gross margin:** gross margin and % gross margin for columns A to D and for EAC.
- **As you type:** G, I, J and the Overall row are worked out on screen. The server works out the same figures again when the report is saved, so what a browser sends is never taken as the total.
- **Fill from Excel (company format):** choose your monthly sheet in the report.
  - Lines are matched by user field code or WBS head name; rows that are not WBS heads are ignored.
  - The TCC dates, POC, column months, contract value and Overall note are read too.
  - If the file's Overall row differs from the sum of its lines, you are told.
  - You check the figures, then save.
- **Export to Excel** in the same layout, from the released report and from the executive report.
- **Executive report → Project view** shows the full table. The summary's cost table now says "Current budget".

### What this changes in the cost figures, on purpose
For reports in the new format:
- **Current budget is entered.** It is D as approved, no longer worked out as Rev-0 plus the approved supplements in the log. The log total is shown beside the report for reconciliation.
- **EAC is unchanged in meaning:** actual + commitment + ETC. "Forecast to complete", used elsewhere in ProTrackAI, is now commitment + ETC, so EAC = actual + forecast to complete still holds.
- **VAC = current budget − EAC,** the overall J.

Older reports, and drafts from the quick multi-project upload (totals only), work exactly as before. A totals-only draft has a button to switch it to the company format.

## Database: `schema-update-v12.sql`
- **New helper:** `pt_cost_wbs` checks the WBS lines and works out every line and total.
- **Changed function:** `release_act` accepts the WBS lines, takes the previous version from the last released report, and refuses to submit a report with an unjustified supplement or saving. Totals-only reports are handled as before.
- **No table changes.** Safe to run twice.
- **Rollback:** `schema-rollback-v12.sql` restores the v3.2 function. Every report is kept, including those by WBS head.

## Verified

| Suite | Checks | Result |
|---|---|---|
| Database: WBS lines and formulas, previous version, header, validation, justification at submit, approval and freezing, revisions, rollback (`test_v12.py`) | 44 | 44 pass |
| Server mode, end to end through the app (v12 applied mid-run; cost-by-WBS scenarios added) | 158 | 158 pass |
| Cost report in the company format in demo mode (`cost_demo.py`): seeded reports, formulas, form, Excel fill and export, justification, totals-only drafts, next month, app and demo page | 28 + 28 | all pass |
| Quantities / issues / released reporting, app and demo page | 28 / 60 / 53 each | all pass |
| RASA / Tender register / lifecycle / imports, app and demo page | 32 / 62 / 36 / 34 | all pass |
| Regression, demo date and live date (with your PE-329 XER) | 77 + 77 | all pass, 2 skipped each |
| Functional suites / formula reference / backup and restore | 59 / 23 / 10 | all pass |
| Demo page: regression and functional suites | 77 / 54 | one expected difference each, as before |

**Checks changed on purpose:**
- **The released-reporting test (`release_demo.py`)** now fills in the cost report by WBS head, with a justification. It expects current budget = D rather than Rev-0 + supplements.
- **The site-staff checks** now also look for "Current budget" and "EAC" on their screens.

**Not verified here:** Supabase itself (a local stand-in was used) and your live project. The Excel fill was tested with a sheet laid out like your sample but with made-up numbers. Try it once with a real sheet.

## Still open
- **More than one project at once:** the quick multi-project upload still gives totals only. Tell me if you want one workbook with a sheet per project instead.
- **Cost breakdown below the WBS heads:** not included. Tell me if you need it.
