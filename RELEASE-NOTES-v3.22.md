# ProTrackAI v3.22: Reporting status, and an executive report released only when every project is complete (October 2026)

**Home → Reporting status** shows, for a week or a month, which projects have released their reports and which have not. The executive report of that period stays **held** until every active project has released, so a partial portfolio is never reported.

## What is tracked
| Deliverable | Week | Month | Responsible | Holds the executive report |
|---|---|---|---|---|
| Internal report | ✓ | ✓ | planning engineers | always |
| Monthly cost report | | ✓ | costing engineers | yes (default) |
| Change order and claim log (the month's upload) | | ✓ | costing engineers | tracked (optional) |
| Budget supplement log (the month's upload) | | ✓ | costing engineers | tracked (optional) |
| Invoice register update (an upload after the month ends) | | ✓ | costing engineers | tracked (optional) |

For each project and deliverable:
- **status:** Released / Uploaded, Submitted, Draft, Returned, Not started / not uploaded
- **who** prepared it and who approved it, and the date
- **timing:** on time, late, or overdue against the **due date**

Due dates: day 7 of the next month for a month, and 2 days after the week ends for a week. The super admin changes both.

## The screen
- **Filters:** report (monthly / weekly), the period (the last 6 months and 8 weeks), region, show (every project, outstanding, overdue, complete), search.
- **The banner:** *released* or *held* for the period's executive report, with "n of N projects" and a progress bar.
- **KPIs:** projects reporting, complete (on time), outstanding, overdue, reminders sent.
- **By region:** the counts per region; tap to filter.
- **The table:** each project with its project manager, each deliverable, its executive report status (*Complete*, *Outstanding* with what is missing, or *Exempted* with the reason), the last reminder, and the actions.
- **Reminders sent** for the period.
- **Export to Excel.**

## Reminders
- **Who sends:** the super admin, the Head of Planning and Cost Control, regional and portfolio managers (projects in their access), and the section planning manager of the project's region.
- **Who receives:** the internal report goes to the project's planning engineers; the cost report, the logs and the invoice register go to its costing engineers. **The project manager is always included.**
- **How it arrives:** in the notifications and as an email. The email is listed in Settings → Email → Sent emails; in the demo it is not sent.
- **Options:** **Remind** one project, **Remind the selected**, or **Remind every overdue project**, with an optional note.
- **Limit:** once a day for the same deliverables.

## The executive report
- **While the period is held:** an executive, a regional or portfolio manager sees *Held*, with how many projects have released and which are outstanding, and no figures. The super admin and the Head see a preview, marked held.
- **Exemptions:** the super admin or the Head can **exempt** a project for a period (for example, a site closed for the week), with a reason. An exemption can be withdrawn.
- **When complete:** once every project is complete or exempted, the report opens for everyone, stating since when.

## Rules (super admin)
**Reporting rules**, at the bottom of the screen:
- the monthly due day (1–28) and the weekly due days (0–14)
- which deliverables are required before the executive report is released; the internal report is always required

## Demo
- **August (monthly):** complete, so the monthly executive report is released. Ras Tanura and Jazan have not updated their invoice registers; that is tracked, not required.
- **Week 38:** held at 4 of 6. Ras Tanura's report awaits approval and Jazan's is a draft.
- **Week 37:** held. Ras Tanura's report was returned and is overdue.

## Checks
`tests/reporting_status_demo.js` runs 28 checks. They cover:
- the deliverables, the due dates and the statuses
- the hold for an executive, the preview for the super admin, and opening when complete
- exemptions (reason, who, withdrawal)
- reminders: who sends, recipients, notification and email, once a day, the section planning manager's region
- the rules, the regional scope, and the Excel export

The presentation reports (16) still pass.

## Server
`schema-update-v29.sql` (STAGE-25-SETUP.md) adds:
- `rs_config`, `rs_exemptions` and `rs_reminders`
- `reporting_act`, with the same rights and the once-a-day rule

Undo: `schema-rollback-v29.sql`. The SQL has not been run on a database yet.
