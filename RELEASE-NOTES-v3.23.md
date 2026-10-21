# ProTrackAI v3.23: intermediate milestones and progress by phase (October 2026)

## Intermediate milestones from the P6 schedule

Internal and client reports → **Milestones** tab → **Intermediate milestones**.

Besides the contractual milestones, the planning engineer adds the milestones the project manager or the client asks for, such as design completion, civil start and civil completion. In **Add a milestone**:

| Field | What it takes |
|---|---|
| Milestone name | Up to 80 characters, unique on the project |
| Asked by | Project manager, client, or both |
| Shows in | Internal and client reports, internal only, or client only |
| Taken from | A **WBS element** of the schedule (main branch, or main › sub-branch), or an **activity or milestone** by its P6 ID |
| Start or finish | A WBS element gives its first start or its last finish. A P6 milestone uses its own date. |

A preview shows the baseline, forecast and delay before saving.

**Where the dates come from:**
- **Baseline:** the baseline dates of the schedule's activities.
- **Forecast and actual:** the updated P6 schedule in force at the end of the period. The client report uses the schedule with client weightage.
- **WBS start:** the first baseline start, and the first actual start once work has begun.
- **WBS finish:** the last baseline finish, the actual finish once every activity has finished, otherwise the last forecast finish.

**Delay and status:**
- Delay = forecast (or actual) − baseline.
- Status: on schedule, at risk (1–30 days), delayed (over 30 days), achieved, or achieved late.

**Where they show:**
- The list belongs to the project and appears in every later report.
- Each report keeps its own copy when saved, frozen at approval. Removing a milestone later does not change approved reports.
- They also appear in the executive report (project view) and in the client report's Excel (sheet *Intermediate milestones*) and printed copy.

**Who keeps the list:** the planning engineers of the project and the super admin. Every addition and removal is logged.

## Progress by phase

Internal report → **Progress** tab, and client report → **Progress by phase**.

Every phase is listed: general works, design, material, construction, installation, testing & commissioning, **energization** and project close out. Each row shows planned and actual % from the updated P6 schedule, the variance, the phase weight and its weighted share. A total row gives the overall progress.

| Report | Weighting | Overall |
|---|---|---|
| Client | The schedule's own (client) weighting, automatically | The client progress of the schedule |
| Internal | The **internal weightage set at the start of the project** (Baselines and P6 import) | Σ internal weight × phase % ÷ Σ weights of the phases in the schedule |

**Daily reports (internal report only):**
- Only the **site phases** are compared with the daily reports: construction, installation, testing and energization.
- The comparison uses the activities the two share, weighted as in the schedule.
- Colours: green within 2 points, amber within 5, red beyond.
- General works, design, material and close out come from P6 only.

The table is saved with the report and frozen at approval. It is also in the executive report (project view) and in the client report's Excel and print.

## Energization is a phase of its own

The internal weightage now has eight phases.

**Existing projects:**
- Their weights and mapping are unchanged.
- Energization has no weight until the planning engineer gives it one. Changing the weightage needs a reason, as before.
- New phase suggestions map "energization" to the new phase.

## Demo

- **Riyadh-Qassim OHTL and Jubail 380 kV** have five intermediate milestones each:
  - design completion
  - material delivery complete (internal only)
  - civil works start
  - civil works completion
  - installation completion
- Their updated schedules now carry actual starts, actual finishes and later forecasts for activities behind plan.
- One construction activity of Riyadh-Qassim OHTL is reported further in P6 than in the daily reports, so the comparison shows a difference.

## Server

`schema-update-v30.sql` (STAGE-26-SETUP.md), after v17 and v22. It adds:
- the `key_milestones` table and its audit;
- `key_milestone_act`;
- `pt_key_ms` and `pt_phase_tbl`, which work out the same figures on the server;
- `release_act_km`, which saves them with each internal and client report;
- energization in `pt_phases()`.

Until it runs:
- the live app cannot add milestones;
- live reports save without these tables.

Undo: `schema-rollback-v30.sql`.

## Checks

`tests/key_ms_demo.js` (17 checks) covers:
- the phases;
- the WBS start and finish rules and a P6 milestone picked by ID;
- the refusals, and who may keep the list;
- the internal and client weighting;
- the daily-report comparison of the site phases only;
- save, submit, approve and freeze;
- the executive report and the client report;
- versions saved before v3.23;
- adding and removing from the card.

These suites still pass:

| Suite | Checks |
|---|---|
| Baselines | 18 |
| Cash-out | 26 and 24 |
| Reporting status | 28 |
| Executive report | 11 |
| Project Visual | 24 |
| Contract value | 25 |
| Deck reports | 16 |
| Delay register | 26 |
