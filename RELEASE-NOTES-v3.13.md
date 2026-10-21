# ProTrackAI v3.13: import many projects from Excel (October 2026)

With 100 or more projects, creating them one by one is not practical. The super admin can now bring them all in from one sheet.

## How
**Settings → Projects → Import projects from Excel** (super admin) opens a full window in three steps.

1. **Template.**
   - **Download the template:** `ProTrack_projects_template.xlsx`, with three sheets:
     - **Projects:** one row per project;
     - **How to fill:** each column explained, with two examples;
     - **Lists:** the regions, sectors, cities (with their region), project types, statuses and people (name, email, role) as they are in ProTrackAI.
   - **Download the current project list:** every project in the same layout.
2. **Upload:** Excel (.xlsx, .xls) or CSV, up to 10 MB, with the Import centre's file checks.
3. **Check and create:**
   - The page shows a count of rows ready, already in ProTrackAI, refused and with warnings.
   - A table lists each row with its result (the first 300 rows are shown; all are checked).
   - If any row is refused, you tick a box to confirm before the rest is created.

## Columns
| Column | Rule |
|---|---|
| PE number | 2 to 24 characters. Empty only for a pre-award tender: ProTrackAI gives the next PE number |
| Project name | required |
| Short name | up to 22 characters; the start of the name if empty |
| Status | Pre-award, Active, On hold or Completed |
| Region | name or code; required |
| Sector, City | name or code; required unless pre-award. The city must exist (add it under Settings → Cities first); a city outside the region is a warning |
| Project type | from the list; Other if empty or unknown (warning) |
| Start date, Finish date | required unless pre-award; the finish after the start |
| Contract value (SAR M) | original contract value, zero or more |
| Client, Location | text |
| TE number, Bid position, Expected value (SAR M), Date Tender notified | the Tender details; bid position L1 or L2 (L1 if empty) |
| NOA date | not for a pre-award tender; not in the future, before notification or after signing. The finance WBS is recorded as released on the same date (v3.12) |
| Contract signed | date |
| Project manager, Site engineer, Planning engineer, Costing engineer | email or full name of a person with that role; they get access. Someone not found is a warning, not a refusal |

## What it does
**Each ready row:**
- creates the project;
- gives access to the named people, and to the Heads and coordinators of Planning and Cost Control, as a Tender registration does;
- writes the Tender register history: *Registered*, *PE allocated*, and *NOA received* / *Finance WBS released* when a NOA date is given.

**Rows that are not created:**
- **Already in ProTrackAI:** a project with the same PE number, or a new tender with the same TE number, is **left unchanged**. The same list can be uploaded again as it grows; to change an existing project, edit it in Settings → Projects.
- **Refused:** a row is refused, with the reason, when:
  - the region, sector or city is unknown;
  - a date is wrong, or the finish is not after the start;
  - the PE or TE number appears twice;
  - a pre-award tender has a NOA date;
  - a number is negative.

**The upload itself:** it is a numbered batch in the Import centre (kind *Project list*), with its refused rows. The same file is not loaded twice.

## On the ProTrack server (live.html)
**Saved on the server:**
- the project records (name, sector, region, city, type, dates, value, status), in one go;
- the team access.

**Kept in the browser for now:** the Tender columns (TE number, bid position, Tender dates, NOA) and the batch. The server's project table does not hold them yet. Moving them needs a server update.

## Checks
`tests/project_import_demo.js` runs 17 checks in the browser console on the demo page, with a 125-row file of 120 projects. It covers:
- the template sheets;
- the counts and the reasons for refused rows;
- warnings, and confirming refused rows;
- creation, the field values and the same-day finance WBS;
- access and the next PE number;
- the batch and the history;
- re-uploads, the current-list round trip, and that only a super admin sees the import.

The 22 Tender register checks still pass.
