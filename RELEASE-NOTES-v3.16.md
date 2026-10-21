# ProTrackAI v3.16: monthly invoicing on the cash-inflow forecast (October 2026)

Submitting an invoice every month for what the progress earns is a key figure for the project manager. **Invoices & Cash Flow → Cash-inflow forecast** now opens with a **Monthly invoicing** section, before the phase status and the cash-inflow table.

## Month by month
| Column | What it is |
|---|---|
| **Planned invoice** | the net invoice the **original baseline** earns in the month under the payment terms (phase caps and milestone releases, retention, advance recovery), with the advance at the contract start; the same plan as the cash-inflow baseline |
| **Invoiceable** | the same, on the **actual progress** reached by each month end (daily reports, and the updated schedule where loaded); past and current months |
| **Submitted** | the invoice register, by **submission date** (the invoice date for an older register without dates) |
| **Approved** | the invoice register, by **approval date** |
| **Submitted − invoiceable** | red when value was earned but not invoiced |
| **Forecast invoicing** | the balance of each phase on the latest updated schedule, from this month on |
| **Cumulative** | planned, invoiceable, submitted and approved |

A **To date** row sums the months up to this one.

## KPIs and chart
- **This month:** planned, invoiceable, and submitted (as a share of the invoiceable value; amber when nothing was submitted against invoiceable value).
- **Submitted to date:** against invoiceable and planned to date.
- **Approved to date:** as a share of submitted.
- **Months invoiced:** past months with invoiceable value in which an invoice was submitted, for example "7 of 7". The last months without one are named.
- **A bar chart** by month: planned, invoiceable, submitted, approved and forecast invoicing (up to six months ahead).

## Download
- **Download (Excel)** on the Monthly invoicing section, and **Export to Excel** at the top, give the same workbook: `Cash_inflow_forecast_<PE>_<date>.xlsx`.
- Its sheets are **Monthly invoicing** (all the columns above, with the to-date line and the months invoiced), **Cash inflow** (formerly Monthly) and **Phases**.

## Demo
Two quirks come from the sample data, not the method:
- The sample activities' original baseline starts in mid-2026, so the planned invoice is zero in the first months of the projects.
- Progress the sample carries from before the first daily report shows as invoiceable in the first month.

## Checks
`tests/cash_inflow_demo.js` now runs 28 checks (5 new):
- the Monthly invoicing sheet and its columns;
- submitted and approved to date against the register;
- planned to date against the baseline plan, and invoiceable never negative;
- the months-invoiced count;
- the page section with its chart and download button.
