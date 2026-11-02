# ProTrackAI v3.54: the Daily Productivity Report, and a preview of every report

Each daily report now produces a **Daily Productivity Report** in the company layout. It can be previewed while the report is prepared, reviewed and approved. Once approved, it goes by email to the people on the Approval email list. The weekly and monthly internal reports can also be previewed as a document before they are submitted.

## The Daily Productivity Report

The layout follows the approved sample:
- **Header:** the alfanar Projects logo with "Building a brighter tomorrow"; **DAILY PRODUCTIVITY REPORT**, "ProTrack AI enabled daily productivity report" and Plan | Track | Analyze | Deliver; the ProTrack logo with "Powered by ProTrack AI".
- **Report details:**
  - Initiator name (the foreman), project name, project number;
  - contract number, client, reporting discipline (the disciplines of the report's activities);
  - date, day and week, and weather.
- **Activity progress & productivity tracking,** one row per activity:
  - work location, activity name, UOM;
  - scope, completed up to yesterday, today's progress, cumulative to date and balance quantity;
  - manpower & productivity: planned MP (as per productivity), actual MP, average overtime hours per person, total normal hours and total overtime hours;
  - the productivity index, coloured by the guide.
- **Summary (totals)** and the **productivity index guide:** over 110% Excellent, 100–110% Good, 90–100% Acceptable, 80–90% Needs Improvement, under 80% Critical. The quantity totals add up when all activities share a unit; otherwise they say "Mixed units".
- **Remarks / comments, major constraints / issues and recovery actions / next steps.**
- **Site photos** (from v3.53).
- **Sign-off:**
  - prepared by (initiator), reviewed by and approved by, each with name and date;
  - each step taken shows "Signed in ProTrack";
  - a step not taken yet shows who it is waiting for.
- **Footer:** People | Projects | Progress, and "For the World. With the World."

**How the figures are worked out:**
- Completed up to yesterday includes other reports of the same day.
- Cumulative = up to yesterday + today.
- Balance = scope − cumulative.
- Planned MP = today's quantity ÷ planned rate ÷ 8 hours.
- Productivity index = earned manhours (quantity ÷ planned rate) ÷ manhours worked, normal and overtime. This is the index the app already uses.

### New fields on the daily report

**Report details** now has a **Weather** field, with suggestions such as Clear, Hot, Windy or Dust / sandstorm. **Evidence and remarks** now has **Major constraints / issues** and **Recovery actions / next steps** beside **Remarks / comments**. The report shows all three.

### Preview at every stage

- **Preparing:** **Preview report** beside Submit and Save draft shows the report as typed, with photos not yet saved, before anything is stored.
- **Reviewing and approving:** **Preview report** at the top of the daily report.
- Until the report is approved, a note says it is a preview and becomes final on approval.
- **Print or save as PDF** prints it on A4 landscape.

### Sent after approval

When a daily report is approved by the site manager, or the project manager, the approval email is now the Daily Productivity Report itself:
- It goes to the people set in **Settings → Approval email**: the roles chosen there, with access to the project.
- If the email is switched off there, nothing is sent.
- The email carries a link to open the report in ProTrack.
- Mail programs block pictures embedded in emails, so the logos are lettered and the site photos are counted, not shown.
- On the demo page, emails are prepared and listed under Settings → Email but not sent.

## Weekly and monthly reports: preview before submitting

Internal report → a week or a month → **Preview report**, beside Save draft and Submit. It shows the report as a document in the same style, from what is in the form at that moment, even if it is not saved:
- **Header and details:** project, number, sub project, contract number, client, region, period, data date and revision.
- **Progress summary:** planned, actual, variance, SPI, forecast finish, productivity and manpower, with internal and external progress.
- **Milestones:** TCC, PAC, FAC, internal TCC and the intermediate milestones.
- **Progress tables:** progress by phase, and engineering and procurement.
- **Site status:** manpower, energization, and areas of concern (monthly).
- **Report notes**, and any figures changed from ProTrack AI with their reasons.
- **Progress photos.**
- **Sign-off.**

The reviewer and approver can open the same preview, and so can anyone who opens a released report.

## Server

`supabase/schema-update-v55.sql` (STAGE-49-SETUP):
- three columns on `dprs`: `weather`, `issues_text` and `recovery_text`;
- `dpr_notes_set(p)`, kept by whoever may edit the report (the v54 rule);
- **media_features()** reports version 55.

The app saves these fields between saving the report and submitting it. Until v55 is installed, the three fields are greyed out on the server copy, with a note. Undo: `schema-rollback-v55.sql`.

## Checks

- `tests/report_preview_demo.js`: 17 checks in the demo.
- `supabase/tests/test_v55.cjs`: 18 checks in PGlite.
