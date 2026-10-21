# ProTrackAI v3.19.2: letters and correspondence on each delay event (October 2026)

Each delay event in **Claims & Variations → Delay events register** now has a **Correspondence and letters** section. The planning engineer records every letter, e-mail, notice, instruction and set of minutes behind the event, with the file when there is one. The extension of time submission then has its **chronology and evidence in one place**.

## Recording a letter
Open an event; below its four groups, **Record a letter or upload a file**:

| Field | |
|---|---|
| **Type** | Letter, E-mail, Notice of claim, Site instruction, Minutes of meeting, Variation order / instruction, Request for information, Drawing / submittal, Photo / site record, Progress report, Other |
| **Direction** | Received (from Employer / Engineer), Sent (from alfanar), Internal |
| **Date of the letter, reference no., subject** | the date and subject are required; no date in the future |
| **From, to, notes** | optional |
| **File** | optional: PDF, Office, e-mail (MSG, EML), images, ZIP or drawings. Up to 10 MB in the demo, 50 MB on the server. The same file twice on one event is refused |

**Add its reference to the register** (ticked by default):
- **received:** the reference and date are added to *Supporting documents ref. (from Employer / Engineer)*
- **sent:** they are added to *Notice of claim supporting documents ref. (from alfanar)*
- **a sent notice of claim** also sets the event's *notice submission date* when it has none. *Days to notice deadline* then says *Notice served*.
- **the event's rules apply.** For example, a notice dated before the event is refused, and the message says to untick the box to record the letter only.

## Using it for the EOT submission
- **The list:** the event's letters in **date order**, with type, direction, reference, subject, from → to and file. **Preview** opens PDFs, images and text in the window; **Download** gets the file.
- **Download the chronology (Excel):** a *Chronology* sheet (the event's dates, time bar, notice and schedule impact, then every record in date order, dates as Excel dates) and an *Event* sheet (the event in the register's layout).
- **Download the EOT pack (ZIP):** `EOT_pack_<PE>_<event>_<date>.zip`. It holds:
  - `00_Chronology.xlsx`, with a column naming each file in the pack
  - `Correspondence/`, every file numbered in date order: `01_2026-05-27_ENG-LTR-0311.pdf`, `02_…`
- **The register:** the *Event* column shows how many letters each event has.

## Keeping the evidence
- **Removing:** a record is never deleted. **Remove** needs a reason in the comment box. The record leaves the list and stays in the history, with its file.
- **Deleting an event:** an event with letters cannot be deleted until they are removed.
- **History:** adding and removing records, and the changes they make to the event, are in the event's history.

## Who
- **Keepers:** the people who keep the register record and remove letters, on their own projects. That is planning engineers, plus the Head of Planning and Cost Control and super admins.
- **Readers:** everyone who reads the register sees the letters and opens the files, on the projects in their access. A project manager, for example, sees the list and the downloads, without the form or *Remove*.

## Demo
Riyadh Metro's *Event 01* holds four sample records:
- the Engineer's letter
- alfanar's notice of claim
- coordination minutes
- the site instruction handing over the corridor

*Event 02* holds the consultant's e-mail. Their files are sample text files. A browser that already held the v3.19 samples gets them when the page loads.

## Checks
`tests/delay_corr_demo.js` runs 16 checks in the browser console on the demo page. They cover:
- the samples and the date order
- the section, the form and the counts in the register
- received and sent letters adding their references, without repeating them
- a sent notice of claim dating the notice, and a refused link with its hint
- the rules, files kept and opened, the same file twice, and a refused file type
- removing with a reason, an event with letters not deleted, and a project manager reading only
- the chronology workbook and the EOT pack's contents

The 26 register checks and 15 list checks still pass.

## Server
`schema-update-v26.sql` (STAGE-22-SETUP.md) adds:
- `delay_corr`
- the private `delay-docs` bucket and its access rules
- `delay_corr_act`, with the same rules
- the trigger that keeps an event with letters

Until it is run, an event's window says that recording letters needs the v26 update. Undo: `schema-rollback-v26.sql`, which keeps every record and file. The SQL has not been run on a database yet.

The EOT pack uses the JSZip library (3.10.1, from cdnjs), loaded only when the pack is downloaded, like the Excel and PowerPoint libraries.
