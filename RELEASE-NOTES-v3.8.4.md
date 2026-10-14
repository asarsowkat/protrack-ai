# ProTrackAI v3.8.4: engineering and procurement progress from the updated P6 schedule (October 2026)

Built from your request: "As we are getting updated xer in weekly basis, 'weekly E&P update' option is not required; protrack can take the progress details from the updated p6 schedule".

## What changed
The separate **Weekly E&P update** (an Excel template filled with milestones and dates) is retired. Engineering and procurement progress now comes from the updated P6 schedule the planning engineer already uploads every week (**Planning & Scheduling → Baselines and P6 import → Updated schedule**).

| For each engineering or procurement activity | Comes from |
|---|---|
| % complete | the updated schedule's % complete |
| Status | Not started, In progress or Completed, from that % |
| Actual start and finish | the updated schedule |
| Forecast finish, slip against the baseline | the updated schedule's finish |
| Data date | the updated schedule's data date |

These figures feed:
- the engineering and procurement cards
- earned value
- the design and procurement figures in Internal Reporting
- late-item alerts
- the project overview
- RASA

### The E&P progress page
**Planning & Scheduling → E&P progress** (was "Weekly E&P update") is now read only. It has no template and no upload. It shows:
- each project's updated schedule and its data date, marked **stale** after 8 days
- the engineering and procurement cards
- the status of every activity
- the list of updated schedules loaded

A button takes you to Baselines and P6 import to load the next one.

### Other changes
- **Import centre:** the "Weekly progress" upload is gone.
- **Reporting compliance** (Performance) checks the **updated schedule**. A project with a baseline and no updated schedule within 9 days is flagged, for example "Updated schedule 12 days old".
- **Planning engineers' score** counts the weeks with an updated schedule over the last 12 weeks.
- **Planning dashboard:** the "Weekly update (P6)" column and "Updated schedules stale" now cover every project with a baseline.
- **Lifecycle stage 7** and the project overview check use "Weekly updated schedule".
- **Late alert:** saving an updated schedule warns when a design or procurement item is forecast more than 7 days late.
- **RASA** names the weekly updated P6 schedule as its source for design and procurement. It now points material questions to Material tracking.

### Projects without an updated schedule yet
These keep the engineering and procurement progress loaded before with the Excel update, until their first updated schedule is uploaded. The E&P progress page says so for each one. Construction activities are unchanged: until an updated schedule is loaded, construction progress still comes from the daily reports.

## Database
No database update. The updated schedules are already on the server (v15). Earlier E&P updates stay in the history.

## Verified
| Check | Result |
|---|---|
| `ep_sched_demo.py`: progress, status and forecast from the updated schedule; the next schedule moves it with nothing else to upload; projects without one keep earlier figures; no upload on the page or in the import centre; compliance, dashboard, lifecycle and RASA | 24 of 24, app and sample-data page |
| All earlier demo suites (updated for the retired upload) | same results as v3.8.3 |
| `e2e_server.py`: the app against the database, including E&P progress read from an updated schedule on the server | 237 of 237 |
