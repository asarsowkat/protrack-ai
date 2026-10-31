# v3.41 setup: the cost plan and the MER

This takes about 3 minutes. **Do not** upload a new `config.js`. It needs v16 (Roles and rights, STAGE-13-SETUP). Try it on a staging copy first: this update has not yet been run on a database.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `supabase/schema-update-v45.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select cost_plan_features() ->> 'version' as version, 'cplan' = any(pt_screens()) and 'mer' = any(pt_screens()) as screens, (select count(*) from pg_policies where policyname = 'cp_read') as read_rule;
   ```

   Expect **45**, **true** and **1**.

**What the update does:**
- **Cost Control → Cost plan:** a cost plan per project and year (internal plan, finance plan, forecast, year start), kept in the table `cost_plans`.
  - Saved by the project's costing engineer (Prepare monthly cost reports, with access to the project) or a super admin; a saved plan is Draft.
  - The project manager marks the internal plan Agreed; the head of planning and cost control, an executive or a super admin approves the finance plan.
  - Read by those who see cost figures, on the projects they see. Every save and decision is kept in the plan's history.
- **Cost Control → MER – Monthly Executive Report:** worked out in the browser from the released reports, the logs, the invoice register, the cash-out forecast and the cost plans.
- The screens `cplan` and `mer` can be shown or hidden per role in **Settings → Role access**.
- The **areas of concern** of the monthly internal report and the cost report's **actual stock value** need no change: the server already keeps them with the report.

## Step 2: Check it (1 minute)

1. Sign in as a costing engineer and reload the page.
2. **Cost Control → Cost plan**: choose a project, enter the budget and the planned cost of a few months, and press **Save the internal plan**. It shows **Draft**.
3. Sign in as that project's manager: **Mark agreed**. The plan shows **Agreed**.
4. **Cost Control → MER – Monthly Executive Report**: the project's planned POC now shows on the Cost tab.

## To undo

Run `supabase/schema-rollback-v45.sql`. The Cost plan screen then shows nothing to save and the MER's planned POC shows "—". The table and the saved plans are kept, so running v45 again brings them back.
