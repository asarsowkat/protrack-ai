# v3.32 setup: the Cashflow Dashboard and its finance cost rates

This takes about 3 minutes. **Do not** upload a new `config.js`. It needs the v16 update (STAGE-13-SETUP, roles and rights). Try it on a staging copy first: this update has not yet been run on a database.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v37.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select cf_features(), 'cfd' = any(pt_screens()) as screen, (select basis from cf_settings) as basis;
   ```

   Expect `{"finance_cost_rates": true}`, **true** and **month**.

**What the update does:**
- **The screen** `cfd` (Invoices & Cash Flow → Cashflow Dashboard) joins the screens of Settings → Role access.
- **The rates:** one interest rate (% per annum) per month, the forecast-period average and the basis (each month's deficit, or the cumulative deficit).
  - Read by those who see cost figures.
  - Changed only by a super admin through `cf_rates_set`, with the same checks as the app.
  - Every change is kept in a history that cannot be changed.
- **The figures:** the dashboard works them out in the browser from what the server already gives: the invoice register, the payment terms, the updated schedules, Finance's cash-out, the PO payment terms and the released cost reports. No new figures are stored.

## Step 2: Set the rates (1 minute, super admin)

1. Sign in as the super admin and reload the page.
2. **Invoices & Cash Flow → Cashflow Dashboard → Finance cost: interest rates**:
   - enter the rate of each past month (% per annum);
   - enter the **forecast average** for the months ahead;
   - choose **Interest on**;
   - press **Save the rates**.
3. Check: the **Finance cost** figure shows, and the month-by-month table gives each month's rate.

## To undo

Run `schema-rollback-v37.sql`. The dashboard still shows inflow, outflow and the net, without a finance cost, and leaves Role access. The rates are kept, so running v37 again brings them back.
