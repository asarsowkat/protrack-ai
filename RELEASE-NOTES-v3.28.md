# ProTrackAI v3.28: the Project list report (October 2026)

A new report, **Project list**: one row per project, with its team, latest progress, next key milestone, and when each report was last updated.

## Where to find it

- **Projects & Handover → Project list**.
- **Reports & Dashboards → All reports → Project list**.
- **RASA:** ask *"Show me the project list"*. Name a region, sector or status in the question to narrow it, for example *"project list for the Eastern region"*.

## What it shows

| Group | Columns |
|---|---|
| Project | Tender no, PE number, project (short name), status, region, sector |
| Team | Project manager, scheduling engineer(s), costing engineer(s) |
| Latest progress | Planned %, actual %, variance, SPI, where the progress comes from, forecast finish |
| Key milestone | Next key milestone not yet achieved, its planned date, forecast (or actual) date and status |
| Reporting status | Last daily report and days since; last weekly report, last monthly report and last monthly cost report, each with its release date |

**Where the figures come from:**
- **PE number:** from the Tender register; the project code where none is held.
- **Progress:** the same as the project-wise progress report. It uses the updated P6 schedule with internal weightage where one is loaded. Otherwise it uses earned value from the baseline and the daily reports.
- **Next key milestone:** the first contractual or intermediate milestone not yet achieved. When every milestone is achieved, the last one achieved is shown.
- **Last daily report:** the latest daily report submitted (drafts don't count).
- **Weekly, monthly and cost reports:** the latest released version of each.
- **Team:** the people with access to the project in Settings → Users and access.

Below the table are two small summaries: projects by status and projects by region.

## Filters

- **Region**, **sector** and **project status**, which can be combined.
- The status filter always offers every status: Pre-award, Active, On hold, Completed and Cancelled.
- The report says how many projects match, for example *"2 of 6 projects"*.
- It starts from the projects in your access and the scope chosen at the top.

## Downloads

- **Excel:** one sheet with every column.
- **PDF:** on an A3 landscape page, so the 24 columns can be read. A report can now choose its own PDF page size; the other reports stay on A4.

## Who sees it

Everyone who sees reports, for the projects in their access: executives, regional and portfolio managers, project managers, planning, costing and read-only users.

Site managers, site engineers and foremen don't get it by default. A super admin can add it for them in Settings → Role access.

## Checks

- **New suite:** `tests/project_list_demo.js`, 20 checks, all passing.
- **Suites re-run after the PDF change:** presentation reports, RASA, project import, baseline comparison and cash inflow. All pass.
