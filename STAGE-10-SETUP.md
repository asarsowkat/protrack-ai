# v3.4 setup: the project document rack

This takes about 10 minutes. **Do not** upload a new `config.js`.

## Step 1: Update the database and create the document store (3 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v13.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select (select count(*) from pg_proc where proname in ('doc_act','pt_doc_can','pt_doc_row')) + (select count(*) from storage.buckets where id='project-docs') + (select count(*) from pg_policies where schemaname='storage' and policyname like 'protrack_docs_%') as installed;
   ```

   Expect **6**: three functions, one storage bucket and two access rules.

**What the update does:**
- adds the tables for box files, documents and their history
- creates a **private** storage bucket called `project-docs`, with a limit of 50 MB a file
- sets who may read and add files

Nothing existing changes, and running it twice is safe. You can see the bucket afterwards in Supabase → **Storage**. Leave it private.

**Space:** the Supabase free plan holds 1 GB of files in total. Supabase → **Settings → Usage** shows how much is used.

## Step 2: Publish

Tell Claude "it showed 6". Claude merges the update, and **live.html** shows **v3.4** within about 2 minutes. Then press **Ctrl + F5**.

## Step 3: Try it on live.html (5 minutes)

| Who | Does | Expect |
|---|---|---|
| Anyone except foremen | **Projects & Handover → Project document rack**, or **Project overview → Documents** | Three rows of box files for the project |
| Planning engineer | Opens **BASELINE (P01)** → **Upload document**, chooses the approved XER, revision "Rev 01", status Approved | The file is listed with its size and history; the box shows "Rev 01" and "Baseline kept" |
| Planning engineer | Uploads this week's schedule into **CURRENT P6 (P02)** | The box shows the week; the baseline box is unchanged |
| Costing engineer | Uploads the Rev 0 budget into **REV 0 (K02)**, then **Open → Upload new revision** for Rev 1 | Both are listed; Rev 0 is marked as the original approved budget |
| A site engineer | Opens the rack | The Planning row only |
| You | **Arrange boxes** → **Add a box file**, move a box, rename or hide one in **Box settings** | The rack changes; the history keeps a record |

## If something goes wrong

| What you see | What to do |
|---|---|
| Amber box: "The document rack needs the v13 database update" | Step 1 has not run. Run `schema-update-v13.sql` |
| Step 1 stops with "must be owner of table objects" or "permission denied for table buckets" | Your Supabase project does not let the SQL Editor change Storage. Tell Claude: the two access rules can then be added in Supabase → Storage → Policies instead |
| "The file was not stored: … row-level security" | The person does not keep that row (for example a planning engineer in the Cost row). Intended |
| "The file is larger than 50 MB" | Split or compress the file, or keep it elsewhere |

**To undo:** run `schema-rollback-v13.sql`. It stops new uploads and box changes. Every box, document, file and history entry is kept and stays readable by the same people.
