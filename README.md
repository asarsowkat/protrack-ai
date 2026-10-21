# ProTrack — Construction Productivity Intelligence

Prototype web application: daily site reporting, productivity, earned value and EAC,
manpower planning and forecasting, Primavera P6 import and export, budget and
costing, contract billing, and an assistant that answers questions from the
project data.

**Pages**

| File | What it is |
|---|---|
| `index.html` | The application |
| `demo.html` | The same application on sample data, for demonstrations (never connects to the server) |
| `guide.html` | User guide: every screen, every formula, FAQ |
| `roles.html` | Step by step by role: foreman, site engineer, project manager, planning engineer, costing engineer, executives, super admin |
| `404.html` | Not-found page |

Everything is self-contained: no build step, no server code, no npm install.
Fonts come from Google Fonts; the spreadsheet and PDF libraries load from a CDN
only when a report is exported.

---

## Deploy

### GitHub Pages
1. Create a repository, for example `protrack`.
2. Upload these files to the repository root, keeping `.nojekyll`.
3. Settings → Pages → Source: *Deploy from a branch*, branch `main`, folder `/ (root)`.
4. The site appears at `https://<your-account>.github.io/protrack/`.

```bash
git init
git add .
git commit -m "ProTrack prototype"
git branch -M main
git remote add origin https://github.com/<your-account>/protrack.git
git push -u origin main
```

Updating later: replace the file, then `git add . && git commit -m "update" && git push`.

### Vercel
Import the repository, framework preset **Other**, no build command, output
directory `.`. Add `protrack.com` under Settings → Domains when ready.

### Netlify
Drag the folder onto the dashboard, or connect the repository with no build
command and publish directory `.`.

---

## Demo accounts

These work on `demo.html` (the demo page next to the live site, sample data only,
never connected to the server) and in any copy **without** a server key in
`config.js`. On the live site they are switched off: everyone signs in with their
work email. `demo.html` is built from `index.html` with `tools/make_demo.py`; rebuild
it whenever `index.html` changes.

Password for every account: `ProTrack@2026`

| Email | Role |
|---|---|
| `asarudeen@company.com` | Super Admin |
| `abhijit@company.com` | Super Admin |
| `khalid.alsolami@company.com` | Executive Manager |
| `hani.barakat@company.sa` | Portfolio Manager, Central |
| `rashid.alomani@company.sa` | Portfolio Manager, Eastern |
| `nasser.alshammari@company.sa` | Regional Manager, Eastern and Southern |
| `nabil.haddad@company.sa` | Planning Engineer |
| `tariq.almutairi@company.sa` | Project Manager |
| `omar.hassan@company.sa` | Site Engineer |
| `imran.sheikh@company.sa` | Foreman |
| `lina.saleh@company.sa` | Read-only |

Everyone except the foreman and read-only users lands on the Executive summary,
scoped to the projects their account may see.

---

## Setting up a project inside the app

1. **Settings → Projects** — create the project shell: code (any format, such as
   `PE-329`), sector, region, city, dates, contract value, project type, team,
   milestones including TCC, PAC and FAC, and the payment terms.
2. **Baselines → Original baseline** — the planning engineer imports the P6 file
   (XER, XML or Excel). This creates the activities.
3. **Baselines → P6 labour resources mapped to trades** — map the schedule's
   resources to ProTrack trades, once per project.
4. **Baselines → Master Manpower Costing Sheet** — the costing engineer downloads the template,
   which arrives pre-filled with every activity ID, adds budget quantity, unit,
   unit rate, cost and manhours, and uploads it. The Master Manpower Costing Sheet never creates
   activities; it matches on activity ID.
5. **Settings → Trades and rates, and Subcontractors** — salaries with dated
   history, and one purchase order per project per vendor.

Then the site reports daily, the project manager approves, and the planning
engineer updates design and procurement weekly.

At import you choose **which WBS branches to monitor** and **which activity
classes to bring in**, so a schedule full of procurement and engineering lines
can be reduced to the construction, installation and testing activities the site
actually reports against.

Mistakes are recoverable: every original import keeps a snapshot, so
**Baselines → Imported baseline and history → Undo this import** puts the project
back, and **Remove imported activities** clears them all. Projects can be deleted
outright from Settings → Projects, from the Baselines page, or from inside the
project editor; the deletion cascades to activities, reports, baselines, costing
and purchase order rates.

---

## Read this before real use

This is a **prototype**. Without a server key, all data lives in the browser's
local storage on each device and the sign-in screen and roles only demonstrate the
intended behaviour.

With a server key (Supabase), sign-in is real, and from version 2.5 projects,
activities, daily reports, costing, invoices, weekly progress, people's access and
the approval matrix are held on the server, which checks every change with
row-level security and server functions. Some settings (rates, purchase orders,
revised baselines, DCMA, role access, email settings) still live in each browser;
see `guide.html` section 12.

Do not use it as a production system for real staff passwords, client contract
values or commercially sensitive schedules.

Production needs:

- A backend with a real authentication service (Supabase Auth, Clerk or Auth0),
  ideally with Microsoft Entra ID single sign-on for office staff
- A database with per-user row-level security, so one region's data cannot be
  returned to another region's user
- Server-side rate limiting, password hashing (bcrypt or Argon2) and secure
  session cookies over HTTPS
- File storage for photographs and attachments
- Backups, and an audit log held outside the browser

---

## Rules the system enforces, which should survive any rewrite

- Construction progress comes only from daily reports; engineering and
  procurement only from the weekly milestone update.
- **Price** comes only from the P6 weighting resource and drives invoicing;
  **cost, quantity and manhours** come only from the Master Manpower Costing Sheet and drive
  budget analysis. Each project names which file owns budget manhours.
- Trade rates and purchase order rates are dated, so a pay rise or a PO
  amendment never restates a report already filed.
- Re-baselining moves the plan, never earned progress. Original, revised and
  recovery baselines are kept side by side.
- Invoiceable value follows the contract: a cap on progress per phase, up to two
  milestone releases per phase, retention with a cap, and release at TCC and FAC.
- Nothing reaches a dashboard until it is submitted or approved, and every
  change is logged with a name and a time stamp.

`guide.html` section 15 lists every formula; section 16 lists these guarantees.

---

## Until go-live: sample data on the main address

- `index.html` (the main link) and `demo.html` show **sample data** in the visitor's browser and never connect to the server.
- `live.html` is the real app, connected to the ProTrack server, for the team. Password-reset and approval-email links that land on the main address are sent on to `live.html`.
- Build: `python3 tools/make_demo.py live.html demo.html` and copy `demo.html` to `index.html`.
- **At go-live:** copy `live.html` to `index.html` (keep `live.html` so links still work).

## Version 3.29

- Budget supplements by user field and category (Cost Control → Logs → Budget supplements): each WF-approved supplement has its version (MMM-YY), WF date, user field, category and unified category, WBS group, ID and description, and remarks; its amount goes to Supplement, Savings, VO Cost or VO Price, and the net value is their sum. One project or every project in scope, one version, filters by region, sector, project type, category, user field and unified category; add, change and remove on the screen or upload the Excel template. The super admin keeps the lists in Settings → Supplement lists. Server update v35 (STAGE-29-SETUP.md). New suite `tests/supplements_demo.js` (37 checks). See [RELEASE-NOTES-v3.29.md](RELEASE-NOTES-v3.29.md).

## Version 3.28.3

- Cost and billing figures only with the right to see them: without *See cost and billing figures* (site engineers and site managers by default, foremen always), the Full report pack holds only the reports the person may open, the EAC, Unit rate, Invoiceable value and Invoicing reports stay closed, other reports leave out BAC, CPI and contract value, and the Live summary, Dashboard, presentation, early warnings and daily report form show no cost figure. New suite `tests/money_view_demo.js` (28 checks). See [RELEASE-NOTES-v3.28.3.md](RELEASE-NOTES-v3.28.3.md).

## Version 3.28.2

- Demo page fix: Riyadh Metro's sample July cash-out version is taken on the v3.21 sample data, so it no longer counts the old other line and the cost report heads both; it is within budget (95.0%) instead of a Forecast Overrun of about 186%. A browser holding the old sample is updated once when the page opens. Server files: `schema-update-v18.sql` runs again (two functions were quoted with `$` instead of `$$`), and every rollback (v4 to v34) is safe to run even if its update was never applied: it then changes nothing and says so. Detail in [RELEASE-NOTES-v3.28.2.md](RELEASE-NOTES-v3.28.2.md).

## Version 3.28.1

- Project list: bid position (L1/L2), tender stage (awaiting NOA, NOA received, cancelled), NOA date, client and expected value, with a Tender stage filter; four SAMPLE tenders on the demo page. Fixes: a project reports from the first full period after its NOA, so a new award never re-opens a closed period; RASA's cash-inflow answer skips projects without a contract value. Detail in [RELEASE-NOTES-v3.28.1.md](RELEASE-NOTES-v3.28.1.md).

## Version 3.28

- New report **Project list** (Projects & Handover, and All reports): tender no, PE number, short name, status, region, sector, project manager, scheduling and costing engineers, latest progress, next key milestone, and the last daily, weekly, monthly and monthly cost report; filters by region, sector and status; Excel and A3 PDF; RASA answers "project list". Detail in [RELEASE-NOTES-v3.28.md](RELEASE-NOTES-v3.28.md).

## Version 3.27.1

- Progress by phase shows in monthly internal and client reports as in weekly ones: a version saved before v3.23 (as the sample monthly reports) has the table worked out from the updated schedule in force at the end of its period, labelled as such, and kept at approval. Detail in [RELEASE-NOTES-v3.27.1.md](RELEASE-NOTES-v3.27.1.md).

## Version 3.27

- RASA answers from every module that is live: BOQ Engine quantities, the text of the documents in the document rack (quoted with the page), the delay events register, the cash-out and cash-inflow forecasts, material tracking, purchase orders, contract values, intermediate milestones, progress by phase, E&P progress and reporting status, plus a "find" search across the live modules. Settings → Release strategy (super admin) puts each module in a go-live stage; RASA answers only from the live ones and names the stage of the others, and the menu can hide them. Documents have their text read in the browser at upload. Server: `schema-update-v34.sql` (STAGE-28-SETUP.md), not yet run on a database. Detail in [RELEASE-NOTES-v3.27.md](RELEASE-NOTES-v3.27.md).

## Version 3.26.1

- Module-by-module review after v3.19–v3.26: 84 logic gaps fixed across reporting, BOQ Engine, cost and commercial and the server updates; 8 left with a reason. Detail in [REVIEW-v3.26.1.md](REVIEW-v3.26.1.md) and [RELEASE-NOTES-v3.26.1.md](RELEASE-NOTES-v3.26.1.md). Server update files v24, v27–v30, v32 and v33 corrected in place (none run on a database yet). 19 acceptance suites, 411 checks, all passing.

## Version 3.26

- E&P progress moves inside every internal and client report (weekly and monthly) as a tab, read from the same updated P6 schedule the report uses (in force at the end of its period; client weightage for client reports): engineering and procurement totals and each activity's plan, actual, actual and forecast dates and slip. No separate E&P screen or upload. Saved with the report and frozen at approval; in the executive report and the client report Excel. Server: schema-update-v33.sql. See RELEASE-NOTES-v3.26.md

## Version 3.25.1

- BOQ Engine sample data on the demo page, labelled sample everywhere: an OHTL (Riyadh–Qassim 380 kV, Section 2: tower T-101 and T-105 foundations, access road AR-2) and a substation (Jubail 380 kV: transformer T1 foundation, cable trench CT-1, GIS building), with sample PDF drawings, specifications, assumptions, verified calculations, released estimates, a revision waiting for review and a hand-off. Fixes: inputs and wastage taken from a specification, requirement conflicts by what they apply to, access roads and earthing checked against the general drawing list. No server change. See RELEASE-NOTES-v3.25.1.md

## Version 3.25

- BOQ Engine works end to end: drawing register with every revision kept, PDF upload read in the background (title block, scale, units, classification and dimension proposals with confidence and evidence, confirmed by a person), review and measurement on the drawing (verify, correct with a reason, calibrate, measure), deterministic quantity calculations in exact decimals with sourced inputs, the drawing completeness check, specifications and assumptions, the Estimated BOQ with optional rates, review, approval and release with no self-approval, revision comparison, Excel export, dashboard and audit history. Never writes to budgets or cost data. OCR and a vision AI provider are not configured. Server: schema-update-v32.sql (STAGE-27-SETUP.md). See RELEASE-NOTES-v3.25.md and BOQ-ENGINE-HANDOVER.md

## Version 3.24

- BOQ Engine (AI-Powered Quantity Take-Off, Engineering Estimation & BOQ Generation), a module of its own in the menu right after Invoices & Cash Flow: the landing page (BOQ Engine Dashboard) with the twelve sections of the module, shown as planned until their specifications are confirmed. Seen by management, planning, costing and project managers; the super admin can change it in Settings → Role access. Server: schema-update-v31.sql (the screen). See RELEASE-NOTES-v3.24.md

## Version 3.23

- Internal and client reports: intermediate milestones besides the contractual ones (design completion, civil start, civil completion, ...), picked by the planning engineer from the P6 schedule's WBS elements (first start or last finish) or activities and milestones, as asked by the project manager or the client; baseline from the schedule's baseline dates, forecast and actual from the updated P6 schedule. Progress tab: every phase (general works to energization and close out) with plan and actual from the updated schedule, weighted by the internal weightage set at project start (internal report) or by the schedule's own weighting (client report); the site phases are compared with the daily reports. Energization is now a phase of its own. Server: schema-update-v30.sql (STAGE-26-SETUP.md). See RELEASE-NOTES-v3.23.md

## Version 3.22.2

- Executive report (released) by project status: active and on-hold projects are listed; a completed project only in the periods it released, then it drops out; pre-award and cancelled projects are not listed. An on-hold project shows its last released figures, labelled with their period, and never holds the report (Reporting status). No server change. See RELEASE-NOTES-v3.22.2.md

## Version 3.22.1

- The home page after signing in is Home → Executive report (released), for every role that has it in its menu. Site engineers and site managers still open the live summary, foremen their daily reports, read-only users the dashboard. Switching "Acting as" opens the same home page. No server change.

## Version 3.22

- Home → Reporting status: per week and month, each active project's internal report, monthly cost report, change order log, supplement log and invoice register update, with status, preparer, approver and on time / late / overdue against the due date. Reminders to the engineers and the project manager (super admin, Head, regional and portfolio managers, section planning manager). The executive report of a period is held until every project has released the required deliverables; exemptions with a reason. Server: schema-update-v29.sql (STAGE-25-SETUP.md). See RELEASE-NOTES-v3.22.md

## Version 3.21

- Cash-out forecast from the material POs (the PO numbers of Material tracking, with value, terms and milestones on the material tracking stages, paid on the P6 forecast dates), the subcontract POs and the monthly cost report by WBS head (EAC − actual of the heads without POs, spread to the P6 forecast TCC; contingency, reserve, PC and provisional sums excluded). Reconciliation bridge with Finance's monthly cash-out: payables, milestones due, retention, unexplained; EAC cross-check. Server: schema-update-v28.sql (STAGE-24-SETUP.md). See RELEASE-NOTES-v3.21.md

## Version 3.20

- Invoices & Cash Flow → Cash-out forecast: Finance cumulative actual cash-out (Excel import by the super admin or the Head Office cost control coordinator, column mapping, restatements kept), PO payment terms and milestones (percent or fixed, contractual days, retention, evidence, approval and baseline), other cash-out lines, monthly planned / actual / forecast, forecast at completion against the approved current budget of the released cost report, statuses, reconciliation, versions with a management review of overruns, scenarios, portfolio, Excel and PDF reports. Server: schema-update-v27.sql (STAGE-23-SETUP.md). See RELEASE-NOTES-v3.20.md

## Version 3.19.2

- Delay events register: Correspondence and letters on each event (letters, e-mails, notices, instructions, minutes; received, sent or internal; date, reference, subject; optional file), which can add their references to the register and date the notice of claim. Chronology (Excel) and EOT pack (ZIP with the numbered files) for the extension of time submission. Kept by the register's keepers; removing needs a reason and keeps the record. Server: schema-update-v26.sql (STAGE-22-SETUP.md). See RELEASE-NOTES-v3.19.2.md

## Version 3.19.1

- Delay events register: the company workbook's drop-down lists (claim identification, status, entitlement, liability, concurrency, mitigation, claim owner) in the window, the filters, the template's Lists sheet and the upload check; a value outside the lists is refused. The super admin adds, removes and reorders items in Settings → Delay register lists (status stays Ongoing / Closed). Server: schema-update-v25.sql (STAGE-21-SETUP.md). See RELEASE-NOTES-v3.19.1.md

## Version 3.19

- Claims & Variations → Delay events register: the company Delay Events Register (27 columns: claim contractual data, notice of claim, schedule impact, cost impact) per project, created and changed in the system or uploaded from Excel, downloaded in the same layout. Claim duration, notice days used, notice days vs time bar and days to the notice deadline are worked out. Planning engineers keep their own projects (new right delay.keep); everyone sees only the projects in their access. Server: schema-update-v24.sql (STAGE-20-SETUP.md). See RELEASE-NOTES-v3.19.md

## Version 3.18

- Presentations → Reports: the internal report, productivity details, client report, invoicing and cash flow, cost report and change order details, each with the parts you tick, for a month and one project or all in scope; as PowerPoint slides or an Excel workbook. See RELEASE-NOTES-v3.18.md

## Version 3.17

- Monthly cost report: gross margin for every budget column (tender and Rev-0 on the original contract value; revised Rev-0, current budget and EAC on the internal revised value; previous version on the previous month's). Emails when an internal report (monthly or weekly) or a monthly cost report is approved, to lists set by the super admin (and per region by the section planning manager for internal reports). See RELEASE-NOTES-v3.17.md

## Version 3.16

- Monthly invoicing on the cash-inflow forecast: planned invoice (original baseline), invoiceable (actual progress), submitted and approved (register) by month, with KPIs (months invoiced), a chart and a Monthly invoicing sheet in the Excel download. See RELEASE-NOTES-v3.16.md

## Version 3.15

- Invoice register with each invoice's phase and actual submission, approval and collection dates; invoicing status by phase. Cash-inflow forecast (Invoices & Cash Flow): a new project from the client baseline and the payment terms; a running project from the register (actuals and outstanding) with the balance of each phase on the latest updated schedule; payment period in the payment terms. See RELEASE-NOTES-v3.15.md

## Version 3.14

- Internal and client reports compare the actual progress with the baselines you tick: original, revised, recovery, and the baseline assigned in the updated schedule (the baseline project exported with the XER). Planned, variance, SPI and finish per baseline, frozen at approval. Monthly cost reports moved out of Internal Reporting (Cost Control → Monthly cost report). See RELEASE-NOTES-v3.14.md

## Version 3.13

- Import projects from Excel (Settings → Projects, super admin): 100+ projects in one sheet, one row per project, with a template, a Lists sheet, row checks, refused rows with reasons, existing projects left unchanged, team access, and a batch in the Import centre. See RELEASE-NOTES-v3.13.md

## Version 3.12

- Tender register: Register an L1 or L2 project opens as a full window and records our bid position (L1, or L2 when the client may still award us). The costing coordinator or a super admin records the NOA with its actual date; the finance WBS is released the same day to record the PBG cost. See RELEASE-NOTES-v3.12.md

## Version 3.11

- Internal and client contract value: the change order and claim log carries the client approved price and the price considered internally (full or partial) with its WF number and date, updated by the costing engineer on the screen or by upload. Internal reports, the executive report, the dashboards and the cost report margin use the internal revised contract value (original + considered internally); client reports use original + approved by the client only. Frozen with each approved report. See RELEASE-NOTES-v3.11.md

## Version 3.10

- Project Visual (Home): planned and actual progress on the project's own PDF drawings (site layout zones) and route (chainage sections, structures, work stages), or both; activity mapping with rules (AI suggestions on the demo page only) and approval; Live and Released (frozen with each approved internal report); PDF export. The P6 import now keeps total float. See RELEASE-NOTES-v3.10.md

## Version 3.9.1

- The Master Manpower Costing Sheet moves from Baselines to its own page under Cost Control, with Download new sample template, Download current existing data and Upload. See RELEASE-NOTES-v3.9.1.md

## Version 3.9

- Executive report (released): each person can show, hide and reorder its sections and tiles; the super admin sets the default for everyone.
- Material tracking on the Live summary (from the latest updated schedule) and on the Executive report (saved with each released internal report).
- Invoice register moves to Invoices & Cash Flow and subcontract purchase orders to Materials & Procurement, out of Baselines. See RELEASE-NOTES-v3.9.md

## Version 3.8.4

- Engineering and procurement progress from the weekly updated P6 schedule; the separate E&P Excel upload is retired. See RELEASE-NOTES-v3.8.4.md

## Version 3.8.3

- Phones and tablets: a Menu button in the bottom bar opens the full menu, as on a laptop (Planning & Scheduling, Cost Control, Materials & Procurement, Administration...). See RELEASE-NOTES-v3.8.3.md

## Version 3.8.2

- Material tracking: History on a material opens full screen, with the nine milestones, the activities and every change. See RELEASE-NOTES-v3.8.2.md

## Version 3.8.1

- Material tracking needs no extra upload: set up from the original baseline import (or, for projects already loaded, the next weekly updated schedule); actual and forecast from the weekly updated schedule. See RELEASE-NOTES-v3.8.1.md

## Version 3.8

- **Material tracking** (Materials & Procurement): set up from the approved baseline XER (Material Name and Unified Activity Name activity codes, WBS branches, milestone mapping, monitored materials); one row per material with the current stage, nine milestones (PR Creation to Civil Readiness) and Delivery Status from the latest updated schedule; KPIs, charts, filters, search, sorting, Excel and PDF; PO number, supplier and remarks kept by hand with a history and never overwritten (`schema-update-v17.sql`)
- New right "Keep material tracking" and new screen "Material tracking" in Roles and rights
- See RELEASE-NOTES-v3.8.md and STAGE-14-SETUP.md

## Version 3.7.2

- Daily reports (review, approval, reading) and Create / Edit project open full screen; the review and approval buttons stay in view at the bottom. See RELEASE-NOTES-v3.7.2.md

## Version 3.7.1

- The costing file is renamed **Master Manpower Costing Sheet** throughout the app, the template download and the guides; saved values and the database are unchanged. See RELEASE-NOTES-v3.7.1.md

## Version 3.7

- **Roles and rights** (Settings, super admin only): 17 rights in four groups given or removed per role, 21 menu screens shown or hidden per role, custom roles made from a built-in role, people with their own exceptions, and a history that cannot be changed (`schema-update-v16.sql`)
- **Access for any role**: whole regions, chosen projects or All projects (which includes projects added later), for every role except super admin and executive manager
- **Rights for one person**: As the role, Allow or Remove, per right; the person's choice wins over the role
- Every permission check on the server reads the same rights (`pt_right`); super admins always keep every right, foremen never see cost and billing figures
- Nothing changes until the super admin changes something: checked person by person for all 48 demo people against v3.6
- See RELEASE-NOTES-v3.7.md and STAGE-13-SETUP.md

## Version 3.6

- Internal weightage by phase (general works, design, material, construction, installation, testing & commissioning, close out), set per project by the planning engineer, with history (`schema-update-v15.sql`)
- Updated P6 schedule upload (XER): data date, % complete, milestones; phase from the main WBS or a P6 activity code; client and internal planned/actual % worked out on the server; updates kept for good
- Every ProTrackAI progress figure uses the internal weightage of the latest updated schedule; invoiceable uses the client weightage with the schedule's % complete
- Progress releases renamed Internal Reporting; new Client Reporting (weekly/monthly, Excel and print); differences from the updated schedule are validated by the regional planning section manager
- See RELEASE-NOTES-v3.6.md and STAGE-12-SETUP.md

## Version 3.5

- Progress release dashboard: weekly and monthly progress releases open full screen with tabs (Overview, Milestones, Progress, Manpower, Energization, Release notes, Approval), nine KPI cards with traffic lights and trends, contractual/revised/forecast TCC, PAC and FAC with worked-out delays, external progress beside the internal headline, manpower and energization (`schema-update-v14.sql`)
- Each region's planning section manager approves its progress releases; a super admin can add a project manager review step; cost reports stay with the Head
- Executive report project view shows the released dashboard figures; a TCC more than 30 days late marks a project critical
- See RELEASE-NOTES-v3.5.md and STAGE-11-SETUP.md

## Version 3.4

- Project document rack: three rows of box files per project (Contract & Commercial, Planning & Scheduling, Cost Control & Costing), files in a private Supabase Storage bucket, revisions that never overwrite, statuses, history, previews, live figures, custom boxes (`schema-update-v13.sql`)
- See RELEASE-NOTES-v3.4.md and STAGE-10-SETUP.md

## Version 3.3

- Monthly cost report in the company format: one row per WBS head with tender, Rev-0, revised Rev-0, previous version, current budget, actual, commitment, balance, ETC, EAC, supplement/saving and justification; TCC, POC, contract value and gross margin (`schema-update-v12.sql`)
- Fill from the company Excel sheet; export in the same layout; executive report project view shows the table
- See RELEASE-NOTES-v3.3.md and STAGE-9-SETUP.md

## Version 3.2

- New report: choosing an activity shows its scope, executed up to yesterday, balance, balance duration and plan for today (balance ÷ balance duration); the actual quantity is entered
- A quantity beyond the scope is accepted; the reviewer must justify it, the justification is kept, and an unjustified quantity cannot be approved (`schema-update-v11.sql`)
- Server backup now also holds releases, logs, issues and justifications
- See RELEASE-NOTES-v3.2.md and STAGE-8-SETUP.md

## Version 3.1

- Executive report Summary (by region, by sector, critical projects, billing and collection, change order and claim status) and Project view, from released versions only
- Issue register with the company issue log columns: planning and costing engineers keep their own projects, the Head reviews by region or sector, Excel upload and export, every change kept; open issues saved with each approved progress release (`schema-update-v10.sql`)
- Billing to date in the monthly cost report, filled in from the invoice register
- See RELEASE-NOTES-v3.1.md and STAGE-7-SETUP.md

## Version 3.0

- Released reporting: weekly and monthly progress releases by planning, monthly cost reports by costing (actual, commitments, approved budget, EAC, VAC), approved by the Head of Planning and Cost Control; revisions instead of edits (`schema-update-v9.sql`)
- Executive report built only from released versions, by month or week
- Change order and claim log and budget supplement log, uploaded monthly per project, all months kept
- See RELEASE-NOTES-v3.0.md and STAGE-6-SETUP.md

## Version 2.9

- Governed RASA answers: sources and data date under every answer and insight, "No evidence" instead of guesses, untracked figures named
- RASA answers only about projects and figures the person can open; the server no longer sends invoice and costing rows to site roles (`schema-update-v8.sql`)
- No project data leaves ProTrackAI: the language model is off on the server, labelled on the demo page
- See RELEASE-NOTES-v2.9.md and STAGE-5-SETUP.md

## Version 2.8

- Tender register: L1 projects recorded from Tender's list with TE number, client, location and expected value; ProTrackAI proposes the PE number, refuses duplicates, and releases a cancelled project's number for the next L1 project (`schema-update-v7.sql`)
- Designations: Head of Planning and Cost Control (approves stages 1 to 5) and costing coordinator (registers projects, records stages 1 to 4)
- Stages 1 to 5 follow the Tender-to-SAP process; stage 4 due 7 days after contract signing
- See RELEASE-NOTES-v2.8.md and STAGE-4B-SETUP.md

## Version 2.7

- Governed 12-stage project lifecycle: owner, due date, required deliverables with evidence, submit and approve (no self-approval), append-only history (`schema-update-v6.sql`)
- Actions and approvals register; Planning dashboard; Cost Control dashboard with source reconciliation and untracked items labelled, never estimated
- See RELEASE-NOTES-v2.7.md and STAGE-4-SETUP.md

## Version 2.6

- Import centre: every upload is a numbered batch with file fingerprint, counts, totals, reconciliation, acknowledgement, failures and retries
- Checks before saving (file type and size, project, currency, dates, numbers, duplicates); exception report as CSV
- Refused rows must be acknowledged by name; all-or-nothing saving, weekly progress included (`schema-update-v5.sql`)
- See RELEASE-NOTES-v2.6.md and STAGE-3-SETUP.md

## Version 2.5

- Daily reports, activities, costing, invoices, weekly progress, approval matrix and
  people's access on the server, every change checked there (`schema-update-v4.sql`)
- Tamper-evident report history; imports all-or-nothing and safe to repeat
- Backup and restore, and a guided move of browser data to the server with reconciliation
- Demo accounts switched off on server sites; `demo.html` keeps a sample-data demo next to the live site
- See RELEASE-NOTES-v2.5.md and STAGE-2B-SETUP.md

## Version 2.4

- Demo or live date: Settings → System; `DATE_MODE` in config.js locks it
- A 0% payment cap now means 0% (blank = 100% / no cap); older saved terms unchanged
- Formula reference for Finance; 158 automated checks in `tests/`

## Version 2.3

- **Every business domain in the menu**, grouped as in the target design: Projects &
  Handover, Planning & Scheduling, Cost Control, Daily Reports, Materials & Procurement,
  Claims & Variations, Invoices & Cash Flow, Reports & Dashboards, RASA, Imports &
  Integrations, Administration. Working screens open as before; items not built yet
  are greyed out with a **Planned** tag and cannot be opened.
- **Project overview** page: lifecycle stages, key figures, contract and financial
  summary, schedule by phase, cost trend, critical items and RASA, from real data only.
- Regression suite in `tests/` (75 checks).

## Version 2.2

- **RASA**, Real-time Artificial Smart Assistant, replaces the old assistant face:
  ten expression states from the RASA artwork, blinking, breathing and gestures
- RASA **points at the live dashboard**: highlights the KPI tile, labels it and
  draws a line to it, moving aside if it would hide the tile
- **Proactive insights**, role-aware: approvals waiting, SPI and CPI below 0.95,
  procurement delays, weakest activity, reporting gaps, un-invoiced work
- Ten quick actions, a larger side-by-side mode, full-screen on phones
- Voice-ready structure: `RASA.adapters` for text-to-speech, speech recognition,
  a language model and an animated avatar

## Version 2.1

- **Site Manager** role; approval chain foreman → site engineer → site manager
- **Approval matrix** set per project by the super admin (Settings → Approval matrix)
- **Timers** on preparing, reviewing and approving each report; new report
  *Time spent preparing, reviewing and approving daily reports*
- **Approval email** with a summary and a link (needs the Supabase mail function)
- **Role access**: super admin sets the reports and executive view for site roles;
  site roles never see cost
- Foremen limited to daily reports, new report and their own performance
- Project managers reach costing, invoices and purchase orders for their projects
- Manpower histogram rebuilt: 8.3 s to 0.34 s

## Recent changes in this build

- **Costing engineer role**, who owns the costing file, the invoice register and
  **subcontractor purchase orders** for his projects, on the Baselines page
- **Performance**: project managers (approvals, SPI, CPI, cost variance, OT,
  under-billing, collection pending, and **monthly invoicing** until 80% of the
  contract), planning engineers (**DCMA 14-point check** and weekly update
  compliance), costing engineers (upload quality and timeliness), and
  **reporting compliance** by project with **Notify team**
- **Customisable executive summary**: 18 tiles, breakdown by region, sector,
  city or project, chosen columns, per person
- Subcontractor entry: one company and one quantity, several trades underneath
- User guide version 2 with every performance formula written out

## Earlier

- **Sign-in against your Supabase server** when `config.js` carries the URL and
  anon key; demo accounts still work for people you show the prototype to
- **Projects live on the server** once signed in that way, so everyone with an
  account sees the same list
- **Invoice register**: the costing engineer uploads invoice number, amount,
  submitted, approved and collected each week, including the advance, and the
  executive summary shows invoiceable, invoiced, approved, collected,
  under-billed, short of approval and outstanding collection
- **Presentation builder**: pick the project and tick the slides, download a
  PowerPoint with cover, KPIs, charts, tables and a closing slide
- **Invoicing and collection** report, alongside the rest

## Earlier in this build

- In-app confirmation dialogs, because sandboxed frames block the browser's own
  `confirm()`; delete, undo and reset now work wherever the app is hosted
- Delete a project from three places, with a full cascade and a change-log entry
- Undo an import, remove imported activities, or delete a revised or recovery set
- Pick WBS branches and activity classes at import; the class list shows live
  counts from the branches ticked
- Resource-aware P6 import: labour hours, material quantities with their units,
  price weighting resource, and the trade mix per activity
- Costing file for budget quantity, unit, rate, cost and manhours, joined on
  activity ID, with a per-project setting for which file owns budget manhours
- Any unit of measure, any project code format
- Billing by phase with up to two milestone releases, plus advance recovery
- Trade-wise manpower histogram with a forecast at current productivity
- Quantity reconciliation, unit rate analysis, budget manhour reconciliation and
  invoiceable value reports
- Executive summary as the landing page, and an interactive ProTrack AI avatar
  that answers from any report

## Resetting the demo

Sign in and use **Reset demo data** at the bottom of the sidebar, or clear the
site data in the browser. Each browser holds its own copy.
