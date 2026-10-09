# ProTrackAI v2.5 — Phase 2 foundation (October 2026)

## What changed

**Server mode** applies when `config.js` holds the Supabase key and the person signs in with their work email.

### On the server, and checked there

These now live on the server: projects, people and their access, regions, sectors, cities, baseline activities, daily reports, costing, invoices, weekly progress and the approval matrix.

- **Daily reports** are saved, submitted, reviewed, returned, rejected and approved only through server functions (`dpr_save`, `dpr_act`). These check the person's role, their access to the project, and the approval matrix for that project. Writing to the tables directly is refused. A browser that shows a hidden button, or calls the server directly, gets "You are not the reviewer or approver assigned to this report".
- **A foreman** always reports under his own name and can edit only his own drafts. Once submitted, only the assigned site engineer or the project manager can edit the report.
- **Approved reports** cannot be changed or deleted by anyone, including from the database console. A project with approved reports cannot be deleted.
- **Report history** is append-only. Each entry carries a fingerprint (SHA-256) of the entry before it, so an altered or removed entry is detected (`dpr_audit_verify`). The change log is append-only too, and nobody can write an entry in someone else's name.
- **Imports** (costing file, invoice register, baseline) run in one transaction. Each is recorded with a fingerprint of its content. Bad rows are refused and listed, never half-applied. Loading the same file again changes nothing, and reloading an older register after a newer one does apply it.
- **Input checks on the server:**
  - one report per foreman per day
  - no future dates
  - the same activity once per report
  - every activity must belong to the project
  - no negative quantities
  - no more than 24 hours a day per worker
- **People:** the super admin saves a person's role and project access on the server (`admin_save_person`). The sign-in account itself is created in Supabase.
- **Team directory:** the app reads names and emails only for colleagues on shared projects, plus super admins and executives.

### Backup, restore, and moving to the server

These are in Settings → System.

- **Download server backup:** every project you can see, with its activities, reports and full history, invoices, approval matrix and import records.
- **Download browser backup** and **Restore** (demo mode):
  - A preview compares the two copies before anything changes.
  - A backup of the current data downloads first.
  - On a server site, a browser backup is never written over server data.
- **Move to server:** when someone signs in to v2.5, anything their browser held from before (reports, activities, costing, invoices) is set aside untouched. The super admin then moves it project by project:
  - A safety backup downloads first.
  - Items the server already has are skipped, never overwritten.
  - Refused items are listed with the reason.
  - A reconciliation table compares counts and totals between browser and server.
  - Running it again creates nothing twice.

### Demo accounts are off on server sites

When `config.js` has a key:

- The demo account list is gone.
- Demo passwords no longer open the app.
- A username that is not an email is refused.
- "Reset demo data" is hidden.
- A browser session saved in demo mode is not restored.

### Errors are shown, never hidden

If server data cannot be loaded, an amber bar says so and offers **Try again**. Every refusal from the server is shown with its reason. Nothing falls back to saving only in the browser.

## Behaviour changes to know about

- A person with no project access sees an empty app. Give access in Settings → Users and access.
- The approval matrix must be set again on the server. Assignments made in a browser before v2.5 referred to browser accounts.
- On the server, **Undo import** and **Remove baseline** are not available, so report history always keeps its baseline. To correct a baseline, import the right file; activities are matched by ID.
- The **Reset password** button now emails a real reset link on server sites.

## Still in each browser (next stage)

- trade rates
- subcontractors and purchase orders
- revised and recovery baselines
- DCMA results
- role access settings
- email settings
- notifications
- executive layout preferences

## Database: `schema-update-v4.sql`

- **Additive only:**
  - new columns on `dprs`, `dpr_lines` and `dpr_audit`
  - new table `import_batches`
  - new functions and triggers
- **Policies removed:** the four direct-write policies on daily reports and their history (`d_insert`, `d_update`, `dl_write`, `da_write`). Writes now go through the functions.
- **No data deleted or rewritten.** Existing history entries are sealed into the fingerprint chain once.
- **Safe to run twice.**
- **Reversible:** `schema-rollback-v4.sql` removes the functions and triggers and restores the v3 rules. It keeps all data, including reports saved under v2.5.

## Verified

Results files are in `tests/`.

| Suite | Checks | Result | What it runs against |
|---|---|---|---|
| Database (`test_v4.py`) | 125 | 125 pass | Real PostgreSQL 16 with the real schema. Each person signs in as Supabase's `authenticated` role, with row level security on. Covers attacks that must fail, the normal approval path, imports, migration, people management, rollback and re-apply. |
| Server mode, end to end (`e2e_server.py`) | 55 | 55 pass | The real app in Chromium, talking to that database through a stand-in for Supabase's web layer. Every allow/refuse decision is the database's own. |
| Regression, demo date | 77 | 77 pass, 2 skipped | Demo data |
| Regression, live date | 77 | 77 pass, 2 skipped | Demo data |
| Functional suites | 58 | 58 pass | Demo data |
| Formula reference | 23 | 23 pass | Hand-calculated reference project |
| Backup and restore, demo mode | 10 | 10 pass | Demo data |

The 2 skipped regression checks are exports, which need CDN libraries this environment cannot reach, and PMXML import, which has no sample file.

**Bug found and fixed by these tests:** when a foreman had no site engineer assigned, the server treated the missing assignment as "allowed", so any site engineer could review that report. The server now treats a missing assignment as "no".

## Not verified here

- **Supabase itself:** its sign-in service, its REST layer and the email function. These were replaced by a local stand-in. Run the Step 5 checks in `STAGE-2B-SETUP.md` on staging, then live, after installing.
- **Your live Supabase project:** nothing was run against it.
- **Subresource integrity hashes for the CDN libraries:** not added. They cannot be computed here without network access, and made-up hashes would break the site. To do on a machine with internet access.
- **Pushing to GitHub:** this release is committed locally on branch `release/v2.5`. Pushing still needs the Claude GitHub app installed on the repository; until then, upload the files by hand.
