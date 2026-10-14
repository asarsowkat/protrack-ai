# ProTrackAI v3.7.2: full-screen daily reports and project forms (October 2026)

Built from your request: "i want full screen window for create project, when we open daily reports for review and approval".

## What changed

### Daily reports open full screen
Any daily report you open now fills the screen instead of a half-width side panel. This covers reports opened by the site engineer to review, the site manager or project manager to approve, and anyone just reading one.

- The four figures (activities, crew entries, manhours, report index) sit in one row.
- On a wide screen the activities sit side by side, two to a row. Each one still shows its scope, executed up to yesterday, balance, plan for today, actual quantity, manhours and crew.
- **Your action** stays in view at the bottom while you scroll: the comment box and the Review, Approve, Return with comments and Reject buttons. You no longer need to scroll to the end of a long report to act on it.
- ✕ or Esc closes it as before. The review and approval timers work as before.

### Create project and Edit project open full screen
**Settings → Projects → Create project** and **Edit** now fill the screen. The fields spread across the width, so the project details, team, milestones, payment terms and baseline sections take less scrolling.

The other settings forms (people, trades, subcontractors, regions, cities, sectors) stay as a side panel.

### On a phone
Nothing changes: these windows already filled the phone screen. The figures show two to a row, and the action buttons stay at the bottom.

## Database
No database update.

## Verified
| Check | Result |
|---|---|
| `fullscreen_demo.py`: a report opened for approval (project manager) and for review (site engineer) fills the screen, its buttons stay in view, Create and Edit project fill the screen, other forms stay a side panel, closing restores the panel; desktop and phone | 21 of 21 |
| `e2e_server.py`: the app against the database, including review and approval of daily reports | 228 of 228 |
| All demo suites | same results as v3.7.1 |
