# v3.17 setup: report email lists and the cost report margin by column, on the server

This takes about 15 minutes. **Do not** upload a new `config.js`. Two earlier updates must be in first:
- v20 (STAGE-16-SETUP, the internal revised contract value)
- v22 (STAGE-18-SETUP, baseline comparison and invoice dates)

v19 and v21 are **not** needed for this one.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v23.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
   - If it says **"Run schema-update-v20.sql (STAGE-16-SETUP) and schema-update-v22.sql (STAGE-18-SETUP) first"**, do the one that is missing, then run this again.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select (select count(*) from pg_proc where proname in ('report_mail_set','release_act_cv','margin_mail_features','pt_release_cvby','pt_cost_cv_by','pt_cv_cols','pt_rel_mail_reader','pt_rel_mail_region_keeper','pt_mail_roles')) + (select count(*) from pg_trigger where tgname='trg_rr_cvby') + (select count(*) from report_mail_lists where region_id is null) + (select count(*) from pg_policies where tablename='report_mail_lists') as installed;
   ```

   Expect **13**: nine functions, one trigger, the two default lists and one read rule.

**What the update does:**
- **The report email lists are kept on the server**, so they apply whoever approves the report, in any browser. Until now each browser kept its own.
  - The default list for **internal reports** and the list for **monthly cost reports** start as in the demo:
    - internal reports: project managers, portfolio managers, regional managers, executives and planning engineers, monthly and weekly
    - cost reports: the same, with costing engineers instead of planning engineers
  - A **region** can have its own list for internal reports. A region without one uses the default list.
  - Each list keeps the on / off switch, *weekly too* (internal reports), the roles, the named people and the other addresses.
- **Who changes a list** (the server checks it, whatever the page shows):
  - the **super admin**: every list (Settings → Email → Report emails)
  - the **section planning manager** of a region: that region's internal report list only (Planning & Scheduling → Internal Reporting → *Report email for your region*). The section planning managers are the ones set under *Who approves progress releases*
  - nobody else; another region's list or a default list is refused
- **Who reads the lists:** everyone who approves reports (super admin, Head of Planning and Cost Control, the section planning managers, and anyone given the right to approve internal or cost reports). The email goes out from the approver's browser, through the mail function `send-daily-report`, as before.
- **The server refuses** an unknown role, a person who is not a ProTrack user, an address that is not an email address, and more than 50 other addresses.
- **Cost reports by WBS head keep the contract value of each column** (`cv_by`), with the same rules as the demo:
  - Tender (A) and Rev-0 (B1): the original contract value
  - Revised Rev-0 (B2), current budget (D) and EAC (I): the internal revised contract value
  - Previous version (C): the contract value of the previous released cost report, else the internal revised value at the end of the previous month
- **The server works the values out itself** on every save of a draft, from its own change order and claim log. At approval it sets A, B1, B2, D and I as of approval, with the contract breakdown (v20). Then they are frozen with the rest of the released version.
- The page sends the values it shows. If the server's differ (the log changed while the page was open), the server's are saved and the page says which column.

Nothing else changes: `release_act`, `release_act_bl` and every approval rule stay as they are. Running it twice is safe.

## Step 2: Publish

Tell Claude "it showed 13". Claude merges the update, and **live.html** uses it within about 2 minutes. Then press **Ctrl + F5**.

Until the update is in, live.html keeps its v3.17 fallback:
- the email lists are kept in each browser, so a list applies only to reports approved in that browser. Settings → Email → Report emails says so
- the margins are worked out in the browser while the form is open. A released cost report shows the internal revised value in every column, as reports saved before v3.17 do

## Step 3: Check it (10 minutes)

| Do | Expect |
|---|---|
| As the super admin: **Settings → Email → Report emails**. Under *Monthly cost reports*, untick **Executives** and add `finance@company.com` | Saved without a note about *kept in this browser*. Reload (Ctrl + F5): the change is still there |
| Sign in as the super admin in **another browser** (or on another computer) and open the same section | It shows the same cost report list |
| As the **section planning manager** of a region: **Planning & Scheduling → Internal Reporting → Report email for your region**. Tick *Use a list for the region*, untick **Weekly internal reports too** | Saved. Reload: the region has its own list, and the super admin sees *own list* next to the region |
| Add `finance` (no @) to *Other addresses* | Refused: "Not an email address: finance" |
| As a costing engineer: **Cost Control → Cost reports**, open this month's draft by WBS head, **Save** | Saved. Reload: the **Contract value** row shows the original value under A and B1, the internal revised value under B2, D and I, and the previous month's value under C |
| Submit it, then approve it as the super admin | Released. The contract value and gross margin rows keep their values. **Settings → Email → Sent emails** lists the cost report email, sent to the list set above (not to Executives). The email is listed in the browser of the person who approved |
| Approve a **weekly** internal report of that region | No email for that region, because *weekly too* is off. A monthly report still sends one |

To see what the server saved, run these in the SQL Editor (they only read):

```sql
select kind, coalesce((select name from regions where id = region_id), 'default') as list, enabled, weekly, roles, cardinality(people) as named_people, extra, updated_at from report_mail_lists order by kind, region_id nulls first;
```

```sql
select project_id, period, rev, status, figures -> 'cv_by' as contract_value_by_column from report_releases where kind = 'cost' and figures ? 'cv_by' order by updated_at desc limit 5;
```

Cost reports saved **before** this update have no `cv_by`. A draft gets it on its next save. A released report keeps one value for every column, as on the demo page. A list set in a browser before this update is **not** moved to the server: set the lists again in step 3.

## If something goes wrong

| What you see | What to do |
|---|---|
| Settings → Email still says the lists are *kept in this browser* | Step 1 has not run, or live.html was not refreshed. Run the check in step 1, then press Ctrl + F5 |
| "The lists could not be read from the server: …" | Run the check in step 1. The rest of the message says what the server answered |
| "Only the section planning manager of the region or a super admin changes this list" | The person is not the section planning manager of that region. The super admin names them under *Who approves progress releases* |
| "Saved. The server worked out the contract value of column … " | The change order and claim log changed while the page was open. The report shows the server's value; nothing to do |
| "Run schema-update-v20.sql (STAGE-16-SETUP) and schema-update-v22.sql (STAGE-18-SETUP) first" | Do the missing setup, then run this update again |

**To undo:** run `schema-rollback-v23.sql`. It goes back to the v3.16 rules on the server:
- `margin_mail_features`, `release_act_cv` and `report_mail_set` are removed, so live.html goes back to its fallback (above)
- the cost report trigger `trg_rr_cvby` is removed; `release_act` and `release_act_bl` are not touched

Everything already saved is kept: the email lists stay in `report_mail_lists`, and `cv_by` stays in the cost reports. Nobody can read the lists until `schema-update-v23.sql` is run again, which uses them again.
