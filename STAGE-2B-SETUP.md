# Stage 2b: daily reports on the server (ProTrackAI v2.5)

This puts the following on your Supabase server, where the server checks every change:

- daily reports
- baseline activities
- costing
- invoices
- weekly progress
- the approval matrix
- people's roles and access

It takes about 30 minutes. Do it first on a **staging copy** (see `STAGING.md`) if you can. If you can't, do it at a quiet time, when nobody is entering reports.

**Do not** upload a new `config.js`. Keep the one already on GitHub; it holds your server key.

---

## Before you start: two checks in Supabase

Open supabase.com → your ProTrack project → **Table Editor**.

1. You should see the tables `invoices` and `approval_matrix`. If `invoices` is missing, run `schema-update-v2.sql` first. If `approval_matrix` is missing, run `schema-update-v3.sql` first. Both are in this package.
2. Write down roughly how many rows `projects` and `profiles` have. You will compare them later.

## Step 1: Update the database (5 minutes)

1. Supabase → **SQL Editor** → **New query**.
2. Open `schema-update-v4.sql` from this package in Notepad. Select all, copy, and paste it into the editor.
3. Press **Run**.
   - The expected result is **"Success. No rows returned"**.
   - Lines saying "already exists, skipping" are normal.
4. Check it worked. Open a new query, paste this and press Run:

   ```sql
   select count(*) as functions_installed from pg_proc
   where proname in ('dpr_save','dpr_act','team_directory','admin_save_person',
                     'import_invoices','apply_costing','import_baseline','export_project','migrate_dprs');
   ```

   Expect **9**.
5. Check that nothing was lost. In Table Editor, `projects` and `profiles` should show the same counts you wrote down.

The update only adds things. It deletes no table, column or row. Running it a second time is safe.

## Step 2: Make sure every person has access to their projects

On the server, people see only the projects they have access to. A person with no project access sees an empty app. Super admins and executives see everything.

1. Sign in to the site as super admin (Step 3 below), then go to **Settings → Users and access**.
2. Open each person and tick their projects. Press Save; this now saves on the server.
3. For a **new person**:
   1. Create their sign-in account in Supabase first: **Authentication → Users → Add user**. Enter the email and a password, and tick **Auto Confirm User**.
   2. Then go to **Settings → Users and access → Create user**, enter the same email, and choose their role and projects.

## Step 3: Upload the website (5 minutes)

1. Go to github.com → **asarsowkat/protrack-ai**.
2. Click **Add file → Upload files**.
3. Drag in `index.html` and `guide.html` from the `protrack-site` folder of this package. Do **not** drag `config.js`.
4. Click **Commit changes**.
5. Wait 1 to 2 minutes, open the site, and press **Ctrl + F5**.
6. Check the sign-in page:
   - It shows **Connected to the ProTrack server**.
   - There is **no** "Demo accounts" list.
7. Sign in with your super admin email. **Settings → System** should show **v2.5**.

## Step 4: Move what people entered in their browsers (super admin)

Before v2.5, reports, baselines, costing and invoices were saved in each person's browser. Version 2.5 sets them aside safely and lists them.

1. On **each computer where reports were entered**, sign in once with your email.
2. On **your** computer, go to **Settings → System → Browser data waiting for the server**.
   - If the data is on someone else's computer, ask them to sign in and press **Download browser backup**, then send you the file.
   - Load their file with **Load a browser backup**.
3. Press **Move to server** for each project, then confirm.
   - A safety backup downloads first.
4. Read the result:
   - Every step should show ✓.
   - Every reconciliation row should say **Match**.
   - Any report the server refused is listed with the reason. Fix it and press **Move again**; nothing is created twice.
5. Go to **Settings → Approval matrix** and set it again for every project. Assignments made in a browser before v2.5 do not carry over.
6. Press **Download server backup** and keep the file.

## Step 5: Test with your team (15 minutes)

| Who | Does | Expect |
|---|---|---|
| Foreman | New report → submit | Report shows **Submitted** |
| Foreman | Tries a second report for the same day | "This foreman already has a report for that date" |
| A site engineer **not** assigned to that foreman | Opens the report | No Review button |
| The assigned site engineer | Mark as reviewed | **Reviewed** |
| The assigned site manager | Approve | **Approved**; summary email sent if email is set up |
| Anyone | Opens the report on another computer | Same status and the same history, with names |
| Costing engineer | Uploads the costing file twice | Second time: "same file … nothing changed" |
| Super admin | Settings → System → Download server backup | A file downloads |

## If something goes wrong

| What you see | What to do |
|---|---|
| Amber bar: "server data could not be loaded" | Check the internet connection, then press **Try again**. If it persists, check that Step 1 ran. |
| "Could not find the function public.dpr_save" | Step 1 did not run, or ran on another project. Run `schema-update-v4.sql` again. |
| A person sees no projects | Give them project access (Step 2). |
| "No sign-in account exists for …" | Create the account in Supabase first (Step 2, new person). |
| "You are not the reviewer or approver assigned to this report" | Check **Settings → Approval matrix** for that project. |

**To undo** (keeps all data):

1. Run `schema-rollback-v4.sql` in the SQL Editor.
2. Upload the v2.4 `index.html` again.

Reports saved while on v2.5 stay in the database. The old app does not show their history.

## What is still in each browser (next stage)

These stay in each browser until the next stage:

- trade rates
- subcontractors and purchase orders
- revised and recovery baselines
- DCMA results
- role access
- email settings
- notifications

Until then, set them on one computer: the super admin's.
