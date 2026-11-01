# v3.49 setup: the Schedule-C item from the WBS, invoiced on the "Schedule C Invoicing" weight

This takes about 5 minutes. **Do not** upload a new `config.js`. It needs v51 (STAGE-45-SETUP).

It passed 27 checks on a test copy of the full schema (PGlite), but has not yet been run on Supabase, so try it on a staging copy first.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `supabase/schema-update-v52.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select cib_features() ->> 'version' as version, cib_features() ->> 'inv_weight' as weight;
   ```

   Expect **52** and **true**.

**What the update adds:**
- On the P6 mapping, each activity's **invoicing weight** and where its item number came from (the WBS or the activity code).
- The server works out an item's progress from the activities that carry the invoicing weight, where any does. Otherwise it uses all of the item's activities by schedule weight, as before.
- A warning on the invoice when a mapped item has no activity with the invoicing weight.

No right or screen changes.

## Step 2: Check P6 (one time per project)

1. **The item number on the WBS.** In the WBS view, the user field **Schedule C** holds the item number, for example `A.SS.3.1.1.1.1.1`.
   - Every activity below that WBS takes it, down through any child WBS without a value.
   - A child WBS with its own value uses its own.
   - An activity code **Schedule C** on an activity, where you use one, wins over the WBS.
2. **The invoicing weight.** Assign the resource **Schedule C Invoicing** only to the activities the client is invoiced on. For a material item, that is the inspection after delivery. Its **budgeted units** are the weight.
   - ProTrackAI finds the resource by "Schedule C" or "invoicing" in its name or ID.
   - The internal and SEC weightage resources are not used here.
3. Export the XER **with the WBS user fields and the resource assignments** (the default export does).

## Step 3: Read it in (2 minutes)

Load the updated schedule as usual in **Planning → updated schedule**. The mapping is read automatically.

To check it first:
1. Open **Invoices & Cash Flow → Client Invoice Builder → Mapping audit → Read the Schedule C mapping from P6**.
2. Load the XER and check the WBS field, the activity code and the invoicing resource.
3. Check that the preview says how many activities take an item from the WBS and how many carry the weight. Act on any activity it lists with the weight but no item.
4. Save.

Open an item in the mapping audit to see which activities count ("not invoiced on" for the others).

## To undo

Run `supabase/schema-rollback-v52.sql`.
- The mappings stay.
- Items then earn on all their activities by schedule weight, as in v3.48.
