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
4. **Baselines → Costing file** — the costing engineer downloads the template,
   which arrives pre-filled with every activity ID, adds budget quantity, unit,
   unit rate, cost and manhours, and uploads it. The costing file never creates
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
  **cost, quantity and manhours** come only from the costing file and drive
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
