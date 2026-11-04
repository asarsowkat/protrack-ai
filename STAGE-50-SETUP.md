# v3.57 setup: the invoicing phase from a P6 activity code

This takes about 2 minutes. **Do not** upload a new `config.js`. It needs v55 (STAGE-49-SETUP).

It passed 25 checks on a test copy of the full schema (PGlite), but has not yet been run on Supabase, so try it on a staging copy first.

Without this update the app works as before: the invoicing phase follows the WBS wording. If someone chooses an activity code at the baseline import, the baseline is still imported, with a note that the code needs this update.

## Step 1: Update the database

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `supabase/schema-update-v56.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select media_features() ->> 'version' as version, media_features() ->> 'inv_phase' as inv_phase;
   ```

   Expect **56** and **true**.

**What the update adds:**
- **`activities.inv_phase`:** ENG, PRC, CON or TC, or empty (the WBS wording).
- **`project_inv_phase`:** the activity code chosen for each project and the phase of each of its values. Read by those who see the project.
- **`act_inv_phase_set`:** saves both right after a baseline import. Only the project's planning engineers and super admins can run it, the same rule as importing a baseline.

## Step 2: Try it

1. In P6, give the activities an activity code for the invoicing phase, for example **Invoice Phase** with values such as Engineering, Supply, Construction and Testing. Export the XER.
2. As a planning engineer: **Baselines → Choose P6 or Excel file**, and choose the XER.
3. Under **Invoicing phase taken from**, the code named for invoicing is chosen; each value shows the phase ProTrack suggests. Change any that are wrong, then import.
4. **Invoices & Cash Flow → Cash-inflow forecast → Invoicing status by phase** says the phases come from the activity code.

## To undo

Run `supabase/schema-rollback-v56.sql`. The phases already set stay on the activities and are still used, but can no longer be changed from an activity code. Running v56 again carries on from them.
