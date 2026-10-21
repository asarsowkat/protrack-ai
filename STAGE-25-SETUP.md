# v3.22 setup: Reporting status, on the server

This takes about 5 minutes. **Do not** upload a new `config.js`. The v14 update must be in first (STAGE-11-SETUP, the regional approval of progress releases).

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v29.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select (select count(*) from pg_tables where tablename in ('rs_config','rs_exemptions','rs_reminders')) + (select count(*) from pg_proc where proname in ('reporting_act','reporting_features','pt_rs_reminder_ok')) + (select count(*) from rs_config) as installed;
   ```

   Expect **7**: three tables, three functions and the default rules.

**What the update does:**
- **`rs_config`:** the reporting rules. Monthly deliverables are due on day 7 of the next month and weekly ones 2 days after the week ends. The internal report and the monthly cost report are required before the executive report of a period is released. Only the super admin changes them, and the internal report always stays required.
- **`rs_exemptions`:** a project exempted for one period, with its reason, by the super admin or the Head of Planning and Cost Control. It can be withdrawn; the exemption is kept, marked withdrawn.
- **`rs_reminders`:** every reminder, which cannot be changed afterwards.
  - **Who sends:** a super admin, the Head, a regional or portfolio manager, or the section planning manager of the project's region, on a project in their access.
  - **Who receives:** planning or costing engineers and project managers of that project.
  - **How often:** at most once a day for the same deliverables. The email goes out from the sender's browser through the mail function `send-daily-report`, as for approvals.
- **Where the statuses come from:** the releases and uploads the server already holds. The page holds the executive report of a period until every active project has released the required deliverables. The released data of each project stays readable as before.

## Step 2: Publish

Tell Claude "it showed 7". Claude publishes v3.22, and **live.html** uses it within about 2 minutes. Then press **Ctrl + F5**.

## Step 3: Check it (3 minutes)

| Do | Expect |
|---|---|
| As a regional manager: **Home → Reporting status**, weekly, the last week | Your region's projects with their internal report status; the banner says whether the weekly executive report is released or held |
| **Remind** an outstanding project | "Reminder sent to …"; the email is listed in Settings → Email → Sent emails; a second reminder the same day is refused |
| As an executive: **Executive report**, the same week, if held | *Held*, with the count of projects released, and no figures |
| As the super admin: **Exempt** the outstanding project with a reason | The project shows *Exempted*; once every project is complete, the executive report opens for everyone |

**To undo:** run `schema-rollback-v29.sql`. Nobody can send reminders, exempt projects or change the rules on the server; everything already saved is kept.
