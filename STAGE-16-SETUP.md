# v3.11 setup: the internal and client contract value on the server

This takes about 10 minutes. **Do not** upload a new `config.js`. The v18 update (STAGE-15-SETUP) must be in first. The v19 update (Project Visual) is **not** needed for this one, and either can go in first.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v20.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
   - If it says **"Run schema-update-v18.sql (STAGE-15-SETUP) first"**, do STAGE-15-SETUP first, then run this again.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select (select count(*) from pg_proc where proname in ('pt_contract_of','pt_vo_check','pt_release_contract','vo_update')) + (select count(*) from information_schema.tables where table_schema='public' and table_name='co_log_updates') + (select count(*) from information_schema.columns where table_schema='public' and ((table_name='co_log' and column_name in ('client_price','internal_price','wf_no','wf_date')) or (table_name='report_releases' and column_name='contract_snapshot'))) as installed;
   ```

   Expect **10**: four functions, one table and five columns.

**What the update does:**
- the change order and claim log keeps the **client approved price**, the **price considered internally** and its **internal WF number and WF date**. An upload refuses a row that breaks the rules (for example a price considered internally without a WF number and date, or above the estimated price)
- the costing engineer or costing coordinator can **Update** a row of a project's latest log on the screen. Every change is kept under **Updates to the log** and in the Change log. Earlier months stay as they were uploaded
- when an internal report, client report or cost report is approved, the server saves its contract breakdown with it. A client report keeps only the original, the approved by the client and the client revised value. A released version keeps it and it cannot be changed

Nothing else changes, and running it twice is safe.

## Step 2: Publish

Tell Claude "it showed 10". Claude merges the update, and **live.html** shows **v3.11** within about 2 minutes. Then press **Ctrl + F5**.

## Step 3: Check it (5 minutes)

| Do | Expect |
|---|---|
| As the costing engineer of a project: **Claims & Variations → Change order and claim log**, upload the template with the new columns | The rows load. The KPIs show **Approved by the client**, **Considered internally** and **Revised contract value (internal)** |
| On the latest month of that log, press **Update** on a row, give a price considered internally **without** a WF number, and **Save** | Refused: "A price considered internally needs the management approval WF number and WF date" |
| Add the WF number and a WF date, **Save** | The row shows the price, **Full** or **Partial**, and the WF. **Updates to the log** shows the change with your name. The contract value follows |
| Choose an earlier month of the log | No **Update** buttons: earlier months stay as uploaded |
| Sign in as a site manager or a planning engineer and open the log | No **Update** buttons |
| Approve a submitted internal report, then a client report, of that project | The internal report's **Contract value** card shows the full breakdown; the client report shows only original, approved by the client and revised contract value |
| Update the log again, then open those released reports | Their contract value has **not** changed |

To see what the server saved, run this in the SQL Editor (it only reads):

```sql
select kind, period, rev, status, contract_snapshot from report_releases where contract_snapshot is not null order by approved_at desc limit 5;
```

Reports approved **before** this update have no breakdown saved with them. The app works theirs out from the log up to their month, as before.

## If something goes wrong

| What you see | What to do |
|---|---|
| On the log screen: "Updating a row on this screen needs the v20 database update" | Step 1 has not run. Run `schema-update-v20.sql` |
| "Only the costing engineer or costing coordinator updates the log" | Only they (or a super admin) can update it. A super admin can give the **logs.upload** right in **Settings → Roles and rights** |
| "Only the latest log of the project can be updated" | Someone uploaded a newer log. Reload the page and update the row in the latest month |
| "The WF date is in the future" | The WF date is checked against today's date in Saudi Arabia |

**To undo:** run `schema-rollback-v20.sql`. It goes back to v3.10 on the server:
- uploads no longer store or check the four new columns
- **Update** on the log screen is switched off again
- approving a report no longer saves its contract breakdown; the app works it out from the log

Everything already saved (the four columns, the update history and the breakdown of released reports) is kept, and released reports still cannot be changed. It is used again if `schema-update-v20.sql` is run again.
