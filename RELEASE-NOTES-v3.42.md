# ProTrackAI v3.42: the cost plans in bulk from Excel (October 2026)

**Cost Control → Cost plan** gets a **Bulk upload (Excel)**. A super admin or the costing coordinator can now load the internal plan, the finance plan and the actual POC of many projects at once from one workbook, instead of entering each project by hand.

## The workbook

**Download the template** gives the same workbook as the export: every project you keep, with its current plans for the year chosen on the page. It has three sheets, one row per project by its project code (Proj. ID):

| Sheet | Columns read |
|---|---|
| **COST PLAN (I)** | Budget, Contract value, and the planned cost of each month (SAR) |
| **COST PLAN (F)** | Actual POC end of last year, Target POC at year end, Approval reference, and the POC % of each month |
| **ACTUAL POC** | The POC % reached in each month |

- Other columns are ignored (totals, quarters, status), so the company's own COST PLAN (I) / (F) sheets can be used when their headers match.
- A sheet may be left out, and so may a project. An empty budget or contract value keeps the current one.
- **Percentages:** a percent cell is read as Excel shows it (12.50 %); a plain number is read as percent points (12.5 = 12.5 %).

## The upload

Upload the workbook. **Nothing is saved until you confirm.** The preview lists every row with its figures and the result:
- **New** or **Change**: it will be saved;
- **No change**: it matches the saved plan;
- or why it is refused, and then that row is not saved.

**Refused rows:**
- an unknown project, or a project that is not yours;
- a project twice in a sheet;
- a value that is not a number, or out of range (the same checks as a single save);
- the months of another year (the whole sheet);
- finance percentages that lost their percent format (0.7 for 70 %).

An actual POC row with every month under 1 % gets a warning to check the format.

**Save the N new or changed plans** saves them together, with an optional comment.
- Each saved plan returns to **Draft**: the project manager agrees the internal plan again, and management approves the finance plan again.
- The history says "Bulk upload: file name".
- The year start (actual POC end of last year) is saved only when December has no released cost report.

## Actual POC in the cost plan and the MER

The actual POC of a month now comes from that month's released cost report, as before, or, **when there is none, from the uploaded actual POC.**
- The cost plan page marks uploaded months with **u**.
- The MER uses them for the actual POC this year and the year-end forecast, and says "actual POC partly from the upload" on that project's row.
- A released cost report always comes first.

## Who

- **Upload:** a super admin, or the **costing coordinator** (Settings → Users → Planning and Cost Control), for the projects they see.
- The costing engineers keep entering their own projects' plans one at a time, as before.

## Server

`schema-update-v46.sql` (with `schema-rollback-v46.sql` and STAGE-40-SETUP.md):
- the column `cost_plans.plan_act`;
- `cost_plan_save` takes the actual POC;
- `cost_plan_import` saves an upload all or nothing, each row with the rights and checks of a single save.

It needs v45. It has not yet been run on a database.

## Checks

**New suite:** `tests/cost_plan_import_demo.js`, 15 checks, all passing on the demo page. It covers:
- who uploads;
- the template and its percent cells; reading it back untouched;
- changes, including 55% typed as text;
- the refusals;
- the preview and saving through the screen: back to draft, the history note, refused rows not saved;
- a costing engineer refused;
- the uploaded actual POC in the MER, after a released cost report of the same month, and for a project without cost reports.

`tests/mer_demo.js` still passes, 25 of 25.
