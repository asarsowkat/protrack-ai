# v3.19 setup: the delay events register, on the server

This takes about 10 minutes. **Do not** upload a new `config.js`. Two earlier updates must be in first:
- v10 (STAGE-7-SETUP, the issue register)
- v16 (STAGE-13-SETUP, roles and rights)

No other update is needed first.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v24.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
   - If it says **"Run schema-update-v10.sql (STAGE-7-SETUP) and schema-update-v16.sql (STAGE-13-SETUP) first"**, do the one that is missing, then run this again.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select (select count(*) from pg_proc where proname in ('delay_act','delay_import','delay_features','pt_dly_keeper','pt_dly_status','pt_dly_nokey','pt_dly_num','pt_dly_numtext','pt_dly_label','pt_dly_keys','pt_dly_merge','pt_dly_log','pt_dly_write')) + (select count(*) from pg_tables where tablename in ('delay_events','delay_audit')) + (select count(*) from pg_policies where tablename in ('delay_events','delay_audit')) + ('delay.keep' = any(pt_rights()))::int + ('dly' = any(pt_screens()))::int + pt_right_default('plan','delay.keep')::int as installed;
   ```

   Expect **20**: 13 functions, the two tables, their two read rules, the new right, the new screen and the planning engineers' default.

**What the update does:**
- **Two new tables:**
  - `delay_events` holds each project's delay events, in the columns of the company *Delay Events Register* workbook.
  - `delay_audit` keeps every change, and the last content of a deleted event. Nobody can change or empty it.
- **Who reads** (the server checks it, whatever the page shows): everyone who sees cost figures, on the projects in their access only. A planning engineer sees the registers of their own projects and no others.
- **Who changes:** the new right **"Keep the delay events register of their projects"**, on the projects in their access:
  - planning engineers by default
  - the Head of Planning and Cost Control by position
  - super admins always
  - the super admin can give it to, or take it from, a role or a person in **Settings → Roles and rights**, as any other right
- **The server applies the page's rules:**
  - the event name and start date are required
  - no date in the future
  - a closed event needs its closing date
  - the notice cannot be dated before the event
  - the time bar is a whole number of days
  - costs are positive amounts
  - an event number is used once per project
  - deleting needs a reason
- **Uploads:**
  - one project per file; events are matched by Claim Event No., else by name
  - refused rows must be acknowledged, and the same file twice in a row changes nothing
  - each upload is listed in the Import centre as *Delay events register*
- **Worked out by the page, not stored:** the claim duration, notice days used, notice days against the time bar and days to the notice deadline.

Nothing else changes. Running it twice is safe.

## Step 2: Publish

Tell Claude "it showed 20". Claude publishes v3.19, and **live.html** uses it within about 2 minutes. Then press **Ctrl + F5**.

Until the update is in, **Claims & Variations → Delay events register** on live.html says *"The delay events register needs the v24 database update (see STAGE-20-SETUP)"* and lists nothing.

## Step 3: Check it (8 minutes)

| Do | Expect |
|---|---|
| As a **planning engineer**: Claims & Variations → **Delay events register** → **Add delay event**. Enter a name, a start date last month and a time bar of 28 days. **Add delay event** | Saved as *Event 01*, Ref. 1. *Days to notice deadline* shows the days left |
| Set the status to **Closed** without a closing date and save | Refused: "Enter the closing date of a closed event" |
| Enter a notice submission date and save | *Days to notice deadline* says **Notice served**; *Notice days vs time bar* is negative (in time) |
| **Download the register (Excel)** | `Delay_Events_Register_<PE>_<date>.xlsx`, in the company layout, with your event |
| In that file, change the *Mitigation / Recovery Action* and add a row *Event 02*. Choose the project, **Choose file**, then **Save 2 rows** | "1 delay events added, 1 updated, 0 unchanged". Upload the same file again: "This is the same file as your last upload, so nothing changed." |
| Sign in as a planning engineer of **another** project | The event is not listed; the project is not in the filters |
| Sign in as a **project manager** of the project | The event is listed; **Open** shows it read-only ("View only: the planning engineers of this project keep its delay events register") |
| Sign in as a site engineer or a foreman | No *Delay events register* in the menu |

To see what the server saved, run this in the SQL Editor (it only reads):

```sql
select (select short from projects where id = project_id) as project, ref, event_no, name, status, start_date, time_bar, notice_date, updated_at from delay_events order by project_id, ref;
```

## If something goes wrong

| What you see | What to do |
|---|---|
| "The delay events register needs the v24 database update" | Step 1 has not run, or live.html was not refreshed. Run the check in step 1, then press Ctrl + F5 |
| "Only the planning engineers of this project, the Head of Planning and Cost Control or a super admin can change its delay events register" | The person does not have the right on that project. The super admin can give it in Settings → Roles and rights, or add the project to the person's access |
| "pt_right_default does not have the expected shape; add delay.keep by hand" | The rights defaults were changed by hand on this database. Ask Claude for the one line to add |
| "Run schema-update-v10.sql (STAGE-7-SETUP) and schema-update-v16.sql (STAGE-13-SETUP) first" | Do the missing setup, then run this update again |

**To undo:** run `schema-rollback-v24.sql`. It removes `delay_act`, `delay_import` and the helper functions, and takes the right and the screen off the lists. Every event and every history entry is kept: run `schema-update-v24.sql` again to use them again.
