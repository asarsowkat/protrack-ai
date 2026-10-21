# ProTrackAI v3.29: the budget supplement log by user field and category (October 2026)

**Cost Control → Logs → Budget supplements** is rebuilt. Each row is a supplement approved by its WF, with its user field, category and unified category, its WBS, and the four value columns the cost team reads: Supplement, Savings, VO Cost and VO Price. One screen shows one project or every project in scope, for one version (month), with filters. Rows can be added, changed and removed on the screen, or uploaded from Excel. Needs the server update v35 (STAGE-29-SETUP.md) on the live app.

## The columns

| Column | What it holds |
|---|---|
| Version | The month of the log, written **MMM-YY** (for example *Oct-26*) |
| No | The supplement number (BS-07) |
| WF date | The date the WF approved it. Only WF-approved supplements are recorded: there is no status column |
| User field | A cost report head (SM, DE, MTRL.ELC, MAN.CVL…) or **Cont. Value**, the contract value. The list is kept by the super admin |
| Category | One of the category list (Project Execution, Cont-Under Est., CHANGE ORDER, Mgmt Res-Proj Exe…) |
| Unified category | Picked automatically from the category, as the list maps it (Cont-Under Est. → Under Estimation) |
| Description | What the supplement is |
| Supplement · Savings · VO Cost · VO Price | The amount, put in one of the four columns (below) |
| Net value | The sum of the four columns: the impact on the gross margin |
| WBS Group · WBS ID · WBS Description | Where it sits in the WBS |
| Linked VO / claim · Remarks | Free text |

**One amount, put in one column.** The amount is the impact on the gross margin: negative for a supplement or a VO cost, positive for a saving or a VO price.

- Unified category **Change Order** and user field **Cont. Value** → **VO Price**.
- Unified category **Change Order**, any other user field → **VO Cost**.
- Any other category: a negative amount → **Supplement**, a positive amount → **Savings**.
- **Net value** = Supplement + Savings + VO Cost + VO Price = the amount.

**The budget change for the cost report** = −(the net value of the rows whose user field is not Cont. Value). A supplement or a VO cost raises the budget, a saving lowers it, and a VO price is contract value, not budget. It is shown as a tile on the screen and used by the cost report (*Budget change from the supplement log up to …*).

## The lists: Settings → Supplement lists (super admin)

- **User fields** (19 by default, from the sheet supplied): SM Site Management, DE Design, TEC Testing, MTRL.ELC, MAN.ELC, INSTL.ELC, MTRL.MECH, MAN.MECH, INSTL.MECh, MTRL.CVL, MAN.CVL, INSTL.CVL, CONT Contingency, SAD Saudization, FNE Financing, PC ITEMS Prime Cost, PROV. SUM Provisional Sum, Cont. Value Contract Value, MGT.RES Management Reserve.
- **Categories and their unified category** (24 categories mapping to 11 unified categories): Project Execution, Under Estimation, Change Order, External Factors, Savings, Claim, Finance, Contract Extension Cost, Saudization, Tender Budet, Contract Value.
- The super admin adds a user field (code and description) or a category (with the unified category it maps to, picked from the existing ones or typed new), removes one with ✕, or goes *Back to the standard list*. Each change is saved at once and listed in the change log. **Cont. Value** cannot be removed (it decides VO Price and the budget change); a code cannot appear twice. A row keeps a value removed from its list, shown as *not in the list*.

## The screen

- **Many projects.** A super admin, or anyone whose access covers more than one project, sees *All projects in scope* with a Project column, or picks one project. Someone with one project sees that project.
- **Version.** A version is chosen from the months that have a log. For each project the screen shows its log for that month, or its latest log before it. Each month's log is kept, so every version can be reported again.
- **Filters:** project, version, region, sector and project type (with many projects), category, user field, unified category, and a search over number, description, WBS, linked VO, remarks and project. *Clear filters* resets them.
- **Tiles:** Supplement, Savings, VO Cost, VO Price, Net value and Budget change of the rows shown.
- **On the screen** (costing engineers and the costing coordinator, right *Upload … budget supplement logs*): *Add a supplement*, *Change* and *Remove* on the latest log of a project. A removal asks for the reason. Every change is listed under *Changes on this screen* with who and when. *Start the Oct-26 version* copies the latest log into this month's version, to change from there. Earlier versions are read-only.
- **Excel.** *Download the template* gives a *Supplements* sheet with every column and four example rows, and a *Lists* sheet with the user fields, categories and unified categories. The upload matches the columns by their header. A file may give one *Amount* (or *Net value*) column, or the four value columns, which are added up. A row is refused, with the reason, when its user field or category is not in the list, its version is not the month of the log, its WF date is missing, invalid or in the future, or a text is too long. *Export to Excel* writes the rows shown, with the filters.

## Reports

- The executive report section is now **Budget supplements by unified category**, with the four columns, the net value and the budget change for the cost reports.
- The project view lists the latest log by unified category.
- The cost report's budget uses the new budget change.

## Logs from before v3.29

Rows without a user field keep their rule: they show *before v3.29*, their category is shown in today's list (Under estimate → Under Estimation, Claims → Claim…), and their approved amounts are added to the budget as before. Only their approved rows are shown (the screen says how many are left out), since the log records WF-approved supplements only. They are not changed on the screen. On the demo page the three sample rows of each project are given a user field, a WBS and the new categories, and two sample rows are added: BS-04, the contract value of VO-001 (VO Price), and BS-05, a saving on site facilities.

## On the server: schema-update-v35.sql

Run it on the live project, after v20 (STAGE-29-SETUP.md). It adds the user field, unified category and WBS columns to `budget_supplements`, the lists (`supp_lists`, kept by `supp_lists_set`, super admin only), the changes on the screen (`supp_update`, each one kept in the append-only `supp_audit`), the new checks in `log_import`, and the budget change (`pt_supp_approved`). The log stays append-only except through `supp_update`. Until v35 runs, the live app says so on the screen, the server takes only a log in the earlier layout, and rows cannot be changed on the screen. `schema-rollback-v35.sql` undoes it and keeps the data.

## Checks

- **New suite `tests/supplements_demo.js`** (37 checks): the split into the four columns and the net value, the budget change and the cost report, the many-projects view and every filter, only WF-approved rows shown, the version and the latest log before it, add, change and remove with the history, *Start the version*, the template and an upload with a refused version, the old-layout rows, the Settings lists (Cont. Value kept, duplicates refused, a new category used at once), the executive report section and the export.
- **Server tests on PostgreSQL 16 (PGlite)**: every update v2 to v35 applies, v35 runs twice, and 40 checks of v35 pass (the lists and their guards, log_import's refused rows, supp_update's add, edit, remove and version with the rights and the history, the append-only guard, the budget change, the rollback).
- **Every other browser suite passes** on the changed page: baseline comparison 18, BOQ Engine 53, BOQ sample 14, cash inflow 28, cash-out 27, cash-out on P6 24, contract value 25, presentation reports 16, delay correspondence 16, delay lists 15, delay register 26, E&P in reports 14, key milestones 20, margin and mail 17, cost visibility 28, project import 17, Project list 26, Project Visual 24, RASA modules 37, reporting status 28, Tender NOA 22, executive report status 11 (506 checks). The Python Playwright suites were not run: Python is not installed on the machine used.
