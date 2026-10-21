# ProTrackAI v3.31: a version on each budget supplement row (October 2026)

**Cost Control → Budget supplements:** each row now has its own **Version**, the month the supplement applies to, whatever its WF date. Needs the server update v36 (STAGE-30-SETUP.md) on the live app.

## Why

A WF is sometimes approved in SAP on 5 October while management approved the values on paper in September: the supplement belongs to the **September** version. Until now the version was the month of the whole log, so a row could not belong to an earlier month than the log it was entered in, and the grid had no Version column.

## What changes

- **The grid** has a **Version** column first: a drop-down of months (the last three years up to this month). A new row starts on the version chosen on the screen, else this month. A range pasted from Excel may carry it (Sep-26, 2026-09). A version after this month is refused.
- **The screen** shows a version as **every row up to it** (what the cost report of that month counts) or, with **Show: This version only**, the rows of that month. The table and the export show each row's version.
- **The log of a project** is its latest log; the version of each row says which month it counts in. Earlier logs stay in Import history.
- **The cost report** of a month counts the rows whose version is up to that month: a September supplement entered in October counts in September. The executive report and the project view do the same.
- **Uploads**: a file is the whole log of the project as of the month of the upload. Each row keeps its **Version** (blank: the month of the upload); a version after the month of the upload is refused, an earlier one is kept. An upload for a month before the project's latest log is refused. The field is now called **Month of this upload**.
- **Rows already logged** keep their figures: each gets the first month its number appears in the project's logs (on the server with v36, on the demo page at once).
- *Start the MMM-YY version* (a copy of the log for a new month) is no longer needed and is gone from the screen; a project without a log still has *Start the MMM-YY log here*.

Until v36 runs on the live server, the screen says so and a row's version stays the month of its log, as in v3.30.

## Server: schema-update-v36.sql

Adds `budget_supplements.version`, fills it for the rows already logged, and updates `pt_supp_row`, `pt_supp_approved`, `log_import`, `supp_update` and `supp_features`. `schema-rollback-v36.sql` puts the v35 functions back and keeps the column.

## Checks

- **Server (PostgreSQL 16, PGlite), 23 checks:** v36 applies twice; rows already logged get their first month and the cost figures are unchanged; a row added with an earlier version and a later WF date counts in its month and not before; a version after this month or not a month is refused; a changed version is in the history, and an edit without one keeps it; an upload keeps each row's version, fills a blank one, refuses a later one; an upload before the latest log is refused; the rollback (also on a database without v36 or v35) and v36 again. The v35 checks (40) still pass.
- **`tests/supplements_demo.js`, 57 checks.** New: the Version drop-down in the grid; a row saved as last month with a WF date this month, counted by last month's cost report; the screen by *this version only* and *up to this version*; an upload for a month before the latest log refused; an upload row keeping an earlier version.
- Suites sharing the screen pass: contract value 25, reporting status 28, cost visibility 28, executive report status 11, RASA modules 37.
