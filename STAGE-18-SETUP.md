# v3.14 and v3.15 setup: baseline comparison, the schedule's own baseline, invoice dates by phase and the payment period, on the server

This takes about 15 minutes. **Do not** upload a new `config.js`. The v17 update (STAGE-14-SETUP, Material Tracking) must be in first. v18, v19, v20 and v21 are **not** needed for this one.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v22.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
   - If it says **"Run schema-update-v17.sql (STAGE-14-SETUP) first"**, do STAGE-14-SETUP first, then run this again.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select (select count(*) from pg_proc where proname in ('release_act_bl','pt_bl_cmp','pt_inv_phase','pt_proj_billing','bl_cash_features')) + (select count(*) from information_schema.columns where table_schema='public' and ((table_name='schedule_updates' and column_name='bl_src') or (table_name='schedule_update_rows' and column_name in ('xbs','xbf')) or (table_name='invoices' and column_name in ('phase','sub_date','appr_date','coll_date')))) + (select count(*) from pg_trigger where tgname='trg_proj_billing') as installed;
   ```

   Expect **13**: five functions, seven columns and one trigger.

**What the update does:**
- **Internal and client reports** keep the baselines ticked under *Actual against baselines* and the comparison table, saved with the report. The browser works out each baseline's planned % and finish, as in the demo. The server then fills in the actual, the forecast finish, the variance, the SPI and the days late or early from the report's own figures. When the report is approved, the comparison is frozen with the rest of the released version. **Revise** copies it into the new draft
- the server refuses a save with no baseline ticked (*Choose at least one baseline to compare the actual progress with*), an unknown baseline, or a table that does not match the ticks
- **Updated schedules** (Baselines and P6 import → updated schedule) keep the dates of the *baseline assigned in the updated schedule* for each activity, and where they come from (the baseline project exported with the XER, or the schedule's planned dates). So that baseline can be ticked on the server too
- **The invoice register** keeps each invoice's phase and its submission, approval and collection dates. The server refuses the same rows as the upload page:
  - an approved or collected amount without its date
  - approved before submitted, or collected before approved
  - a date in the future (Saudi Arabia date) or not a valid date
  - a phase that is not a payment-terms phase, Advance, Retention release or Variations
  - a register in the earlier layout (amounts only) still loads
- **The payment terms** keep *Client pays within (days of submission)*: a whole number of days from 0 to 365, blank meaning 60

Nothing else changes: release_act and every approval rule stay as they are. Running it twice is safe.

## Step 2: Publish

Tell Claude "it showed 13". Claude merges the update, and **live.html** uses it within about 2 minutes. Then press **Ctrl + F5**.

Until the update is in, live.html keeps its v3.14 / v3.15 fallback:
- the comparison is shown and worked out in the browser, but not saved with the report
- the schedule's own baseline is not kept, so it shows as *not in this updated schedule*
- the invoice phase and dates are not kept: the register shows the amounts and the invoice date
- the payment period is saved with the other payment terms, without the server's check

## Step 3: Check it (10 minutes)

| Do | Expect |
|---|---|
| As a planning engineer: **Baselines and P6 import → updated schedule**, upload a P6 XER exported **with its baseline** | Loaded. On an internal report of that period, **Baseline assigned in the updated schedule** can be ticked, and its line names the baseline project |
| **Planning & Scheduling → Internal Reporting**, open a draft, tick **Original** and **Revised**, **Save** | Saved. Reload the page (Ctrl + F5): the same two are ticked and the table shows the same planned, actual and variance |
| Untick every baseline and save | Refused: "Choose at least one baseline to compare the actual progress with" |
| Submit, then approve it as the Head of Planning and Cost Control | Released. The check boxes are locked and the table no longer moves when a baseline changes |
| Do the same on a **client report** | The same, with client weightage. Its Excel (Summary sheet) carries the comparison |
| **Invoices & Cash Flow → Invoice register → Download template**, fill one row with an approved amount and **no approval date**, upload | The row is refused: "Approval date missing for the approved amount" |
| Fix the row, upload again and apply | Loaded. After Ctrl + F5 the register still shows the phase and the three dates. **Invoicing status by phase** shows the last dates |
| **Settings → Projects**, open a project, set *Client pays within* to **45**, **Save payment terms**, then Ctrl + F5 | The field still shows 45. The **Cash-inflow forecast** collects 45 days after submission |

To see what the server saved, run these in the SQL Editor (they only read):

```sql
select project_id, kind, period, rev, status, figures -> 'bl_sel' as ticked, jsonb_array_length(figures -> 'bl_cmp') as baselines from report_releases where figures ? 'bl_cmp' order by updated_at desc limit 5;
```

```sql
select invoice_no, inv_type, phase, sub_date, appr_date, coll_date from invoices order by uploaded_at desc limit 10;
```

```sql
select id, short, billing -> 'pay' as payment_period from projects where billing ? 'pay';
```

Reports saved **before** this update have no saved comparison. Until they are released, the card works it out in the browser, as before. Schedules loaded before this update have no assigned baseline (*not in this updated schedule (loaded before v3.14)*); upload the XER again to add it. Invoice registers loaded before this update have no phase or dates; upload the register again.

## If something goes wrong

| What you see | What to do |
|---|---|
| The comparison is back to the original after reloading, and nothing is refused | Step 1 has not run, or live.html was not refreshed. Run the check in step 1, then press Ctrl + F5 |
| "The comparison does not match the baselines ticked. Reload the page and save again" | The page was open while a baseline was loaded or removed. Reload and save again |
| "Figure bl_sel must be a number" | The page in the browser is older than this update. Press Ctrl + F5 |
| "The payment period must be from 0 to 365 days" | Enter a number of days from 0 to 365, or leave it blank for 60 |
| "Run schema-update-v17.sql (STAGE-14-SETUP) first" | Do STAGE-14-SETUP, then run this update again |

**To undo:** run `schema-rollback-v22.sql`. It goes back to the v3.13 rules on the server:
- `release_act_bl` and `bl_cash_features` are removed, so live.html goes back to its fallback (above)
- the updated schedule and the invoice register are loaded as before v22 (`schedule_update_commit` from v17, `import_invoices` from v5)
- the payment-period check is removed

Everything already saved (the comparisons in the reports, the schedule's baseline dates, the invoice phases and dates, the payment periods) is kept. It is used again if `schema-update-v22.sql` is run again.
