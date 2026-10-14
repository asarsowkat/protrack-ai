# ProTrackAI v3.8.1: Material Tracking without an extra upload (October 2026)

Built from your request: "i dont want to upload baseline multiple times so protrack should take information from initial baseline which we are uploading initial stage itself and actual/forecast shall be taken from weekly updated p6 file which planning engineer use to upload for reporting purpose".

## What changed

Material Tracking no longer needs its own baseline upload. It takes its information from the two files the planning engineer already loads.

| What | Comes from |
|---|---|
| Material activities, Material Name, Unified Activity Name, **baseline dates** | The **original baseline** XER, imported once at the start (Planning & Scheduling → Baselines and P6 import → Original baseline) |
| **Actual and forecast** dates, % complete, statuses, Delivery Status | The **weekly updated schedule** XER the planning engineer uploads for reporting (Baselines → Updated schedule) |
| PO Number, Supplier Name, Remarks | Typed in Material tracking, as before; never changed by an upload |

### 1. Original baseline import
- **The option:** when the original baseline XER carries activity codes, the import preview shows **Also set up Material Tracking from this baseline**. It is ticked already.
- **Filled in for you:** the Material Name and Unified Activity Name activity codes, and the WBS branch holding the material activities (Procurement, Material, Supply Chain…). It also shows how many material activities and materials it found.
- **One press:** **Import** loads the baseline activities and sets up Material Tracking together.
- **All material activities are taken.** This includes procurement activities that you filter out of the ProTrackAI baseline itself.
- **Importing the original baseline again** refreshes the material activities. PO numbers, suppliers, remarks and your choice of monitored materials are kept.

### 2. Weekly updated schedule
- **Every upload** refreshes the actual and forecast dates of the material activities. Nothing to tick.
- **Projects whose baseline is already in ProTrackAI** (loaded before v3.8.1, without Material Tracking): the next weekly upload shows **Also set up Material Tracking from this schedule**, ticked, so you don't need to load the baseline again.
  - **Baseline dates:** from the original baseline in ProTrackAI where the activity was imported. Otherwise they are the planned dates in that file.
  - **History:** it records "Set up from the weekly updated schedule".

### 3. Material tracking page
- **Set-up section:** it now explains where the data comes from. It offers no main upload button.
- **The mapping and the monitored materials** are still changed there.
- **Fallback:** a small **Load a schedule file here instead** remains, for a baseline imported without its activity codes.

## Database
No database update. This uses the v17 functions already installed.

## Verified
| Check | Result |
|---|---|
| `mt_auto_demo.py`: the original baseline import sets up Material Tracking in the same step; the weekly update brings actual and forecast; a project already loaded is set up by its next weekly upload; no extra upload (app and sample-data page) | 17 of 17 on each |
| `mat_demo.py` and all earlier demo suites | same results as v3.8 |
| `e2e_server.py`: the app against the database | 237 of 237 |

Not verified: your real XER on the real server. The next original baseline import or weekly upload with activity codes is the real test.
