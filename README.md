# ProTrack — Construction Productivity Intelligence

Prototype web application: daily site reporting, productivity, earned value and EAC,
manpower planning and forecasting, Primavera P6 import and export, budget and
costing, contract billing, and an assistant that answers questions from the
project data.

**Pages**

| File | What it is |
|---|---|
| `index.html` | The application |
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

---

## Read this before real use

This is a **prototype**. All data lives in the browser's local storage on each
device. There is no server, no database and no real authentication: the sign-in
screen, roles and access rules demonstrate the intended behaviour, they are not
security.

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

## Resetting the demo

Sign in and use **Reset demo data** at the bottom of the sidebar, or clear the
site data in the browser. Each browser holds its own copy.
