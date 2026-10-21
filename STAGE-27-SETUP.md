# v3.24 and v3.25 setup: BOQ Engine on the server

This takes about 10 minutes. **Do not** upload a new `config.js`. Run the v16 update first (STAGE-13-SETUP, roles and rights). Try this on a staging copy first: these updates have not yet been run on a database.

## Step 1: Update the database (3 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v31.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, do the same with `schema-update-v32.sql`.
4. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select (select count(*) from pg_tables where tablename like 'boq\_%') + (select count(*) from pg_proc where proname in ('boq_save','pt_boq','pt_boq_file_can')) + (select count(*) from unnest(pt_rights()) r where r like 'boq.%') + (select count(*) from storage.buckets where id = 'boq-drawings') + (case when 'boq' = any(pt_screens()) then 1 else 0 end) as installed;
   ```

   Expect **21**: 11 tables, 3 functions, 5 rights, the bucket and the screen.

**What the updates do:**
- **v31:** BOQ Engine becomes a screen in Settings → Role access.
- **v32 rights:** five new rights: upload, estimate, review, approve and rate. The Head of Planning and Cost Control reviews and approves by position.
- **v32 tables:** one table per record type, readable by people who see the project, and an audit table that cannot be changed.
- **v32 saving:** every change goes through `boq_save`, which checks the rules:
  - rights and project access;
  - a registered drawing revision keeps its number, revision and file;
  - status confirmation by someone else;
  - assumptions reviewed and approved by someone other than their author;
  - the estimate status order, with no self-review or self-approval;
  - approved and released lines never change;
  - hand-offs recorded only.
- **v32 files:** a private bucket `boq-drawings` for the drawings.
- **Never touched:** budgets, cost reports, purchase orders, commitments, actual costs, forecasts and earned value.

## Step 2: Publish

Tell Claude "it showed 21". Claude publishes v3.25, and **live.html** uses it within about 2 minutes. Then press **Ctrl + F5**.

## Step 3: Give the review and approval rights (2 minutes)

Settings → **Roles and rights** → group *BOQ Engine*:
- give *review* to the lead engineers;
- give *approve* to the estimation managers.

The Head of Planning and Cost Control has both already.

## Step 4: Check it (5 minutes)

| Do | Expect |
|---|---|
| As a planning engineer: **BOQ Engine → Project & WBS Setup**, create a package and a structure | Saved; visible to a colleague on the same project, not to a person without access |
| **Drawing Upload & Classification**, upload a PDF drawing, then **Register** | The title block values are proposed; the drawing is in the register; an IFC status says *awaiting confirmation* |
| As another person with the review right: **Drawing Register → Details → Confirm** | Confirmed; the person who registered it cannot confirm it |
| Upload the same file again | Refused: already registered |
| Verify two dimensions, make a calculation from them, verify it, start a revision, generate, submit | The revision is *Ready for Review*; the preparer is not offered the review |
| As the reviewer: start the review, approve, release | *Released*; the lines no longer change when a calculation changes |

**To undo:** run `schema-rollback-v32.sql`, then `schema-rollback-v31.sql`.
- Nobody can change BOQ Engine records on the server.
- Everything saved, including the files, is kept.
