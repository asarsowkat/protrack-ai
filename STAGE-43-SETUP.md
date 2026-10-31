# v3.46 setup: client report formats for Word reports

This takes about 2 minutes. **Do not** upload a new `config.js`. It needs v48 (client report formats, STAGE-42-SETUP). Try it on a staging copy first: this update has not yet been run on a database.

## Step 1: Update the database (1 minute)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `supabase/schema-update-v49.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select crf_features() ->> 'version' as version, crf_features() ->> 'word_formats' as word_formats;
   ```

   Expect **49** and **true**.

**What the update does:** a client report format can now hold:
- pages at two levels;
- portrait or landscape pages;
- the document revision record and invoices pages;
- the table heading colours, the header line and the page orientation.

## Step 2: Check it (1 minute)

1. Sign in as the super admin. In **Settings → Client report formats**, choose **Draft a format from a client's PowerPoint or Word report** and pick the client's monthly Word report. Check the pages (levels, sources, columns), set the customer and save.
2. Open a monthly client report of that customer → **Client format and export** → **Export** → **Word**. The Index fills its page numbers when Word asks to update the fields.

## To undo

Run `supabase/schema-rollback-v49.sql`. Formats with the new pages or fields can then no longer be saved; those already saved are kept.
