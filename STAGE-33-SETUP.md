# v3.35 setup: Budget & Cost Management, Automatic WBS Classification

This takes about 15 minutes. **Do not** upload a new `config.js`. It needs the v16 update (Roles and rights, STAGE-13-SETUP). There is no Edge Function to install and no outside service: the files are read and classified in ProTrack, and the server checks and stores everything.

Try it on a staging copy first. The database part has run only on a test database (PostgreSQL 16 with every update v2 to v39), not yet on Supabase itself.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `supabase/schema-update-v39.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select bcm_features() ->> 'version' as version, (select count(*) from pg_proc where proname in ('bcm_master_act','bcm_batch_save','bcm_file_add','bcm_file_run','bcm_classify','bcm_review')) as functions, (select count(*) from bcm_master where ent in ('wbs','rule')) as starting_master;
   ```

   Expect **39**, **6** and **88**.

**What the update does:**
- **Four new rights:**
  - `bcm.upload`: upload tender files, read them and run the classification. Costing engineers have it by default.
  - `bcm.review`: confirm, correct and override classifications. Costing engineers have it by default.
  - `bcm.master`: propose changes to the WBS master, rules and thresholds.
  - `bcm.approve`: approve those changes. The person who proposed a change never approves it.
  - The Head of Planning and Cost Control holds review, master and approve by position.
  - Seeing the module needs the cost-figures right (`money.view`).
- **Tables for the module:**
  - The master data (WBS elements, rules, approved mappings, thresholds), with every version kept.
  - The tender batches and files.
  - The extracted lines. These never change and are never deleted.
  - The classifications, their history and an audit log.
- **The starting WBS master and rules** (the specification's working definitions: SM1 to SM9, Design, Electrical Material, Electrical Manpower, Electrical Equipment, Testing & Commissioning, Civil Works, Saudization, Financing, Contingency, Management Reserve). They arrive as **proposals**, so nothing is classified until your company approves them (Step 3).
- **A private storage bucket `bcm-tender`** for the original files (25 MB each). People who see the project and its cost figures can read them; people with `bcm.upload` can add them; nobody can replace or delete them.
- **Running the update twice is safe.**

## Step 2: Give the rights (5 minutes)

Settings → **Roles and rights**:
- Costing engineers already have `bcm.upload` and `bcm.review`.
- Give **`bcm.master`** to the person who keeps the WBS master (for example the costing coordinator).
- Give **`bcm.approve`** to the person who approves it. That must be someone other than the proposer, for example the Head of Planning and Cost Control (who holds it by position) or a cost control manager.

A super admin also proposes and approves. Like everyone else, a super admin cannot approve their own proposal.

## Step 3: Check and approve the starting WBS master (the important step)

1. Open **Budget & Cost Management → WBS Mapping Master**.
2. Go through the elements. They are working definitions: the codes other than SM1 to SM9 are provisional (for example `ELM-01`, `CIV-06`).
3. If your company's WBS differs:
   - Press **Propose a change** on an element, or **Add an element**.
   - Or download the master to Excel, correct it, and use **Import a WBS master workbook**.
4. If warranty-period expenses have their own element (apart from SM9), add it.
5. Mark **Financing**, **Contingency** and **Management Reserve** "Always needs individual review" (they arrive so marked), and any other element you want reviewed every time.
6. The approver opens the same page and presses **Approve all waiting**. Parents are approved first.
7. Do the same for the rules, under **Classification rules**.
8. **Thresholds and lists** start at 95% (automatic) and 80% (review). The value limits are SAR 1,000,000, USD 270,000 and EUR 250,000. Change them only as a proposal for the approver.

## Step 4: First tender

1. **Tender File Intake**: create a batch (tender reference, revision, currency, project type).
2. Upload the costing workbooks, several at once.
3. Each file is checked, fingerprinted, stored, read sheet by sheet and classified.
4. A sheet whose header ProTrack cannot find says **Map columns**.
5. **Classification Review** lists what needs a person: proposals, high-value lines, combined costs and data problems.
6. Confirm, override (with a reason) or exclude (with a reason).
7. To make a decision reusable, choose **Remember this decision as** (this project, this project type, or all projects). The mapping is then waiting in **Mapping Learning History** for someone else's approval.

## If something goes wrong

| What you see | What to do |
|---|---|
| **Budget & Cost Management needs the v39 database update** | Step 1 has not run |
| **Not classified yet: the WBS master has no approved element** | Step 3: approve the master |
| **You proposed this change, so someone else approves it** | Another person with `bcm.approve` approves it |
| **This file was already uploaded** | The same file (same SHA-256) is never taken twice in a project. To replace a batch, withdraw it (with a reason) and upload into a new one |
| **The workbook is password-protected** | Remove the password in Excel and upload again |
| A sheet **Needs header mapping** | Press **Map columns**, give the header row and the column letters, and read again |
| **Upload the file to storage first** | The upload to the bucket failed; check the storage rules ran (Step 1) and try again |

## To undo

Run `supabase/schema-rollback-v39.sql`. Nothing can be written to the module after that. Every table, file, line, decision and history row is kept, so running v39 again brings everything back.
