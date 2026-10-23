# v3.39 setup: budget supplement and change request forms, approved through Approval Hub

This takes about 10 minutes. **Do not** upload a new `config.js`. It needs v36 (the version of the budget supplement log, STAGE-30-SETUP) and v20 (the change order log).

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `supabase/schema-update-v43.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select wf_hub_status() ->> 'version' as version, (select count(*) from pg_proc where proname in ('wf_form_save','wf_form_act','wf_hub_next','wf_hub_update','wf_hub_setup','wf_hub_status','pt_wf_post','pt_wf_decide')) as functions, (select count(*) from information_schema.tables where table_schema = 'public' and table_name in ('wf_forms','wf_events','wf_outbox','wf_hub_cfg')) as tables;
   ```

   Expect **43**, **8** and **4**.

**What the update does:**
- **New tables:** the forms (`wf_forms`), their history (`wf_events`, never changed), the queue for Approval Hub (`wf_outbox`) and the link settings (`wf_hub_cfg`).
- **Two new rights** (Settings → Roles and rights):
  - **wf.initiate**: prepare and submit the forms. Planning and costing engineers have it by default.
  - **wf.record**: record an Approval Hub decision by hand while the link is not connected. The **costing coordinator** has it by position.
- **An approved Budget Supplement / Returns Request is posted to the budget supplement log** of the project:
  - one row per line, with the WF number and the approval date;
  - its version is the month of the approval;
  - the costing engineer or coordinator can move the version to the month before, or any month up to now, with a reason.
- **An approved Change Request is posted to the change order and claim log.**
- **Rows posted from a WF keep their amounts.** On the log screen only their version and remarks change, and they are not removed there.
- **Running the update twice is safe.**

## Step 2: Try a form (5 minutes)

1. **Cost Control → Budget & change requests.** Choose the project, then press **New budget supplement / returns request**.
2. **Fill in the form.** It follows your form AP/Planning-BRF:
   - 01 general information (from the project master);
   - 02 the lines: description, category, user field, WBS, supplement or saving;
   - 03 the budget summary by user field. It is prefilled from the approved budget versions, the supplement log and the SAP report; type over a figure to correct it;
   - 04 the impact on margin and milestones;
   - 05 the category details;
   - 06 the approvals. VP and EVP are added automatically for contingency and management reserve.
3. **Save it.** **Download the form (Excel)** gives the company layout, to attach in Approval Hub if needed.
4. **Press Submit to Approval Hub.**
5. **Until the link is connected:** the costing coordinator opens the form, enters the Approval Hub decision (WF number, date, approver), then presses **Record the decision**. Once approved, the lines appear in **Budget supplements** with the WF number.

## Step 3: Connect Approval Hub (with the IT team, later)

1. Give **APPROVAL-HUB-INTEGRATION.md** to the IT team.
2. When they are ready, the super admin opens **Budget & change requests → Approval Hub** and presses **Connect: make the token**. Give the token to IT at once: it is shown only once.
3. From then on, decisions arrive by themselves. **Switch the link off** stops it at any time.

## If something goes wrong

| What you see | What to do |
|---|---|
| **Budget and change requests need the v43 database update** | Run Step 1 |
| **Line n: user field … is not in the list** | Choose a user field from Settings → Supplement lists |
| **Only the costing coordinator (wf.record) records an Approval Hub decision by hand** | The costing coordinator records it, or the super admin gives wf.record |
| **Approval Hub is connected: its decision comes by itself** | Wait for the hub, or tick "the decision did not arrive" to record by hand |
| **The version is from … to …** | The version can be the month before the approval, up to the current month |
| **Supplement … was posted from the approved WF …** | Change it with a new request (a supplement or a saving), not on the log screen |

## To undo

Run `supabase/schema-rollback-v43.sql`. This removes the functions, so the forms are read-only and the Approval Hub token stops. The forms and the posted rows stay, so running v43 again brings everything back.
