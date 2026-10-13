# ProTrackAI v3.5: the Project Performance Release Dashboard (October 2026)

Built from your specification of 13 October 2026, with your answers:
- **Internal progress is the headline.** It is calculated from the internal weightage loaded in P6 and agreed with management. External progress follows the client agreement weightage and is entered beside it.
- **Who approves:** each region's planning section manager reviews and approves that region's progress releases. A super admin can later add a project manager review before that, without any new release of the app.

## What changed

### Weekly and monthly progress releases open full screen
- **Where to find it:** **Planning & Scheduling → Progress releases → Open**.
- **Layout:** the release now fills the whole window instead of half. Monthly cost reports keep their own layout.
- **Tabs:** **Overview · Milestones · Progress · Manpower · Energization · Release notes · Approval**.
- **Buttons:** stay at the bottom of every tab: **Save draft**, **Submit for approval**, **Mark reviewed** (only when the project manager review is on), **Approve and release**, **Reject (return to planner)**.

### Executive KPIs at the top
Nine cards, each with a colour and a trend against the last released period (▲ improving, ▼ deteriorating, ■ stable):
- actual progress and planned progress
- progress variance
- SPI (internal, with external beside it)
- forecast completion
- manpower variance and utilization
- TCC status and PAC status
- energization status

The colours are green for on schedule, amber for at risk and red for delayed. The colour is never the only signal: the words are always shown.

### The tabs
| Tab | What is on it |
|---|---|
| Overview | **Project information:** data date, project number, sub project number, name, region, sector, contract value, project manager, planning engineer. **Milestones at a glance:** TCC, PAC and FAC. **Internal against external progress.** |
| Milestones | **Contractual:** commencement, site handover, original TCC, PAC and FAC. **Internal TCC target.** **Approved revised** TCC, PAC and FAC. **Forecasts:** internal forecast TCC; external forecast TCC, PAC and FAC. **Delays** are worked out automatically, with a traffic light each. |
| Progress | **External:** planned and actual amount (SAR) and %, with variance and SPI. **Internal:** the ProTrackAI figures, the figure used in this release, and the reason if you change one. Internal planned and actual amounts come from the contract value. |
| Manpower | Alfanar direct, indirect and subcontractor manpower, planned and actual. Totals, variance, utilization and productivity index. |
| Energization | TCC, PAC and FAC receipt dates. **Status:** Not Started, Under Testing, Ready for Energization or Energized. Forecast or actual date, and remarks. |
| Release notes | Progress summary, key issues and risks, recovery actions, next week or month target. Management remarks are added by the approver. |
| Approval | Revision, reason for the revision, released (submitted) by, reviewed by and approved by, each with the date. Who approves this project, and the full history. |

### Progress releases list
- **New filters:** **Region** and **Sector**.
- **New columns:** region and sector, and the **Data date**.
- **New card:** **Waiting for you** counts the releases you need to review or approve.
- **Unchanged filters:** project (the **Scope** selector at the top), period type (weekly or monthly) and the month or week.

### Executive report → Project view
- **New panel:** **Milestones, progress, energization and manpower**, as released.
- **Comments now also show** recovery actions and management remarks.
- **Critical projects:** a project whose TCC is more than 30 days late is now marked critical, with the reason "TCC N days late". This applies unless it is already critical for its finish date.

### Demo
- **New sample users:** two planning section managers.
  - **Faris Al-Zahrani** covers Central and Western.
  - **Ravi Shankar** covers Eastern and Southern.
- **Sample figures:** the sample releases now carry dashboard figures.

## Field classification

Key in the figures: the names below are what the server stores in `report_releases.figures`. Keys ending `_date` are dates and keys ending `_text` are text.

| Field | Key | Class | Who fills it |
|---|---|---|---|
| Data date | `data_date` (column) | Existing, read-only | ProTrackAI |
| Project number, name, region, sector, contract value | project record | Existing, read-only | Administration |
| Project manager, planning engineer | team | Existing, read-only | Administration |
| Sub project number | `sub_project_text` | **New**, editable | Planning engineer |
| Contractual commencement | `commence_date` | **New**, editable (starts from the project start) | Planning engineer |
| Site handover | `site_handover_date` | **New**, editable | Planning engineer |
| Original contractual TCC / PAC / FAC | `tcc_orig_date`, `pac_orig_date`, `fac_orig_date` | **New**, editable (starts from the project milestones) | Planning engineer |
| Internal TCC target | `tcc_int_target_date` | **New**, editable | Planning engineer |
| Approved revised TCC / PAC / FAC | `tcc_rev_date`, `pac_rev_date`, `fac_rev_date` | **New**, editable | Planning engineer |
| Internal forecast TCC | `tcc_int_fc_date` | **New**, editable | Planning engineer |
| External forecast TCC / PAC / FAC | `tcc_ext_fc_date`, `pac_ext_fc_date`, `fac_ext_fc_date` | **New**, editable | Planning engineer |
| TCC / PAC / FAC delay | `tcc_delay_days`, `pac_delay_days`, `fac_delay_days` | **Calculated**, read-only | Server |
| Internal TCC delay | `tcc_int_delay_days` | **Calculated**, read-only | Server |
| TCC / PAC / FAC receipt | `tcc_receipt_date`, `pac_receipt_date`, `fac_receipt_date` | **New**, editable | Planning engineer |
| Energization status, date, remarks | `energ_status_text`, `energ_date`, `energ_remarks_text` | **New**, editable | Planning engineer |
| External planned / actual amount (SAR) | `ext_plan_amt`, `ext_act_amt` | **New**, editable | Planning engineer |
| External planned / actual % | `ext_plan_pct`, `ext_act_pct` | **New**, editable | Planning engineer |
| External variance, external SPI | `ext_var_pct`, `ext_spi` | **Calculated**, read-only | Server |
| Internal planned / actual % | `planned_pct`, `actual_pct` | Existing, calculated by ProTrackAI. Editable only with a reason | ProTrackAI / planning engineer |
| SPI, design, procurement, forecast finish, workforce, productivity | `spi`, `eng_pct`, `prc_pct`, `forecast_finish`, `workforce`, `productivity_pct` … | Existing, calculated. Editable only with a reason | ProTrackAI / planning engineer |
| Internal variance, internal planned / actual amount | `int_var_pct`, `int_plan_amt`, `int_act_amt` | **Calculated**, read-only | Server |
| Manpower planned (direct, indirect, subcontractor) | `mp_dir_plan`, `mp_ind_plan`, `mp_sub_plan` | **New**, editable | Planning engineer |
| Manpower actual (direct, indirect, subcontractor) | `mp_dir_act`, `mp_ind_act`, `mp_sub_act` | **New**, editable (direct and subcontractor start from the last daily reports) | Planning engineer |
| Manpower totals, variance, utilization | `mp_tot_plan`, `mp_tot_act`, `mp_var`, `mp_util_pct` | **Calculated**, read-only | Server |
| Productivity index | `productivity_pct` | Existing, calculated (earned ÷ spent manhours, last 30 days) | ProTrackAI |
| Summary, key issues, next target | `narrative.summary`, `.issues`, `.next` | Existing, editable | Planning engineer |
| Recovery actions | `narrative.recovery` | **New**, editable | Planning engineer |
| Management remarks | `narrative.mgmt` | **New**, editable by the approver only, at approval | Planning section manager |
| Revision, reason for revision | `rev`, `revise_reason` | Existing, read-only | Server |
| Released (submitted) by and date, approved by and date | `submitted_by/at`, `approved_by/at` | Existing, read-only | Server |
| Reviewed by and date, review note | `reviewed_by`, `reviewed_at`, `review_note` | **New** columns, read-only | Server |

**Carried forward:** dates, external progress, energization, indirect manpower and planned manpower start from the last release. You only change what moved.

## Calculations
The app shows these as you type; the server works them out again on every save.

**Milestone delays (in days):**
- **TCC, PAC and FAC delay** = external forecast − approved revised date. When there is no revised date, the original contractual date is used.
- **Internal TCC delay** = internal forecast TCC − internal target. If there is no internal target, the revised TCC is used, then the original TCC.

**Traffic lights:**

| Colour | Status | Rule |
|---|---|---|
| Green | On schedule | 0 days or earlier |
| Amber | At risk | 1–30 days late |
| Red | Delayed | over 30 days late |
| Green | Received | the certificate has been received |
| — | Data unavailable | no dates entered |

**Progress:**
- **External variance** = actual % − planned %.
- **External SPI** = actual % ÷ planned %.
- **Internal variance** = actual % − planned %.
- **Internal amounts** = contract value × planned % and contract value × actual %.

**Manpower:**
- **Totals** = direct + indirect + subcontractor.
- **Variance** = total actual − total planned.
- **Utilization** = total actual ÷ total planned.

**Missing figures:** a figure that is missing stays empty ("—" or "Data unavailable"). It is never treated as zero.

## Workflow
1. **Planning engineer** prepares the release, saves it as a draft, then submits it.
2. **Optional:** if a super admin has switched on the project manager review, the **project manager** of that project marks it reviewed, or rejects it with a comment.
3. **Regional planning section manager** approves and releases it, adding management remarks, or rejects it with a comment. The Head of Planning and Cost Control and super admins can always approve.
4. **After release,** the version is frozen and the executive report reads it. A change needs a new revision with a reason, which goes through the same steps.

**Rules the server enforces:**
- Nobody approves or reviews a version they submitted.
- A planning section manager approves only projects in their region that they have access to.
- **Reject** returns the release to the planner as a draft. It needs a comment and is kept in the history.
- Monthly cost reports are unchanged: the Head of Planning and Cost Control approves them.

**Setting it up (super admin):** **Administration → Approval matrix → Progress release approval**:
- name one or more planning section managers per region
- tick the project manager review when management wants it

A region with nobody named falls back to the Head.

## Validation rules (app and server)
- External planned and actual % must be between 0 and 100.
- Amounts and manpower cannot be negative. Figures must be numbers and dates must be valid dates.
- Energization status must be one of the four values. "Energized" needs the energization date.
- Text fields are limited to 300 characters. Management remarks are limited to 2,000 characters.
- Actual progress must be entered. A changed ProTrackAI figure needs a reason (as before).
- Reject needs a comment. A new revision needs a reason.

## Database: `schema-update-v14.sql`

**New tables:**
- `release_approvers` (region, user)
- `release_settings` (the project manager review switch, off to start)

Signed-in users can read both. Only `release_setup` changes them.

**New columns on `report_releases`:** `reviewed_by`, `reviewed_at`, `review_note`. They are frozen once released, like the rest of the version.

**New functions:**

| Function | What it does |
|---|---|
| `pt_rel_plan_calc` | works out and validates the dashboard figures |
| `pt_rel_approver`, `pt_rel_decider`, `pt_rel_pm_review` | decide who approves and who reviews |
| `release_setup` | super admin only: add or remove a planning section manager, switch the review on or off |

**Updated:**
- `release_act`:
  - a new `review` action
  - approval by the regional planning section manager
  - management remarks (`mgmt`) at approval
  - the review step
  - calculated figures on save
- The read rule on `report_releases`: approvers and reviewers also see submitted progress releases of their projects.

**Nothing existing changes or is removed, and it is safe to run twice.**

**Rollback:** `schema-rollback-v14.sql` restores the v3.4 approval rules (the Head approves) and keeps every new table, column and figure.

## API changes (server functions the app calls)

**`release_act(p)`:**
- `action`: `save`, `submit`, **`review`** (new), `approve`, `return`, `revise`.
- `approve` accepts **`mgmt`**: management remarks, progress releases only.
- `figures` accepts the new keys listed above. The server overwrites the calculated keys with its own results.

**`release_setup(p)`** (new):
- `{action:'approver_add', region_id, user_id}`
- `{action:'approver_remove', region_id, user_id}`
- `{action:'pm_review', on:true|false}`

**Read access:** the app also reads `release_approvers` and `release_settings`.

**No new services:** no new outside service, key or data transfer.

## Verified
| Suite | Checks | Result |
|---|---|---|
| Database: dashboard figures, validation, regional approval, review step, set-up, frozen review, reads, rollback (`test_v14.py`) | 56 | 56 pass |
| Earlier database suites (v4, v10 to v13) | 125 / 51 / 46 / 44 / 75 | all pass |
| Server mode end to end (v14 applied mid-run: set-up, submit with server calculations, approval by the planning section manager, project manager review, executive report) | 193 | 193 pass |
| Dashboard in demo mode (`reldash_demo.py`), app and demo page | 68 + 68 | all pass |
| Released reporting / issues / quantities / cost / documents, app and demo page | 53 / 60 / 28 / 28 / 44 each | all pass |
| RASA / Tender / lifecycle / imports, app and demo page | 32 / 62 / 36 / 34 | all pass |
| Regression, demo date and live date (with your PE-329 XER) | 77 + 77 | all pass |
| Functional suites / formula reference / backup and restore | 59 / 23 / 10 | all pass |
| Demo page: regression and functional suites | 77 / 54 | one expected difference each, as before |

**Existing checks that changed, both because of intended changes:**
- **Test steps:** two existing tests now click the Progress and Release notes tabs before typing, because the fields moved into tabs.
- **Wording:** a progress release in the action list now reads "approve or reject" instead of "approve or return". Cost reports still say "return".

**Not verified here:**
- **Supabase itself and your live project.** The first release approved by a planning section manager on live.html is the real test.

## Still open
- **Planned manpower:** it is typed in. ProTrackAI does not import P6 resource loading.
- **Productivity index:** it is the existing ProTrackAI figure (earned ÷ spent manhours over the last 30 days).
- **Data date filter:** the data date is shown as a column. Filtering is by month or week, which sets the data date.
- **Reject:** returns the release to the planner. There is no separate "rejected for good" state, so nothing is lost.
- **Access for a planning section manager:** they need the region's projects (see STAGE-11-SETUP). A planning engineer account cannot be given whole regions.
