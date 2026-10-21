# ProTrackAI v3.9.1: the Master Manpower Costing Sheet gets its own page (October 2026)

Built from your request: "remove the Master Manpower Costing Sheet from Baselines and it shall be separate full window under Cost Control. Similar to sample template, costing engineer can able to download the existing uploaded value so add one more button Download existing."

## Cost Control → Master Manpower Costing Sheet
A full page of its own. Baselines no longer shows the costing sheet. Choose the project at the top. The page has three buttons:

| Button | What you get |
|---|---|
| **Download new sample template** | The blank sheet, as before: every activity ID of the project's baseline, with budget manhours pre-filled from P6 |
| **Download current existing data** | The same sheet, filled with the costing applied now: budget quantity, UOM, unit rate, budget cost, budget manhours and gang code. Activities with no costing are left blank. Change what you need and upload it again. File: `Master_Manpower_Costing_Sheet_<project>_current_<date>.xlsx`. The button is greyed out until a sheet has been applied to the project. |
| **Upload the Master Manpower Costing Sheet** | The same upload as before: preview, checks, reconciliation, then apply |

Below the buttons, **Costing applied now** lists every costed activity with its quantity, unit, rate, cost, manhours and gang code.

- **Who can open the page:** the same people as before, meaning costing engineers, project managers, planning engineers and super admins.
- **Roles and rights:** it is a new screen under Settings → Roles and rights → Screens by role.
- **Shortcuts:** the Import centre button and Imports & Integrations → Excel templates both open it.

## Fixed: uploading the template back was refused
The upload took the template's own instruction line, "One row per activity ID…", for the header row. It then said the sheet had no "Budget quantity" or "UOM" column. It now looks for the header only in short cells, so both downloaded sheets upload as they are. This was already the case in v3.8.4 and v3.9.
