# ProTrackAI v3.30: budget supplements edited like Excel (October 2026)

**Cost Control → Budget supplements** can now be kept on the screen like a spreadsheet. The Excel upload is optional. Nothing changes on the server: the grid saves through `supp_update` (schema-update-v35.sql), the same function the one-row form used.

## The grid

The costing engineer or the costing coordinator chooses one project and its latest version, and presses **Edit in the grid** (or **Add rows**). Every row of that log becomes a row of cells, whatever the filters:

| Column | In the grid |
|---|---|
| No, Description, WBS Group, WBS ID, WBS Description, Linked VO / claim, Remarks | Typed |
| WF date | A date picker; a pasted 2026-10-05, 05/10/2026 (day first) or 5-Oct-26 is read |
| **User field** | A drop-down of the list (code · description) |
| **Category** | A drop-down of the list (category → unified category) |
| Unified category | Follows the category |
| Amount (SAR) | Typed: negative for a supplement or a VO cost, positive for a saving or a VO price; 1,250 and (120,000) are read |
| Supplement, Savings, VO Cost, VO Price, Net value | Follow the amount, the category and the user field as you type |
| Check | What the row still needs (a missing WF date, a value not in the list, a number twice), or *new*, *changed*, *deleted when saved* |

- **Enter** goes to the row below (a new row after the last one); ↑ and ↓ move between rows.
- **Add row** adds an empty row; ✕ deletes a row, and **Keep** undoes it before saving.
- **Paste from Excel:** copy a range in Excel and paste it into any cell. Its columns are taken in the grid's order (No, WF date, User field, Category, Description, Amount, WBS Group, WBS ID, WBS Description, Linked VO / claim, Remarks), rows are added as needed, and the user field and category are matched to the lists whatever their case.
- **Save** checks every row first and saves nothing while a row needs fixing. Deleting asks for one reason. Each change is kept under *Changes on this screen*, with who and when. If the server refuses a change, the save stops there: what was saved stays saved, and the rows not saved stay in the grid with the reason.
- **Cancel**, or choosing another project or version, asks first when there are changes not saved.
- Rows logged before v3.29 are shown in the grid but changed only by uploading the log again. Earlier versions stay read-only.

## A log without a file

A project with no supplement log has **Start the Oct-26 log here**: it starts an empty log for this month and opens the grid. A project whose latest log is from an earlier month has **Start the Oct-26 version**, which copies the latest log and opens the grid. The Excel template, upload and export are unchanged, and the upload panel says it is optional.

## Also

- The one-row *Add a supplement* / *Change* / *Remove* form is replaced by the grid.
- *By unified category* and *By user field* under the log keep their heading above their table on wide screens (the heading and the table were drawn side by side).

## Checks

- `tests/supplements_demo.js` now has 51 checks. New, driving the real cells: the grid holds every row whatever the filters, with drop-downs; typing an amount, a user field and a category fills the unified category and the VO price at once; a row without a WF date stops the save and says why; a changed amount, a new row and a deleted row are saved with three history entries; a range pasted from Excel fills two rows with the lists matched and a day-first date read; the same number twice is flagged; leaving with changes asks first; the pasted rows are saved; a project without a log starts it on the screen and saves a typed row.
- Checked by hand in the browser: a real paste event of two rows, Enter to the row below, and no sideways page scroll at phone width (the grid scrolls inside its box).
- Suites sharing the screen pass: contract value 25, reporting status 28, cost visibility 28, executive report status 11.
- On the live server, the grid's save calls `supp_update` once per change; it was not tried against a live database here.
