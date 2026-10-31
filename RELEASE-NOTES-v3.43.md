# ProTrackAI v3.43: the cost plan upload and the monthly actual POC upload (October 2026)

The bulk upload of v3.42 is split in two, because the two change at different times:
- **the cost plan**, revised once or twice a year;
- **the actual POC**, uploaded every month.

Both are in **Cost Control → Cost plan**, for a super admin or the costing coordinator.

## Cost plan upload (once or twice a year)

**Download the template** (the export) and upload it back. It has one row per project in three sheets:

| Sheet | Columns read |
|---|---|
| **COST PLAN (I)** | Budget, Contract value, and the planned cost of each month (SAR) |
| **COST PLAN (F)** | Target POC at year end, Approval reference, and the POC % of each month |
| **ACTUAL TO LAST YEAR** (new) | Actual POC end of last year, Budget at December of last year, Contract value at December of last year: the year start |

**About ACTUAL TO LAST YEAR:**
- A project whose December has a released cost report takes the year start from that report. The sheet shows where each figure comes from, and the upload says so.
- A blank cell keeps what is saved.

**Other rules:**
- The COST PLAN (F) sheet still shows the actual POC at the end of last year, for the check, but it is read only from an older (v3.42) workbook without ACTUAL TO LAST YEAR.
- An ACTUAL POC sheet in a cost plan workbook is no longer read; the preview says to use the monthly file.

Everything else is as in v3.42: the preview, the refusals, saving together, and plans back to Draft.

## Actual POC upload (every month)

Choose the month and **Download the month's template**. It is one sheet, **ACTUAL POC**, with:
- the month in its "Month" cell;
- for each project: **Actual POC in the month (%)** and **Cumulative actual POC from start (%)**;
- for reference: ProTrack's cumulative POC at the end of last month, and whether the month has a released cost report.

**Give one of the two for each project:**
- **the POC in the month**, as it is;
- **or the cumulative POC from the project's start**: ProTrack takes the month's POC as cumulative − the cumulative at the end of the month before. That earlier cumulative includes the actual POC uploaded for that month.

Leave a project blank to skip it.

**Upload it.** The month written in the file is the one saved, whatever month the page shows. The preview shows the POC in the month, the cumulative and the result.

**Refused:**
- the two figures do not agree;
- only a cumulative is given, and ProTrack does not know last month's cumulative;
- a cumulative that looks like a fraction;
- plus the usual project checks.

A month with a released cost report is accepted with a note: the cost report comes first.

**Saving** adds the month to the project's actual POC of the year and keeps the other months. The cost plans are untouched and stay agreed and approved. The history says "Actual POC Sep 2026".

## Server

No change: both uploads use `cost_plan_import` from v46 (STAGE-40-SETUP).

## Checks

`tests/cost_plan_import_demo.js` now has 21 checks, all passing on the demo page:
- the two uploads and who uses them;
- the cost plan template and its year-start sheet, read back untouched;
- the changes, refusals and saving;
- the monthly template;
- the month in the file;
- the POC in the month and the cumulative, and the two disagreeing;
- saving month after month;
- the cost report first;
- the MER.

`tests/mer_demo.js` still passes, 25 of 25; its check 24 now expects ACTUAL TO LAST YEAR.
