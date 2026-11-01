# v3.48 setup: Client Invoice Builder

This takes about 10 minutes. **Do not** upload a new `config.js`. It needs v50 (STAGE-44-SETUP).

It passed 85 checks on a test copy of the full schema (PGlite), but has not yet been run on Supabase, so try it on a staging copy first.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `supabase/schema-update-v51.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select cib_features() ->> 'version' as version, 'cib' = any(pt_screens()) as screen;
   ```

   Expect **51** and **true**.

**What the update adds:**
- **Six rights:**
  - `cib.setup` (Schedule-C, rules, invoice history);
  - `cib.map` (P6 mapping);
  - `cib.prepare` (prepare, submit, issue);
  - `cib.review`;
  - `cib.approve`;
  - `cib.certify` (client certificate and payment).
- **The `cib` screen**, in Role access.
- **The tables:**
  - Schedule-C revisions and their items;
  - the P6 mapping and the reviews of unmapped items;
  - client invoices;
  - the append-only audit trail.
- **The server works out every invoice itself**, from:
  - the updated schedule's progress;
  - the mapping;
  - the rules;
  - the TCC and FAC actual dates;
  - the previous certified invoice.

  It checks every right, the separation of duties and every state change.

## Step 2: Give the rights (2 minutes)

In **Settings → Roles and rights**, group **Client invoices**, the defaults are:

| Right | Default | Give it also to |
|---|---|---|
| `cib.setup`: Schedule-C, rules, history | Costing and planning engineers | — |
| `cib.map`: P6 mapping and reviews | Planning engineers | — |
| `cib.prepare`: prepare, submit, issue | Costing and planning engineers | — |
| `cib.review`: review invoices | Project managers | Project controls managers |
| `cib.approve`: approve invoices and Schedule-C revisions | Regional managers and the Head of Planning and Cost Control | Commercial and division managers |
| `cib.certify`: client certificate and payment | Costing engineers | Finance |

Only people who see billing figures (`money.view`) see client invoices. Foremen never do.

## Step 3: The P6 activity code (one time per project)

In P6, create an activity code type named **Schedule C**. On each activity, set its value to the Schedule-C item number the activity earns, for example `A.SS.4.1.6.1`.

The next time the updated schedule is loaded in ProTrackAI (Planning → updated schedule), the mapping is read automatically. You can also load the XER in **Client Invoice Builder → Mapping audit**.

## Step 4: First invoice (5 minutes)

1. **Invoices & Cash Flow → Client Invoice Builder → Schedule-C**:
   - upload the contractual price schedule (the **Template** button shows the columns);
   - check the header and the rules by component (they start from the project's payment terms);
   - save. Another person with `cib.approve` approves it.
2. **Mapping audit**: map or review every item shown as Missing.
3. **Running project only:** in **Client invoices → Load the latest certified client invoice**, load the last certified invoice workbook. Check each sheet's certified-to-date column and the totals, then load it.
4. **Client invoices → Prepare from P6 progress**:
   - run **Review invoice**;
   - mark the supporting documents;
   - submit.

   The project manager reviews it, and the approver approves it. Then:
   - issue it;
   - export the **Excel invoice**;
   - record the client's certificate and the payment.

## To undo

Run `supabase/schema-rollback-v51.sql`. It removes the builder's tables and functions, the six rights and the screen. The invoice register and the cash pages keep working with the uploaded register.
