# v3.8 setup: Material Tracking

This takes about 20 minutes. **Do not** upload a new `config.js`.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v17.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select (select count(*) from pg_proc where proname in ('material_setup_save','material_item_save','pt_mat_keeper')) + (select count(*) from information_schema.tables where table_schema='public' and table_name in ('material_setup','material_acts','material_items','material_audit')) as installed;
   ```

   Expect **7**: three functions and four tables.

**What the update does:**
- keeps each project's Material Tracking set-up, the material activities of its baseline, one row per material with PO number, supplier and remarks, and a history that cannot be edited
- lets every updated schedule keep each activity's Material Name and Unified Activity Name, so the statuses refresh
- adds the right "Keep material tracking" (planning engineers, and the Head by position) and the screen "Material tracking" to Roles and rights

Nothing else changes, and running it twice is safe.

## Step 2: Publish

Tell Claude "it showed 7". Claude merges the update, and **live.html** shows **v3.8** within about 2 minutes. Then press **Ctrl + F5**.

## Step 3: Check your P6 schedule (once)

Material Tracking reads two **activity codes** from the XER. In P6, the material activities need:

| Activity code | Example values |
|---|---|
| **Material Name** | GIS Equipment, Power Transformer, Shunt Reactor, Control Panels, Steel Structures, Cable Drum |
| **Unified Activity Name** | PR Creation, PO Creation, Base Design, GAFM Approval, Manufacturing, FAT, Shipment, Delivery, Installation Readiness |

The code types can have other names; you choose them in Step 4. They must be exported with the XER (P6: Export → XER, with activity codes).

## Step 4: Set it up for one project (planning engineer, 5 minutes; from v3.8.1, no extra upload)

| Do | Expect |
|---|---|
| **New project:** import the original baseline XER as usual (Planning & Scheduling → Baselines and P6 import → Original baseline) | The preview shows **Also set up Material Tracking from this baseline**, ticked, with the two activity codes and the Procurement branch picked |
| **Project whose baseline is already loaded:** upload the next weekly updated XER as usual (Baselines → Updated schedule) | The preview shows **Also set up Material Tracking from this schedule**, ticked |
| Check the two code types and the WBS branch(es), then **Import** / **Save updated schedule** | One step: the import or update, and Material Tracking |
| **Materials & Procurement → Material tracking** | One row per material; check the milestone of each Unified Activity Name and untick materials you do not monitor in Set-up |
| Type a PO number, a supplier and remarks in a row, then click elsewhere | "Saved". **History** on the row lists the change |

## Step 5: Every schedule update (planning engineer)

Upload the updated XER as today (**Planning & Scheduling → Baselines and P6 import → Updated schedule**). Material Tracking then shows:
- the new statuses
- the forecast and actual dates
- Delivery Status

PO numbers, suppliers and remarks are never changed by an upload.

## Step 6: Rights (super admin, optional)

**Settings → Roles and rights**:
- **"Keep material tracking"** is ticked for Planning Engineer. Tick it for another role (for example Costing Engineer), or give it to one person in Users and access.
- **"Material tracking"** in Screens by role shows or hides the screen for each role. Site engineers and site managers do not have it until you tick it.

## If something goes wrong

| What you see | What to do |
|---|---|
| Amber box: "Material Tracking needs the v17 database update" | Step 1 has not run. Run `schema-update-v17.sql` |
| "This schedule has fewer than two activity code types" | Export the XER again with activity codes |
| "No activity in the chosen WBS branches carries a Material Name" | Tick the right WBS branch, or check the Material Name code type |
| "The Material Name and the Unified Activity Name must be two different activity codes" | Choose two different code types |
| "Only the people who keep material tracking … can change it" | Ask the super admin for the right "Keep material tracking" |
| A milestone column stays empty | No Unified Activity Name is mapped to it. Change the mapping in Set-up |

**To undo:** run `schema-rollback-v17.sql`. It goes back to v3.7. Material Tracking then stops saving. Everything already saved is kept and comes back if `schema-update-v17.sql` is run again.
