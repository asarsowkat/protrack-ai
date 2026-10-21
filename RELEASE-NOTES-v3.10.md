# ProTrackAI v3.10: Project Visual (October 2026)

Project Visual shows the project's planned and actual progress on its own drawings and route. It is not a new schedule engine:
- **Activity progress:** the earned value ProTrackAI already works out. Construction comes from daily-report quantities, and engineering and procurement from the updated P6 schedule.
- **Planned progress:** the baseline you choose (original, revised or recovery).
- **Weights:** the earned-value budget weights.

## Where to find it
**Home**, under the executive reports:

| Item | For | What it shows |
|---|---|---|
| **Project Visual: Live** | management and planning roles | the latest valid data on the drawing or route |
| **Project Visual: Released** | the same people | the copy frozen into each approved internal report |
| **Project Visual: Configuration and mapping** | the people who keep Project Visual | set-up, drawings, zones, route, mappings and history |

**Who keeps Project Visual:** a new right, *Keep Project Visual*, under Settings → Roles and rights. By default it goes to planning engineers for their projects, the Head of Planning and Cost Control (with the position), and super admins.

**Screens:** Project Visual is in Screens by role. Site roles and foremen don't see it unless a super admin switches it on for them.

## Set up a project
In Configuration and mapping → **Visualization set-up**, or in Settings → Projects (Edit project):

| Setting | Choices |
|---|---|
| Visualization type | **Site layout** (area-based: substations, plants, buildings), **Linear route** (chainage: overhead lines, underground cable, pipelines), or **Hybrid** (both) |
| Linear route kind | Overhead transmission line, Underground cable network, Pipeline, Other |
| Drawing or route source | PDF drawing, GIS route data, or both |
| Baseline for planned progress | the original baseline, or a revised or recovery baseline when one is loaded |
| On track within | ± percentage points, 2 by default |
| Route length | the chainage of the end of the route |
| Work stages (linear) | name, unit and weight of each stage |
| Work-stage progress | by quantity where every activity in the stage has one, else by budget weight |

The work-stage lists for each route kind are **defaults**: overhead lines have 9 stages, underground cable 10 and pipelines 7. Set the approved names, units and weights.

Changing the type never deletes drawings, zones, sections, mappings or releases. Views that no longer apply are hidden and come back if you switch back. Every change is in the history.

## Drawings
- **Uploading:** PDF only, up to 25 MB, multi-page; choose the page to show. Give each upload its drawing number, revision, title, discipline, what it is used for (site layout or route drawing) and a description.
- **Checks:** the file must really be a PDF. The same file, or the same revision number twice, is refused.
- **Storage:** the file is kept **unchanged** in this browser, in the same store the document rack uses. Zones, routes and progress are stored apart from it and never written into the PDF.
- **A new revision of a drawing number** waits for review, and Live keeps using the current revision until then. **Review** shows the two revisions side by side and lists the current revision's zones. For each zone you choose **Move** (same place on the new sheet, with its mappings) or **Retire**. **Make current** then supersedes the old revision. The old revision, its zones and mappings are kept, and releases keep the revision they were made with.
- **The viewer:** zoom with the wheel or + and −, drag to move, Fit, and Full screen.

## Zones and the route
- **Zone tools:** **Rectangle**, **Polygon** (click the corners, double-click or Enter to finish, Backspace removes the last corner, Esc cancels), **Point**, and **Route line** (on a route drawing).
- **Editing a zone:** select it to rename it, set its type and an optional code (as used in P6), drag its corners, map activities to it, or retire it.
- **Coordinates:** stored as fractions of the page, so overlays stay aligned at any zoom and size.
- **Route sections:** name, start and end chainage (for example 0+000 and 5+000), work front, circuit. Overlaps are allowed and flagged.
- **Structures:** towers, poles, joint bays, manholes, access points, terminations, valve stations. Add them one by one, or as a series (for example T1 to T121 every 400 m).
- **GIS route:** a GeoJSON or KML line; its length is measured on the coordinates. Shapefiles are not read; export them to GeoJSON or KML first. A PDF is never assumed to carry coordinates.

## Mapping activities
- **What an activity maps to:** a zone, a section, a structure, or the whole route, with a **share** (an allocation percentage) and, on the route, a **work stage**.
- **One activity can map to several places, and several activities to one place.** An activity's shares add up to **100% at most**, so its progress is never counted twice. A whole-route mapping is spread over the sections by length.
- **Suggest matches (rules):**
  - exact zone codes found in the activity;
  - an activity location equal to a zone name;
  - chainage ranges written in the activity ("km 0 to 24", "CH 5+000 to 10+000");
  - tower numbers;
  - words in common.

  Each suggestion shows its evidence and a confidence. Equal matches are marked as conflicts and share the activity until you decide.
- **Suggest with AI:** on the demo page only, with sample data, under the RASA rules. AI suggestions are labelled. On the ProTrack server it is switched off: no project data is sent to an outside AI service.
- **Approval:** nothing counts until approved. Approve, reject, change the share or stage, or remove; each step records who and when. **Approve suggestions at 90% or more** does that in one step, except conflicts.
- **The mapping register** has these filters: waiting for review, conflicts, low confidence, approved, rejected, retired, unmapped activities, and zones or sections without activities.

## How the figures are worked out
| Figure | Rule |
|---|---|
| Activity planned | share of its baseline duration elapsed at the cut-off (`plannedPct`) |
| Activity actual | earned value ÷ budget at the cut-off (`evm`) |
| Zone, section, total | Σ budget × share × progress ÷ Σ budget × share (`bacOf`, the earned-value weight) |
| Variance | actual − planned, in percentage points |
| Status | Completed at 100%; Delayed or overdue when a mapped activity is past its baseline finish and not complete; Behind or Ahead outside ± tolerance; On track inside; Not started; Unmapped |
| Work stage | its own unit: quantities convert only within one kind (m with km, counts with counts), so towers and kilometres are never added. The stage uses quantity when every activity in it has a compatible quantity, else budget-weighted progress, and says which. |
| Route total | Σ stage weight × stage progress ÷ the weights of the stages that have activities |
| Critical | total float ≤ 0 and not complete. **From v3.10, the P6 import keeps total float.** Schedules imported earlier show "total float not in the import". |

Route **coverage** (the length the sections define) is shown apart from construction progress: a route is not done because a line has been drawn.

**Data-quality warnings:**
- no baseline;
- baseline dates missing for the chosen set;
- shares over 100% (scaled back) and activities partly allocated;
- unmapped activities and zones, suggestions waiting for review;
- activities without a budget, stage quantities in units that don't convert, route mappings without a stage, stage weights not adding up to 100;
- overlapping sections, sections not covering the route;
- a drawing revision waiting for review, a failed last import (the last valid data is shown), a data date more than 8 days old;
- no total float in the import.

## Live and Released
- **Live** shows:
  - the cut-off;
  - the schedule data date (from the updated schedule, else the last daily report);
  - the latest successful import and any later failed one;
  - the drawing and mapping revisions;
  - the figures, the drawing or route, and the registers;
  - filters for WBS, discipline, location and activity status.
- **Released** is the copy saved with each internal report when it is **approved** (Planning & Scheduling → Internal Reporting), as the open issues and material status already are. It holds:
  - the release ID, period, revision and approver;
  - the cut-off and baseline;
  - the drawing revisions (zones and their geometry);
  - the route sections and structures, and the mapping revision;
  - the calculation settings, every figure and warning, and a fingerprint.

  It is never recalculated. A correction is a new revision of the internal report, with its own snapshot; the earlier one stays, marked Superseded. The approval workflow and its rights are the internal reporting ones.
- **Export PDF** (A3 landscape) works for Live and Released, labelled LIVE or RELEASED on every page. It contains:
  - the summary and the warnings;
  - each drawing with coloured zones and a legend;
  - the route grid in parts of eight sections;
  - the work stages, progress by zone and section, and the activity register.

## On the ProTrack server (live.html)
- **Kept in each browser for now:** set-up, drawings, zones, sections, structures and mappings. The page says so when you are signed in to the server.
- **Snapshots:** a release approved through the server does not yet carry Project Visual.
- **What the server needs before go-live** (a v19 database update):
  - tables for these records, with the rights above;
  - a private storage bucket for drawings;
  - the snapshot saved with the release.

## Limitations
- **PDF content:** PDFs are shown as drawings. Their text and shapes are not read to find zones; zones are drawn by hand or matched by name, code and chainage.
- **AI matching:** demo page only, and always suggestions.
- **GIS:** GeoJSON and KML lines only, not shapefiles.
- **Time-chainage:** a planning view only; it does not change the P6 schedule.

## Demo
- **Sample set-up:** opening Project Visual on the demo page prepares clearly marked samples:
  - **Jubail 380kV Substation:** site layout (generated sample drawing JBS-LAY-001 rev B, five zones);
  - **Riyadh-Qassim OHTL:** linear, 48 km (route plan QOT-RTE-001 rev A, two sections, 121 towers);
  - **Jazan pipeline:** hybrid (Pump Station 2 layout and two pipeline sections).
- **Mappings:** they come from the rules. Matches at 80% or more are approved by the project's planning engineer; the rest wait for review.
- **Releases:** the released internal reports of these projects carry their snapshot.
- **Reset demo data** clears all of it.

## Checks
`tests/project_visual_demo.js` runs 24 checks in the browser console on the demo page and puts the demo data back afterwards. It covers:
- the sample, allocation limits and double counting, the zone and variance formulas, suggestions;
- the route spread, stage units, route coverage;
- refused uploads, drawing revisions, frozen releases and corrections;
- rights and redirects, GIS length, PDF export.
