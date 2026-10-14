# ProTrackAI v3.8: Material Tracking (October 2026)

Built from your specification "Material & Procurement Tracking", with your answers:
- **Each material's schedule columns show its current stage:** the activity in progress, or the next one due.
- **Delayed means forecast late:** not completed, and either the forecast finish is later than the baseline finish, or the baseline finish has passed at the data date.
- **A new right controls editing:** "Keep material tracking", in Roles and rights.

## Where
**Materials & Procurement → Material tracking.** It was shown as "planned" before.

## 1. Set-up from the approved baseline (planning engineer)
1. Choose the project and press **Load the approved baseline (XER)**.
2. The file is read in the browser. ProTrackAI then offers four choices:
   - **The two P6 activity codes.** One holds the **Material Name** (e.g. GIS Equipment, Power Transformer, Shunt Reactor, Control Panels, Steel Structures, Cable Drum). The other holds the **Unified Activity Name** (e.g. PR Creation, PO Creation, Base Design, GAFM Approval, Manufacturing, FAT, Shipment, Delivery, Installation Readiness). ProTrackAI picks the code types whose names say so, and you can change them.
   - **The WBS branches holding the material activities**, for example Procurement, Material, Supply Chain or any other branch. Branches with those names are ticked for you.
   - **The milestone column for each Unified Activity Name.** It is matched from the name, so "Shipment" goes to Release for Shipment, "Delivery" to Delivery at Site and "Installation Readiness" to Civil Readiness. You can change any match, or set it to "Not tracked".
   - **The materials to monitor.** Each one shows how many activities it has.
3. **Load** saves it. Each material gets one monitoring row.

**Changing it later:**
- The mapping and the monitored materials can be changed later without loading the file again.
- **Load a revised baseline** replaces the material activities. PO numbers, suppliers, remarks and your choice of monitored materials stay as they are. New materials are added.

## 2. The tracking table (one row per material)

| From the schedule (automatic) | Kept by hand |
|---|---|
| WBS, Material Name, Unified Activity Name, Current schedule status, Baseline start and finish, Current start and finish, % complete | PO Number (text) |
| PR Creation, PO Creation, Base Design, GAFM Approval, Manufacturing, FAT, Release for Shipment, Delivery at Site, Civil Readiness | Supplier Name (type, or pick a known supplier or subcontractor) |
| **Delivery Status** | Remarks (several lines) |

**Where the dates and statuses come from:**
- **The schedule columns** are those of the material's current stage.
- **Each milestone** shows **Not Started**, **In Progress**, **Completed** or **Delayed**, with its actual or forecast finish. Several activities under one milestone are combined: Completed when all are complete, Delayed when any is late, In Progress when any has started.
- **Delivery Status** comes from the activities tagged Delivery at Site:
  - **Not Delivered** (red) until one starts
  - **Delivery Started** (amber) while it runs
  - **Delivered** (green) once it is complete
- **Where statuses are read:** the latest updated schedule (Baselines → Updated schedule), matched by activity ID. Until the first update, the baseline file is used. An updated schedule also shows material activities that are not in the baseline, if they carry a Material Name in the chosen branches.
- **Manual fields:** PO Number, Supplier Name and Remarks are saved as soon as you leave the box. A schedule import never changes them. **History** shows each material's activities and every change: field, before, after, who and when.

## 3. Dashboard
- **Eight summary figures:**
  - Total Materials Tracked
  - Not Delivered
  - Delivery Started
  - Delivered
  - Delayed Materials
  - Manufacturing in Progress
  - Pending FAT (manufactured, FAT not done)
  - Pending Shipment (FAT done, not yet released)
- **Three charts:**
  - Delivery Status Distribution
  - Supplier-wise Material Status
  - Procurement Progress Breakdown, by milestone
- **Filters:** Project, WBS, Material, Supplier, Delivery Status and Procurement Status (the current stage). There is also an option to show the materials not monitored.
- **Search** finds a Material Name, PO Number or Supplier Name.
- **Sorting:** by Delivery date, Supplier, Status or Material.
- **Export:**
  - **Excel:** a tracking sheet, a summary and the history.
  - **PDF:** the tracking table on A3 landscape.

## 4. Who can do what
- **Keep Material Tracking** (set-up, PO number, supplier and remarks) is a new right in Roles and rights:
  - By default it goes to **planning engineers** and to the **Head of Planning and Cost Control**, by position.
  - The super admin can give it to costing engineers or any other role or person.
- **Viewing:** the tracking is in the menu for every office role with access to the project: executives, regional and portfolio managers, planning and costing engineers, project managers and read-only users.
  - Material tracking is a new screen in Screens by role, so the super admin can also show it to site engineers and site managers, or hide it from any role.
  - Foremen do not have it.
- **On the server:** every change is checked by the server, and the history cannot be edited or deleted.

## 5. Ready for later
The material rows already have room for quantity ordered, quantity delivered and unit. Partial deliveries, GRN, SAP PR and PO, the vendor portal, inspection status and site receipt can be added later without changing the existing data.

## Database: `schema-update-v17.sql`

**New tables:**

| Table | Holds |
|---|---|
| `material_setup` | per project: the two code types, the WBS branches, the milestone mapping, the baseline file |
| `material_acts` | the material activities of the baseline |
| `material_items` | one row per material: monitored or not, PO number, supplier, remarks (and the quantity columns for later) |
| `material_audit` | the history (append-only) |

**New functions:**

| Function | What it does |
|---|---|
| `material_setup_save` | loads the baseline, saves the mapping and the monitored materials; checks every row; never touches the manual fields |
| `material_item_save` | saves PO number, supplier, remarks; one history entry per changed field |
| `pt_mat_keeper` | who may keep it: the new right, with project access |

**Updated:**
- **`schedule_update_rows`** gets four new columns: early start, Material Name, Unified Activity Name and the activity's own WBS. `schedule_update_commit` fills them.
- **Roles and rights:** the new right `materials.keep` and the new screen `mat` (`pt_rights`, `pt_screens`, `pt_right_default`).

**Safe to run twice.** Rollback: `schema-rollback-v17.sql` goes back to v3.7 and keeps every table, column and history entry.

## Validation rules (app and server)

| Rule | Message |
|---|---|
| Only planning engineers of the project, the Head, a super admin or someone given the right | "Only the people who keep material tracking … can change it" |
| Two different activity codes | "The Material Name and the Unified Activity Name must be two different activity codes" |
| At least one WBS branch | "Choose at least one WBS branch that holds the material activities" |
| Only the nine milestones | "Unknown milestone …" |
| Every activity: ID up to 60 characters, a Material Name up to 120, valid dates, % complete 0 to 100 | "Activities refused …" |
| PO number 60, supplier 120, remarks 4,000 characters at most | "The PO number is 60 characters at most" and so on |
| A baseline must be loaded before the mapping is changed | "Load the baseline schedule into Material Tracking first" |

## Verified
| Check | Result |
|---|---|
| `test_v17.py`: the server rules of v17 on PostgreSQL 16 (rights, checks, mapping, monitored materials, manual fields and history, never overwritten, schedule codes, reads, rollback and re-apply) | 63 of 63 |
| Earlier server suites (v4 to v16), each run with the later updates up to v16 and then up to v17 | only expected change: the v16 count of rights and screens is now 18 and 22 |
| `mat_demo.py`: set-up from a synthetic XER, statuses, Delayed rule, updates, manual fields, history, filters, search, sorting, export, rights, phone (app and sample-data page) | 50 of 50 on each |
| `e2e_server.py`: the app against the database, v17 applied mid-run (baseline load, manual fields, statuses from an update, revised baseline, refusals) | 237 of 237 |
| All earlier demo suites | same results as v3.7.2 (the regression count of "planned" menu items is one less: Material tracking is live) |

Not verified: the real Supabase project and a real XER with your activity codes. The first set-up on live.html is the real test.

## Known limits
- **Statuses come from P6.** They change when a new updated schedule is uploaded, not in between.
- **Activities are matched by ID.** An activity renamed in P6 under a new ID appears as a new activity.
- **Charts** appear when the chart library can load (the same as the other dashboards).
