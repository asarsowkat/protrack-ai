# ProTrackAI v3.20: the cash-out forecast (October 2026)

**Invoices & Cash Flow → Cash-out forecast** forecasts each project's cash-out against its **approved current budget**. The budget is the control limit.
- **Finance's actual cash-out** is recorded exactly as sent.
- **The remaining PO payment obligations** and the other approved cash-out are forecast on their expected dates.
- **The forecast at completion** is reconciled with the budget.
- **An overrun** is shown, never hidden, and needs a documented management review.

## Where the figures come from
| Figure | Source |
|---|---|
| **Approved current budget** | The *Approved budget* (Rev-0 + approved supplements) of the latest monthly cost report released up to the reporting cutoff. The released cost reports are its revision history. No released cost report: **Budget Not Configured**. PO values are never used as a budget or added to it |
| **Actual cash-out** | Finance's **cumulative** cash-out per project and month, imported from Excel. Monthly actual = this cumulative − the previous one. The first balance is an *opening balance* unless a zero opening is verified |
| **Forecast remaining** | The unpaid net amount of every PO payment milestone, at its expected payment date, plus the remaining amount of the *other cash-out lines* (cash-out in the budget that no PO covers) |
| **Forecast at completion** | Actual cumulative at the cutoff + forecast remaining. Never the PO total |
| **Planned (baseline)** | Each milestone at its first approved payment date, and each other line's original plan |

**Statuses**, in this order:
- **Budget Not Configured**
- **Actual Overrun:** actual above the budget. This takes priority, even when the forecast is incomplete.
- **Forecast Overrun:** forecast at completion above the budget.
- **Forecast Incomplete:** a PO without payment terms, milestones not totalling 100%, a missing payment date, or no Finance import.
- **Reconciliation Required:** a negative movement, a missing month, unallocated actual cash-out beyond 1% or SAR 100k, a PO value changed without a revision record, or a possible duplicate PO.
- **Within Budget**

Money is added in whole halalas, so totals are exact. Every figure is in SAR; no other currency is combined.

## The screen
- **Overview:**
  - the status, with a red alert for an overrun stating the amount and percentage, and whether the management review is recorded
  - eight KPI cards: approved current budget, actual cumulative, forecast remaining, forecast at completion, headroom / overrun, forecast utilization, outstanding PO obligations, reconciliation status
  - charts: monthly planned / actual / forecast with the cumulative lines and the budget; approved budget against forecast at completion
  - the monthly table; the data-quality exceptions
- **PO payment schedules:**
  - every PO of the project (from Subcontract purchase orders, linked to Material tracking by PO number): original and current value, status, milestones and their total, paid (verified), outstanding, next payment, checks
  - **Open** a PO to keep its payment terms, as below
  - a chart of the forecast payments by month and by PO
  - **Other cash-out lines:** paid to date (with its Finance reference), remaining, months; each confirmed as not covered by a PO
- **Finance actuals:**
  - the import (super admin and Head Office cost control coordinator)
  - the opening balance setting
  - every cumulative balance with its monthly movement and checks
  - the upload and correction history
- **Reconciliation:**
  - actual against plan and against the latest forecast, month by month
  - paid milestones, other lines paid, **unallocated actual cash-out**
  - remaining obligations (overdue ones flagged)
  - the budget history (released cost reports), headroom or overrun
  - the audit trail
- **Versions and scenarios:**
  - forecast versions (draft → reviewed by someone else → published by the Head or a super admin)
  - the management review of an overrun
  - the comparison: original baseline, previous and latest published, latest draft, live forecast, actual; with the trend chart
  - scenarios: Base, Optimistic, Pessimistic and user-defined, clearly labelled *simulations*
- **Portfolio:** every project in your access, with totals.

## PO payment terms and milestones
- **Fields per milestone:**
  - name and payment term (advance, drawings, manufacturing progress, FAT, dispatch, delivery, installation, testing and commissioning, taking-over, retention, final payment, progress, custom)
  - **% of the PO value** or a **fixed amount**, and the event
  - planned milestone date, expected invoice date, **contractual payment days**, expected payment date (computed, or set)
  - retention or deduction, status (Planned, Invoiced, Paid, On hold, Cancelled), paid date and amount, **evidence**, notes, approval
- **Standard schedule:** 10 / 20 / 20 / 40 / 10 (advance, drawings, delivery, installation, retention) for a PO without terms.
- **Rules:**
  - the milestones must total 100% of the current PO value, or the forecast is incomplete
  - a paid milestone needs its payment date and Finance evidence
  - what was paid cannot be changed by changing future assumptions; only an approver can, with a reason
  - changes are *Draft* until the costing coordinator, the Head or a super admin approves them; the first approved payment date is the milestone's baseline
- **PO revision:** record it with its reference, date and reason. It updates the PO register and keeps the original value.
- **Cancelled PO:** needs a reason, and its unpaid obligations leave the forecast.

## Finance Excel import
1. Choose the **projects** the file covers and the **reporting cutoff**.
2. **Choose file:** the template (`Finance_cumulative_cash_out_template.xlsx`) or Finance's own layout.
   - The columns are recognised by their headers, or **mapped** by hand and saved for next time.
3. **Preview:**
   - each row is *New*, *Restatement*, *Already imported* or *Refused*, with its checks
   - refused rows: unknown project, a project not chosen or not in your access, a period after the cutoff or not a month, a cumulative that is not a number or is negative, another currency, the same period twice
   - warnings: a negative movement, missing months, a back-filled period, a different project name
4. **Import:**
   - refused rows need the acknowledgement
   - a **restatement** needs *Record them as corrections* and Finance's reason; the original is kept, marked superseded
   - the same file twice, or a file with nothing new, is refused
   - each import is numbered (FCO-0001…) and listed in the Import centre

Finance never signs in. The figures are project-level. They are never shared out among POs; the difference with the paid milestones and other lines is shown as **Unallocated actual cash-out**.

## Reports
- **Export to Excel:** `Cash_out_forecast_<PE>_<cutoff>.xlsx`, with these sheets:
  - Summary, Monthly cash-out, Actual vs plan, Reconciliation, Budget
  - PO payment schedule, Other lines, Uploads and corrections, Version comparison, Exceptions
- **Export to PDF:** key figures, monthly cash-out, budget history, PO payment schedule and exceptions.
- **Portfolio:** an Excel with every project in your access.
- **Every report states:** the project, reporting cutoff, currency, approved budget revision, forecast version and generation time. The figures are the screen's.

## Rights
| Who | Can |
|---|---|
| Super admin, Head Office cost control coordinator | Import and correct Finance actuals; verify a zero opening; approve payment terms; review versions |
| Head of Planning and Cost Control, super admin | Publish versions; record the management review of an overrun |
| Costing engineers (right *Keep the cash-out forecast of their projects*, set in Roles and rights) | Keep payment terms, other lines, scenarios and draft versions of their projects |
| Project managers, management, planning, read-only | See the projects in their access |
| Site roles, foremen | No access |

## Demo
- **Finance actuals:** every project has Finance cumulative actuals to August 2026.
  - Riyadh Metro has a verified zero opening.
  - Riyadh-Qassim's first balance is an opening balance.
  - Jeddah DC has a June restatement with its reason.
  - Ras Tanura is missing April.
- **Payment terms:**
  - every PO has 10/20/20/40/10 terms, with the past milestones paid and evidenced
  - Riyadh-Qassim's PO-2026-051 has no terms
  - Riyadh Metro's installation is forecast 30 days after its baseline
- **Other cash-out lines:** cover own manpower, overheads and materials.
- **Result:**
  - Riyadh Metro, Jubail and Jazan are within budget
  - Jeddah DC is a **Forecast Overrun** (104%) awaiting the management review
  - Riyadh-Qassim is **Forecast Incomplete**
  - Ras Tanura is **Reconciliation Required** (SAR 2.5M unallocated, missing April)
- **Versions:** Riyadh Metro has a published July version, the original baseline.

## Checks
`tests/cashout_demo.js` runs 26 checks in the browser console on the demo page.
- **The 12 acceptance tests of the specification:**
  - within budget (191M, 9M, 95.5%); overrun (206M, 6M, 103%, not reduced; management action)
  - actual overrun (205M kept, 5M); PO commitments not added to the budget
  - milestones 10/20/20/40/10 of SAR 1M; cumulative 20/35/53/66M → 20/15/18/13M
  - duplicate upload; approved correction; missing budget
  - no false PO-level actuals; no double counting; project access
- **Workflows:**
  - only the uploaders import; row checks; column mapping
  - payment terms totals; evidence; paid milestones locked
  - versions and the overrun review; a new version keeps the published one
  - scenarios as simulations; the Excel and PDF reports; the menu and the right

The delay register (26) and presentation (16) checks still pass.

## Server
`schema-update-v27.sql` (STAGE-23-SETUP.md) adds:
- the tables, with their read rules and append-only guards
- the right `cashout.keep` and the screen `cout`
- `cashout_act`, which re-checks every rule and right on the server

The forecast itself is worked out in the page from the stored records and the released cost reports. Undo: `schema-rollback-v27.sql`, which keeps everything. The SQL has not been run on a database yet.
