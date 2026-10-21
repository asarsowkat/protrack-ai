# v3.12 setup: L1 and L2 tenders, and the notice of award, on the server

This takes about 10 minutes. **Do not** upload a new `config.js`. The v16 update (STAGE-13-SETUP, roles and rights) must be in first. v18, v19 and v20 are **not** needed for this one.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v21.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
   - If it says **"Run schema-update-v16.sql (STAGE-13-SETUP) first"**, do STAGE-13-SETUP first, then run this again.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select (select count(*) from pg_proc where proname = 'tender_features') + (select count(*) from information_schema.columns where table_schema='public' and table_name='projects' and column_name in ('bid_rank','rank_note','fwbs_on','noa_by')) + (case when 'tender.noa' = any(pt_rights()) then 1 else 0 end) as installed;
   ```

   Expect **6**: one function, four columns and the new right.

**What the update does:**
- every project keeps **our bid position**, L1 or L2, and the optional reason for L2. Projects registered before v3.12 count as **L1**
- the bid position can be changed in the Tender details until the NOA is received; then it is fixed
- the NOA date is no longer typed into the Tender details. **Record NOA received** (costing coordinator or super admin) saves it with the **finance WBS released the same day** for the PBG cost, makes a Pre-award project **Active**, and writes *NOA received* and *Finance WBS released* to the register history and an entry to the stage 3 history
- the server refuses an NOA date in the future, before the date Tender notified or after the contract signing, and a correction without a reason (kept as *NOA date corrected*)
- a new right, **Record the notice of award**, in Settings → Roles and rights. The costing coordinator has it by position; super admins always
- stages 1 and 3 not yet submitted take the v3.12 wording (*bid position (L1 or L2)*, *Finance WBS released on the NOA date to record the PBG cost*). Ticks already given are kept

Nothing else changes, and running it twice is safe.

## Step 2: Publish

Tell Claude "it showed 6". Claude merges the update, and **live.html** uses it within about 2 minutes. Then press **Ctrl + F5**. Until the update is in, live.html keeps the v3.12 fallback: the NOA is saved as the award date, and the bid position is not kept.

## Step 3: Check it (5 minutes)

| Do | Expect |
|---|---|
| As the costing coordinator: **Projects & Handover → Tender register → Register an L1 or L2 project**, choose **L2** and give a reason, save | The register shows the project as **L2**, *Awaiting NOA*. Its history says *Registered* with the reason |
| Open it, change the bid position to **L1**, **Save Tender details** | Saved; the history shows *bid position L2 to L1* |
| Press **Record NOA received** with a date **before** the date Tender notified | Refused: "The NOA date cannot be before the date Tender notified" |
| Press it with today's date | The project is **Active**. *NOA and finance WBS* shows the date. The history shows *NOA received* and *Finance WBS released*; stage 3 shows the entry |
| Try to change the bid position again | The field is locked. (The server also refuses: "The bid position cannot change once the NOA is received") |
| **Correct the NOA date** without a reason, then with one | First refused: "Give a reason for correcting the NOA date". Then saved as *NOA date corrected*, and the finance WBS date moves with it |
| Sign in as the Head of Planning and Cost Control or a planning engineer and open the project | No **Record NOA received** button |

To see what the server saved, run this in the SQL Editor (it only reads):

```sql
select id, te_number, bid_rank, rank_note, status, award_on, fwbs_on, (select name from profiles where id = noa_by) as noa_by from projects where te_number is not null order by registered_at desc limit 5;
```

Projects whose award date was entered **before** this update have no finance WBS date. They show *The finance WBS release was not recorded (NOA entered before v3.12)*.

## If something goes wrong

| What you see | What to do |
|---|---|
| In the Tender details: "The bid position and the finance WBS date need the v21 database update" | Step 1 has not run. Run `schema-update-v21.sql` |
| "Only the costing coordinator or a super admin records the notice of award" | Give the person the costing coordinator position (Settings → Users and access), or the **Record the notice of award** right in **Settings → Roles and rights** |
| "Record the notice of award with Record NOA received" | The award date is no longer saved with **Save Tender details**. Use **Record NOA received** |
| "Tender details, PE numbers, the NOA and cancellations are recorded in the Tender register" | Something tried to write these straight into the projects table. Use the Tender register |

**To undo:** run `schema-rollback-v21.sql`. It goes back to the v3.11 Tender rules on the server:
- the award date is typed into the Tender details again, and the finance WBS date is no longer set
- the bid position is no longer saved, and the **Record the notice of award** right leaves Settings → Roles and rights
- live.html goes back to its v3.12 fallback (the NOA saved as the award date)

Everything already saved (the bid positions, the L2 reasons, the finance WBS dates, who recorded the NOA, and every history entry) is kept. It is used again if `schema-update-v21.sql` is run again.
