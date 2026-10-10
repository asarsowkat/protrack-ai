# v3.1 setup: issue register and released executive summary

This takes about 10 minutes. **Do not** upload a new `config.js`.

## Step 1: Update the database (3 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v10.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select count(*) as installed from pg_proc where proname in ('issue_act','issue_import','pt_issue_snapshot','pt_issue_apply');
   ```

   Expect **4**.

The update only adds the issue register tables and functions, and one column on releases for the issues saved at approval. Running it twice is safe.

## Step 2: Publish

Tell Claude "it showed 4". Claude merges the update, and **live.html** shows **v3.1** within about 2 minutes. Then press **Ctrl + F5**.

The main address keeps showing sample data until go-live. The sample data includes issues for every sample project, so you can show the new screens there.

## Step 3: Try it on live.html (5 minutes)

| Who | Does | Expect |
|---|---|---|
| Planning or costing engineer | **Projects & Handover → Issue register → Add issue** for one of their projects | The issue gets the next number (ISS-001) |
| Planning or costing engineer | **Download template**, or choose your own issue log file, then **Save** | New issues added; rows already in the register (same project and description) are updated, not duplicated. Rows for projects that are not theirs are refused and listed |
| You | Tap a region or sector row; open an issue; **Mark reviewed** with a note | The register filters; the issue shows "reviewed" |
| Planning engineer, then you | Submit and approve a progress release | The project's open issues are saved with the release |
| Costing engineer | **Monthly cost report**: check **Billing to date** (filled in from the invoice register), then submit | Invoiced and collected appear in the executive summary once you approve |
| A project manager or executive | **Home → Executive report (released) → Summary**, then **Project view** | By region, by sector, critical projects, billing and collection, change order and claim status; and one project's full released picture |

**Your existing issue log:** an engineer can upload it for their own projects, or you can upload the whole file at once as Head. Project codes must match the PE numbers in ProTrackAI; rows for projects not in ProTrackAI are refused and listed, and the rest are saved.

## If something goes wrong

| What you see | What to do |
|---|---|
| Amber box: "The issue register needs the v10 database update" | Step 1 has not run. Run `schema-update-v10.sql` |
| "not one of your projects" on upload rows | Intended. Each engineer keeps their own projects; the Head can upload any |
| "This issue is closed; reopen it first" | Intended. Press **Reopen** and say why |
| Text such as "NA" in a date or priority column | Not refused: it is kept in Remarks, marked "(From upload: …)" |

**To undo:** run `schema-rollback-v10.sql`. It removes the issue functions and puts releases back as in v3.0. Every issue, its history and the issues saved with releases are kept.
