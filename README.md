# ProTrack — Construction Productivity Intelligence

Prototype web application: daily site reporting, productivity, earned value, EAC,
manpower forecasting, Primavera P6 import and export, contract billing, and an
assistant that answers questions from the project data.

**Live pages**

| File | What it is |
|---|---|
| `index.html` | The application |
| `guide.html` | User guide: every screen, every formula, FAQ |
| `roles.html` | Step by step by role: foreman, site engineer, project manager, planning engineer, costing engineer, executives, super admin |

Everything is self-contained. No build step, no server code, no npm install.
Fonts load from Google Fonts; the spreadsheet and PDF libraries load from a CDN
only when you export a report.

---

## Deploy

### GitHub Pages
1. Create a repository, for example `protrack`.
2. Upload these files to the repository root (keep `.nojekyll`).
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

### Vercel
Import the repository, framework preset **Other**, no build command, output
directory `.`. Add `protrack.com` under Settings → Domains when you are ready.

### Netlify
Drag the folder onto the Netlify dashboard, or connect the repository with no
build command and publish directory `.`.

---

## Demo accounts

Password for every account: `ProTrack@2026`

| Email | Role |
|---|---|
| `asarudeen@company.com` | Super Admin |
| `abhijit@company.com` | Super Admin |
| `khalid.alsolami@company.com` | Executive Manager |
| `hani.barakat@company.sa` | Portfolio Manager, Central |
| `nasser.alshammari@company.sa` | Regional Manager, Eastern and Southern |
| `nabil.haddad@company.sa` | Planning Engineer |
| `tariq.almutairi@company.sa` | Project Manager |
| `omar.hassan@company.sa` | Site Engineer |
| `imran.sheikh@company.sa` | Foreman |

Each account lands on the Executive summary, scoped to the projects it may see.

---

## Read this before real use

This is a **prototype**. All data lives in the browser's local storage on each
device. There is no server, no database and no real authentication: the sign-in
screen, the roles and the access rules are demonstrations of the intended
behaviour, not security.

Do not put real staff passwords, client contract values or commercially
sensitive schedules into it as a production system.

For production the following are needed:

- A backend with a real authentication service (Supabase Auth, Clerk or Auth0),
  ideally with Microsoft Entra ID single sign-on for office staff
- A database with per-user row-level security, so a site engineer's requests
  cannot return another region's data
- Server-side rate limiting, password hashing (bcrypt or Argon2), and secure
  session cookies over HTTPS
- File storage for photographs and attachments
- Backups, and an audit log held outside the browser

---

## Resetting the demo

Sign in and use **Reset demo data** at the bottom of the sidebar, or clear the
site data in the browser. Each browser holds its own copy, so a demo on one
laptop does not affect another.

---

## Notes for whoever builds the production version

- The prototype is a single HTML file by design, so it can be opened, emailed and
  demonstrated anywhere. The production build should keep the same screens and
  rules but split into components with the data model below.
- Core rules the system enforces, which should survive the rewrite:
  construction progress only from daily reports; engineering and procurement only
  from the weekly milestone update; price only from the P6 weighting resource;
  cost only from the costing file; dated trade and purchase order rates so past
  reports never restate; re-baselining moves the plan, never earned progress.
- `guide.html` section 15 lists every formula, and section 16 the guarantees.
