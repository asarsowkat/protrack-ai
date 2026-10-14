# ProTrackAI v3.7.1: "Master Manpower Costing Sheet" (October 2026)

Built from your request: "rename the 'costing file' which we are using for manpower productivity and daily report 'Master Manpower Costing Sheet'".

## What changed

The file the costing engineer loads per project is now called the **Master Manpower Costing Sheet** everywhere it appears. It holds the budget quantity, unit, rate, cost and manhours for each activity, and feeds manpower productivity and the daily report.

| Where | Before | Now |
|---|---|---|
| Baselines page | Costing file · Download costing template · Upload costing file | Master Manpower Costing Sheet · Download the sheet template · Upload the Master Manpower Costing Sheet |
| Cost Control menu | Costing file | Master Manpower Costing Sheet |
| Downloaded template | `ProTrack_costing_<project>_<date>.xlsx`, sheet "Costing" | `Master_Manpower_Costing_Sheet_<project>_<date>.xlsx`, sheet "Manpower Costing" |
| Projects → Budget manhours from | Costing file | Master Manpower Costing Sheet |
| Import centre, project checklists, lifecycle items, reconciliation reports, cost dashboard, RASA answers, history entries | costing file | Master Manpower Costing Sheet |
| Roles and rights | Load costing files and invoice registers | Load the Master Manpower Costing Sheet and invoice registers |
| Performance (costing engineers) | Costing uploads | Costing sheet uploads |
| User guide, role guide, README | costing file | Master Manpower Costing Sheet |

**Uploading is unchanged.** Sheets made with the old template still load, because the upload reads the column headings, not the title or the file name.

**Not renamed:** the tender costing documents in the document rack ("Tender costing file", "Original tender costing files") and the lifecycle item "Costing file with detailed breakup handed over". These are the tender estimate handed over at award, not this sheet.

## Database

**No database update.** Saved values stay as they are: a project's budget manhour source is still stored as "Costing file" and uploads are still of kind "costing". They are only shown under the new name.

One server message still uses the old wording: if someone without the right tries to apply the sheet, the refusal says "...can apply a costing file". This can be changed with the next database update.

## Verified
| Check | Result |
|---|---|
| `mmcs_demo.py`: the new name on the Baselines page, the menu, the template file name, project settings, the Import centre and Roles and rights; the stored value unchanged; tender documents untouched | 10 of 10 |
| `e2e_server.py`: the app against the database, including uploading and applying the sheet on the server | 228 of 228 |
| All demo suites (regression, suites, reference, backup, Tender, RASA, releases, issues, quantities, cost, documents, dashboard, schedule, imports, lifecycle, rights) | same results as v3.7 |
