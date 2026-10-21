# ProTrackAI v3.26.1: module-by-module review fixes (October 2026)

Every module was reviewed after the v3.19–v3.26 changes. There is nothing new to learn: the screens are the same. Some figures, rules and checks are now correct where they were not before.

**Detail:** [REVIEW-v3.26.1.md](REVIEW-v3.26.1.md) lists each finding by module, its fix, and the eight points left as they are, each with its reason.

## What users will notice

**Internal and client reports:**
- A report prepared after its week or month uses the schedule that was in force at the end of that period, not today's schedule.
- SPI shows 1.00 when nothing is planned yet. It no longer shows a red 0.00.
- The project manager's remarks given with "Mark reviewed" are kept.
- Reporting status takes the first release to decide whether a report was on time, and it shows "Returned".

**Cost report:**
- A new warning row appears when the budget (D) differs from Rev-0 plus the approved supplements.
- The sample August reports show this warning. Their budgets leave out that month's supplements; the cause is the sample data, not the code.

**Cash-out forecast:** a cancelled PO, or a PO in a currency other than SAR, no longer makes a whole cost head count as covered.

**Change order log:** "Not approved" and "Pending approval" no longer count as client approved.

**Invoiceable amounts:** the same figure everywhere, on the client contract value and including the advance.

**Delay register upload:**
- A file is saved completely or not at all.
- An event keeps its status when the file has no status column.

**BOQ Engine:**
- Each estimate revision keeps its own copy of its calculations. Its Excel file and line detail show what it was released with.
- Approval checks again that each line still matches its calculation.
- The author of a calculation cannot verify it.
- A drawing status is confirmed by someone else, never by the person who set it.
- The cable trench now measures the sand without the ducts. The sample substation trench shows sand 56.863 m³ and selected backfill 298.8 m³.

## Server updates

Several of the update files were corrected in place: v24, v27, v28, v29, v30, v32 and v33, with the v24 rollback. None of these updates has been run on a database yet, so there is nothing new to run. Run them in order, as STAGE-26-SETUP.md and STAGE-27-SETUP.md say.

The most important correction is in v30: `pt_phase_tbl` would have failed on every internal report save.

## Checks

- **Acceptance suites:** 19 suites, 411 checks, all passing. One check was added: a calculation's author cannot verify it.
- **Screens:** every screen opened as each of the 11 roles, 456 views in all, with no error.
- **Report windows:** every internal and client report window opened, every tab, weekly and monthly. Then 48 cost report windows. No error, and no blank or broken number.
