# v3.44 setup: logos, customers and report photos and videos

This takes about 4 minutes. **Do not** upload a new `config.js`. It needs v16 (Roles and rights) and the report release updates. Try it on a staging copy first: this update has not yet been run on a database.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `supabase/schema-update-v47.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select media_features() ->> 'version' as version, (select count(*) from storage.buckets where id = 'report-media') as bucket, (select count(*) from pg_policies where policyname like 'protrack_rm_%') as file_rules;
   ```

   Expect **47**, **1** and **3**.

**What the update does:**
- **Settings → Logos and customers** (super admin):
  - the company logo and name, in `pt_branding`;
  - the customers with their logos, in `customers`;
  - renaming a customer renames the client of its projects;
  - a customer that is a client cannot be deleted.
- **Photos & videos** in the internal and client reports:
  - the files go in the private bucket `report-media` (100 MB a file), and their records in `report_media`;
  - they are read by those who see the project;
  - they are added, captioned and deleted by those who prepare the report, while it is not approved.

## Step 2: Check it (2 minutes)

1. Sign in as the super admin and reload the page. In **Settings → Logos and customers**, upload the official company logo, then create a customer with its logo.
2. Open **Cost Control → MER – Monthly Executive Report → Project wise** for a project of that customer. Both logos show at the top right. Press **This project to PDF**: one A4 page.
3. Sign in as a planning engineer. Open a draft monthly internal report → **Photos & videos** and add a photo. Give it a caption.
4. In the client report of the same period, press **Copy from the internal report**, then **Print or save as PDF**: the photo prints with its caption.

## To undo

Run `supabase/schema-rollback-v47.sql`. The exports then print the company name without a logo and the reports show no photos. The tables, the bucket and the files are kept; running v47 again brings them back.
