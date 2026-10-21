# v3.27 setup: release strategy and RASA document text on the server

This takes about 5 minutes. **Do not** upload a new `config.js`. It needs the v13 update (STAGE-10-SETUP, the Project document rack). Try this on a staging copy first: this update has not yet been run on a database.

## Step 1: Update the database (3 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v34.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select golive_features(), (select cfg ->> 'current' from golive_cfg) as live_up_to;
   ```

   Expect `{"doc_text": true, "release_strategy": true}` and **4**: every module live, as before the update.

**What the update does:**
- **Release strategy:** one row with the stages, the stage of each module and the stage live up to. Everyone signed in reads it; only a super admin changes it (`golive_set`, with the same checks as the app). Every change is kept in an audit table that cannot be changed.
- **Document text:** the text of each document, page by page, read in the browser at upload. It is read with the rights of the document itself: whoever cannot read a document cannot read its text. Only the people who keep the box, or a super admin, store it (`doc_text_set`). RASA searches it with `doc_text_search`, on the documents the person can read only.
- No project data is sent to any outside AI service: the search runs in the database.

## Step 2: Set the plan (2 minutes, super admin)

1. Sign in as the super admin and reload the page.
2. **Settings → Release strategy**:
   - name the stages and give their planned go-live dates;
   - put each module in its stage;
   - choose **Live up to** (for example, Stage 1 at the first go-live);
   - tick **Hide the modules not live yet from the menu** if people should not see them yet;
   - press **Save the release strategy**.
3. Under **Document text for RASA**, press **Read their text now** once. This reads the documents uploaded before this update. New uploads are read at once.

## Step 3: Check (1 minute)

- As a project manager, open RASA and ask about a module that is not live yet. RASA should say it goes live in its stage.
- Ask **"What does the contract say about retention?"** on a project whose contract is in the document rack. RASA should quote the clause with the page.
- A scanned PDF says *no text layer*. RASA cannot quote it until a text version is uploaded.

## To undo

Run `schema-rollback-v34.sql`. The app then counts every module as live and RASA no longer quotes documents. The tables are kept, so running v34 again brings everything back.
