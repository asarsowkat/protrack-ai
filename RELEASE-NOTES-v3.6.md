# ProTrackAI v3.6: internal weightage, updated schedules, internal and client reporting (October 2026)

Built from your request of 13 October 2026, with your answers:
- **Phase mapping:** each phase comes from the main WBS branch or from a P6 activity code. Both work.
- **Progress source:** once an updated schedule is loaded, planned %, actual % and milestone dates come from it.
- **The tick box** says which weightage the uploaded schedule is loaded with: client or internal.
- **Reporting:** "Progress releases" is renamed **Internal Reporting**, and a new **Client Reporting** is added.
- **Invoiceable** uses the client weightage with the schedule's actual %.

## What changed

### 1. Internal weightage by phase (Baselines and P6 import)
- **Where:** a new **Internal weightage by phase** panel on **Planning & Scheduling → Baselines and P6 import**.
- **What you set:** the planning engineer enters a % for each of seven phases once, at the start of the project:
  - General works
  - Design
  - Material
  - Construction
  - Installation
  - Testing & commissioning
  - Project close out
- **Rules:**
  - The total must be 100%. It is shown as you type.
  - Only planning engineers of the project and super admins can save it.
  - Every change is kept in a history that cannot be edited.
  - Once a schedule has been reported, a change needs a reason.
- **The panel also shows** which main WBS branches or activity code values feed each phase.

### 2. Updated schedule
- **Where:** a new **Updated schedule** panel on the same page.
- **Uploading:**
  - Tick whether the schedule is loaded with **client weightage** or **internal weightage**.
  - Choose the updated P6 file (XER).
- **ProTrackAI reads from the file:**
  - the data date
  - each activity's % complete: physical, duration or units, as set in P6; 100% when completed, 0% when not started
  - the planned dates
  - the forecast and actual finish dates
  - the milestones
- **Before saving you see:**
  - **Client weighting:** taken from the schedule's weighting resource (or planned labour units, or duration).
  - **Phase of each activity:** from the main WBS branch (sub-branches roll up), or from a P6 activity code such as "Phase". ProTrackAI suggests the phase from the name; you can change it.
  - **Results:** planned and actual % by phase, client %, internal %, and the TCC, PAC and FAC dates.
- **Rules when saving:**
  - Every weighted activity needs a phase once internal weightage is set.
  - Saving the same file twice changes nothing.
  - Updates are kept for good: they cannot be changed or deleted, even from the database console.
- **Your PE-329 baseline file:** its seven main WBS branches are already your seven phases, so they map automatically.

### 3. One source for progress in every report
- **With an updated schedule loaded,** progress for that project is the **internal weightage** of the latest one. This applies to:
  - Planned %, actual % and SPI on the project overview, dashboard, executive summary tiles and columns, portfolio by region and sector, and the progress-by-project and progress-by-region reports.
  - RASA's progress and schedule answers.
  - The internal report.
- **Combining several projects:** they are weighted by contract value, as in the released executive report.
- **Labels:** each figure says where it comes from, for example "internal weightage, schedule of 20 Sept 2026".
- **Projects without an updated schedule** work as before.
- **Daily reports** still drive productivity, manpower and quantities. The Earned value page (EV, PV, AC, CPI, EAC) stays cost-weighted.

### 4. Invoiceable value by client weightage
For each activity in the latest updated schedule, invoiceable value now uses the **client price weighting × the schedule's % complete**. Activities not in the schedule are earned as before (daily reports and the weekly engineering and procurement update). Payment caps, milestone releases, retention and advance recovery are unchanged.

> **This changes the invoiceable figure** for projects that load updated schedules, as you chose.

### 5. Internal Reporting (was Progress releases)
- **Same report:** the v3.5 full-screen dashboard, with the same approval.
- **Starts from the latest updated schedule:**
  - internal planned and actual %
  - external (client) planned and actual % with the amounts
  - TCC, PAC and FAC forecasts
- **A banner** shows which schedule the report follows.
- **When you change progress or a milestone date by hand,** the report is marked **"Differs from the updated schedule"**, with each difference listed.
- **On submit,** the section manager is notified and the item shows in **Actions and approvals** with "validate the differences".
- **Before approving,** the section manager must tick **"I have checked these differences"** and write a note. The server refuses approval otherwise.
- **After approval,** the validation (who, when and the note) is kept with the report and cannot be changed.
- **A draft started before a newer schedule** offers **"Take progress and milestone dates from the updated schedule"**.

### 6. Client Reporting (new)
- **Where:** **Planning & Scheduling → Client Reporting**, weekly or monthly. It opens full screen.
- **Tabs:**
  - **Overview:** planned, actual, variance and SPI by client weightage; manpower.
  - **Progress by phase**
  - **Milestones:** TCC, PAC and FAC forecasts, and every milestone in the schedule.
  - **Look-ahead:** open activities in the next 30 days.
  - **Report notes:** summary, achievements, next period, issues and support required from the client, remarks.
  - **Approval**
- **Approval:** the regional planning section manager approves it for issue, with the same rules (differences validated).
- **Files for the client:** **Export to Excel** and **Print or save as PDF**. Drafts are marked DRAFT.
- **What it never contains:** internal weightage, management remarks or cost.

### Demo
- **Sample projects:** QOT and JBS now have phase weightage and an updated schedule. The other sample projects work as before.
- **Validation example:** QOT's submitted internal report differs from its schedule, to show the validation.

## Database: `schema-update-v15.sql`

**New tables:**

| Table | Holds |
|---|---|
| `project_phase_setup` | the weightage and mapping per project |
| `phase_setup_audit` | the history of changes (append-only) |
| `schedule_updates` | the updated schedules: the server works out the summary; append-only |
| `schedule_update_rows` | each activity of each update (append-only) |

**New functions:**

| Function | What it does |
|---|---|
| `phase_setup_save` | saves the weightage and mapping |
| `schedule_update_commit` | stores an updated schedule; the phase of each activity comes from the saved mapping; matched activities use the ProTrackAI baseline dates |
| `pt_sched_summary` | works out the summary of an update |
| `pt_rel_sched` | compares a report with the schedule and records the differences |
| `pt_rel_client_calc` | works out the client report figures |

**Updated:**
- **`release_act`:**
  - adds the `client` kind
  - writes the schedule figures itself (the app cannot hide a difference)
  - requires `validated` and `validation_note` to approve a report that differs from the schedule
- **`report_releases` gains** `sched_validated_by`, `sched_validated_at` and `sched_validation_note`, frozen once released, and the kind `client`.

**Nothing existing is removed and it is safe to run twice.**

**Rollback:** `schema-rollback-v15.sql` brings back the v3.5 rules and keeps every table, update, client report and validation, still readable.

## Validation rules (app and server)

**Internal weightage:**
- Seven known phases only, each 0–100%, adding up to 100%.
- A reason is needed once a schedule has been reported.

**Updated schedule:**
- **Who and when:**
  - Only the project's planning engineers or a super admin.
  - The tick box must say client or internal.
- **Dates:**
  - A valid data date, not more than a month ahead.
  - Weighted activities need planned dates.
- **Activities:**
  - 1 to 30,000 activities, each with an ID of up to 60 characters.
  - % complete between 0 and 100. Weights are not negative.
  - At least one weighted activity.
  - Every weighted activity mapped to a phase when the schedule is client-weighted and internal weightage is set.
- **Duplicates:** the same file twice is ignored.

**Reports:**
- **Client report:** actual % is required; planned and actual % are between 0 and 100; manpower is not negative.
- **Differences:** a difference is a % that differs by more than 0.05, or a TCC, PAC or FAC forecast date that differs.
- **Approving a report with differences** needs the check and a note of up to 1,000 characters.

## Workflow
1. **At project start,** the planning engineer saves the internal weightage.
2. **Each week or month,** the planning engineer uploads the updated schedule (client weightage), checks the mapping and results, and saves.
3. **The internal report and the client report** for the period start from that schedule. The planning engineer adds the remaining information and submits.
4. **If figures were changed by hand,** the regional planning section manager is notified and validates the differences when approving. The project manager review step (v3.5) still applies to internal reports when switched on.
5. **Once approved,** the executive report reads the internal report, and the client report is exported or printed for the client.

## Verified
| Suite | Checks | Result |
|---|---|---|
| Database: weightage, mapping, updated schedules and their formulas, append-only, reads, comparison with reports, validation, client reports, rollback (`test_v15.py`) | 76 | 76 pass |
| Earlier database suites (v13, v14) | 75 / 56 | all pass |
| Server mode end to end (v15 applied mid-run: weightage, upload, server and app figures match, invoiceable, validation, client report) | 208 | 208 pass |
| v3.6 in demo mode (`sched_demo.py`), app and demo page | 62 + 62 | all pass |
| Internal report dashboard / released reporting, app and demo page | 68 / 53 each | all pass |
| Issues / quantities / cost / documents / RASA / Tender / lifecycle / imports, app and demo page | 60 / 28 / 28 / 44 / 32 / 62 / 36 / 34 | all pass |
| Regression, demo date and live date (with your PE-329 XER) | 77 + 77 | all pass |
| Functional suites / formula reference / backup and restore | 59 / 23 / 10 | all pass |
| Demo page: regression and functional suites | 77 / 54 | one expected difference each, as before |

**Existing checks that changed, all because of intended changes:**
- **Renamed:** "Progress releases" is now "Internal Reporting", so two menu and wording checks were updated.
- **Project overview SPI:** the check now compares with the internal SPI when the project has an updated schedule.
- **Invoiceable:** the independent re-calculation now uses the schedule's % complete where loaded, as the new rule says.
- **Validation:** one approval in the v3.5 dashboard test now includes the validation, because QOT now has an updated schedule.

**Not verified here:**
- **Supabase itself and your live project.** The first upload on live.html is the real test.
- **Large schedules:** tested with small synthetic files. Your PE-329 file has 945 activities and was used for the existing baseline tests, not uploaded as an update.

## Still open
- **File types:** XER only for updated schedules. PMXML or Excel updates can be added.
- **Server backup:** includes the weightage, its history, the updates and their activities.
- **Phase weightage per period:** one set per project, with history. A change applies to future uploads; earlier uploads keep the weights they were worked out with.
