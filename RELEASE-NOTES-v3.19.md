# ProTrackAI v3.19: the delay events register (October 2026)

**Claims & Variations → Delay events register** is new. It keeps every delay event of a project, in the 27 columns of the company *Delay Events Register* workbook.

| Group | Columns |
|---|---|
| **Claim contractual data** | Ref., claim event no., name, identification, start date, status (Ongoing or Closed), closing date (if closed), *claim duration till date*, supporting documents ref. |
| **Notice of claim data** | time bar (contractual days), submission date, documents ref., *notice days used*, *notice days vs time bar*, *days to notice deadline* |
| **Schedule impact data** | detailed description, affected baseline activities, schedule impact (days), claim data date, entitlement type, liability party |
| **Cost impact data** | prolongation cost, variation orders omitted and added, concurrency flag, mitigation / recovery action, claim owner |

The columns in italics are **worked out**, never typed:
- **Claim duration till date:** the closing date of a closed event, else today, minus the start date.
- **Notice days used:** notice submission date minus start date.
- **Notice days vs time bar:** notice days used minus the time bar. Above 0 the notice was late (red); 0 or less it was in time (green).
- **Days to notice deadline:** start date plus time bar minus today, until the notice is dated, then *Notice served*. 0 or less red, 1 to 7 amber, more green, as in the workbook's colour rules.

The workbook's own formulas for these four columns point outside the sheet (`#REF!`). ProTrackAI works them out as above, and the downloaded file carries working formulas.

## On the screen
- **KPIs:**
  - delay events, ongoing and closed
  - notices not served: past the time bar, due within 7 days
  - notices served late
  - schedule impact in days
  - cost impact: prolongation plus variations added, less omitted
- **Delay events by project:** the same figures per project, and whether you keep or read it. Tap a row to filter.
- **Filters:** project, status, notice of claim (not served, time bar passed, deadline within 7 days, served late, served in time), entitlement, liability, and a search over the words and letter references.
- **The register**, then **Open** an event. The window opens full screen with the four groups, and the worked-out columns follow what you type.

## Create and change in the system
- **Add delay event:**
  - event numbers run *Event 01, Event 02…* per project unless you type one
  - Ref. is the event's order in the project
- **The rules:**
  - the event name and start date are required
  - no date in the future
  - a closed event needs its closing date, and a closing date needs *Closed*
  - the closing date and the notice cannot be before the start date
  - the time bar is a whole number of days, 0 to 3650
  - costs are positive amounts
  - schedule impact and costs can be a note such as *Not calculated yet*
  - an event number is used once per project
- **History:** every change is kept with who, when and which fields. **Delete event** needs a reason, and the deleted event stays in the history.

## Excel
- **Download the register (Excel):**
  - the events the filters show, one sheet per project (named by its PE number), in the workbook's layout
  - the four group headings merged over their columns, and the 27 headers word for word over two rows
  - events from row 4, dates as Excel dates (`dd-mmm-yy`), and the four worked-out columns as formulas
  - file name: `Delay_Events_Register_<PE>_<date>.xlsx`, or `Delay_Events_Register_<date>.xlsx` for several projects
- **Download template:** the same layout with an *Example* row (skipped on upload) and a *How to fill* sheet.
- **Upload:**
  - choose the project, then the file: the company register or the template
  - the sheet named by the project's PE number is read, else the first sheet
  - events are matched by **Claim Event No.**, else by name, so they are updated, not duplicated. A blank number never renumbers an event
  - **refused rows** are listed with their sheet row: a missing name, a bad date, a status other than Ongoing / Closed, a number used twice, or any rule above. Tick the box to save the rest
  - dates can be date cells, `2026-09-22`, `22/09/2026` or `22-Sep-26`
  - the same file twice in a row changes nothing, and each upload is listed in the **Import centre** as *Delay events register*

## Who sees and who keeps
| Who | Can |
|---|---|
| **Planning engineers** | add, change, delete, upload and download the delay events of **their own projects** (new right *Keep the delay events register of their projects*, group Planning) |
| Head of Planning and Cost Control (by position), super admin | the same on any project in their access |
| Costing engineers, project managers, executives, regional and portfolio managers, read-only | see and download the registers of the projects in their access |
| Site engineers, site managers, foremen | no access |

Everyone sees only the projects in their access, so a planning engineer never sees another engineer's projects. The super admin can give or take the right, and show or hide the screen *Delay events register*, in **Settings → Roles and rights**.

## Demo
The demo page holds 12 sample delay events on four projects (Riyadh Metro, Riyadh-Qassim OHTL, Jeddah DC and Jubail). They cover:
- an event closed with its notice served in time
- notices past the time bar, due within 7 days, and served late
- schedule and cost impacts

## Checks
`tests/delay_register_demo.js` runs 26 checks in the browser console on the demo page. They cover:
- the menu, the screen and the samples
- the four worked-out columns and their colours
- every rule, the event numbers, the history and deleting
- the right: planning engineers on their own projects only, project managers and read-only reading, no site roles
- the Excel layout, dates and formulas
- upload matching, refused rows with their sheet rows, saving, the import history, and the same file twice

The v3.12, v3.17 and v3.18 checks (22, 17 and 16) still pass on the combined pages.

## Server
`schema-update-v24.sql` (STAGE-20-SETUP.md) keeps the register on the server:
- `delay_events` and an append-only `delay_audit`
- `delay_act` and `delay_import`, with the same rules
- the right `delay.keep` and the screen `dly`
- read rules: cost-figure viewers, on the projects in their access

Until it is run, live.html shows *"The delay events register needs the v24 database update"*. Undo: `schema-rollback-v24.sql`, which keeps every event. The SQL has not been run on a database yet.
