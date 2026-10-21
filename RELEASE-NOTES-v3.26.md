# ProTrackAI v3.26: E&P progress inside the internal and client reports (October 2026)

**E&P progress** is now a tab of every **internal report** and **client report**, weekly and monthly. The separate screen is gone: there is no menu item and no phone shortcut, and its old address opens Internal Reporting.

**No double upload:**
- The progress and dates come from the **same updated P6 schedule the report uses**: the one in force at the end of the report's period. The client report uses the schedule with client weightage.
- Each week or month, the planning engineer uploads the updated schedule once, in Baselines and P6 import. The report, its E&P tab, its progress by phase and its milestones all read it.

**What the tab shows:**
- The schedule it comes from: its data date and file, and whether it is stale (over 8 days old).
- Three totals, each with plan, actual and the number forecast late:
  - engineering progress, weighted by budget manhours;
  - procurement progress, weighted by package value;
  - engineering and procurement together.
- Each engineering and procurement activity:
  - plan, meaning baseline progress at the schedule's data date;
  - actual %, actual start and actual finish;
  - baseline finish, forecast finish, and slip in days.
- Without an updated schedule up to the end of the period, the tab says so. It shows the baseline plan only and invents no actuals.

**Where else it appears:**
- **Saving:** the tab's figures are saved with the report and frozen at approval. A version saved before v3.26 says so.
- **Executive report:** the project view shows it as released.
- **Client report exports:** the Excel has an *E&P progress* sheet, and the printed copy has the totals.

**Unchanged:**
- The late-item notification and the updated-schedule compliance check.
- Construction progress, which still comes from the daily reports.

**Server:** `schema-update-v33.sql`, after v30. The server works out the same E&P table (`pt_ep_tbl`) and saves it with each internal and client report through `release_act_km`. Until it runs, live reports show the tab but are saved without it. Undo: `schema-rollback-v33.sql`. Not yet run on a database.

**Checks:**

| Suite | Result |
|---|---|
| `tests/ep_report_demo.js` | 14 checks |
| Intermediate milestones | 17, still passing |
| Baselines | 18, still passing |
| Reporting status | 28, still passing |
| Executive report | 11, still passing |
