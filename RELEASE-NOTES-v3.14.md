# ProTrackAI v3.14: actual progress against the chosen baselines (October 2026)

## Internal and client reports: tick the baselines to compare with
A new card, **Actual against baselines**, is on the Overview tab of every internal report (Planning & Scheduling → Internal Reporting) and every client report (Client Reporting). It has four check boxes:

| Baseline | Where it comes from |
|---|---|
| Original baseline | the baseline the project was planned with (always available) |
| Revised baseline | Baselines and P6 import, when one is loaded |
| Recovery baseline | Baselines and P6 import, when one is loaded |
| Baseline assigned in the updated schedule | the baseline project exported with the updated schedule (XER); if the file carries none, the schedule's planned dates, and the card says which |

A baseline that cannot be used is greyed out with the reason. The reasons are:
- not loaded;
- no updated schedule for the period;
- the schedule was loaded before v3.14.

**For each ticked baseline the card shows:**

| Figure | Rule |
|---|---|
| Planned | the same activities and weightage as the report headline, with that baseline's dates, at the schedule data date: Σ weight × elapsed share of the baseline duration ÷ Σ weight |
| Actual, Variance, SPI | the report's actual; variance = actual − planned; SPI = actual ÷ planned |
| Baseline finish and forecast finish | the latest finish in that baseline against the report's forecast finish (internal) or TCC forecast (client), in days late or early |

The headline weightage depends on the report:
- **Internal reports:** internal weightage.
- **Client reports:** client weightage.

The original baseline gives exactly the headline's planned progress.

**Missing data:**
- An activity missing from a baseline keeps its original dates, and the card counts how many.
- Without the updated schedule's activity rows (they are kept for the two latest schedules of a project), the earned-value plan (budget weighted) is used and the schedule's own baseline is not available.

**Saving and approval:**
- Ticking updates the table at once.
- The choice and the figures are saved with the report, and at least one baseline must be ticked. The original is ticked by default.
- When the report is approved, the comparison is frozen: later baseline changes don't move it, and the check boxes lock.
- The client report's Excel (Summary sheet) and printed copy carry the comparison.

## The updated schedule keeps its own baseline
When a P6 XER exported **with its baseline** is uploaded (Baselines and P6 import → updated schedule):
- ProTrackAI reads only the schedule's own activities. Before, the baseline project's activities could be read as well.
- It keeps the baseline project's dates apart, as the *baseline assigned in the updated schedule*.

The baseline project is the one named in the schedule's `sum_base_proj_id`, or the copy made from it. Without a baseline project, the schedule's planned dates are kept. Schedules loaded before v3.14 don't have these dates.

## Monthly cost reports: out of Internal Reporting
Internal Reporting under Planning & Scheduling now has two tabs only: **Internal reporting** and **Client reporting**. Monthly cost reports are prepared and approved in **Cost Control → Monthly cost report**, as before.

## On the ProTrack server (live.html)
**Not sent to the server yet:**
- the comparison is shown and checked in the browser, but the release's baseline choice and figures (`bl_sel`, `bl_cmp`) are not sent;
- the updated schedule's own baseline dates.

The server needs an update for both, as for the contract breakdown earlier.

**Still available on the server:** comparison against the original, revised and recovery baselines, worked out in the browser.

**The v22 update is ready, not yet installed** (`supabase/schema-update-v22.sql`, STAGE-18-SETUP; it needs v17 only). Once it is in, live.html sees it (`bl_cash_features()`) and:
- **saves the comparison with the report.** An internal or client report's save goes through `release_act_bl`, which saves `bl_sel` and `bl_cmp` in the figures. The browser works out each baseline's planned % and finish. The server sets the actual, forecast finish, variance, SPI and days late or early from the report's own figures. Approval freezes the comparison with the released version, and Revise copies it into the new draft. A save with no baseline ticked is refused. `release_act` itself is not replaced, so v18, v19 and v20 keep their changes;
- **keeps the updated schedule's own baseline.** `schedule_update_commit` keeps each activity's `xbs` / `xbf` and the update's `bl_src`, so *Baseline assigned in the updated schedule* can be ticked on the server.

Until then, live.html behaves as above, with a one-line note on the card. Reports saved and schedules loaded before v22 have no saved comparison or schedule baseline; upload the XER again to add it.

**Not yet checked:** the SQL has not been run (there is no PostgreSQL on the build machine), and live.html has not been opened against the real server. The demo page behaves exactly as before.

## Demo
**Sample data:**
- a revised baseline for Riyadh-Qassim OHTL and Jubail 380kV, and a recovery baseline for Riyadh-Qassim OHTL;
- the baseline assigned in both sample updated schedules (BL1).

All of it is clearly marked sample. **Reset demo data** clears it.

## Checks
`tests/baseline_compare_demo.js` runs 18 checks in the browser console on the demo page. It covers:
- that the original baseline equals the headline (internal and client), and the revised-baseline formula;
- variance and SPI, and the reasons a baseline is unavailable;
- the earned-value fallback, and that choosing nothing is refused;
- the check boxes, live update, saving, and freezing at approval;
- the client card;
- an XER with and without a baseline project;
- that the cost reports tab has moved.

The 25 contract value checks, 24 Project Visual checks, 22 Tender checks and 17 project import checks still pass.
