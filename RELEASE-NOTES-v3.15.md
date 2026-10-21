# ProTrackAI v3.15: invoices by phase with actual dates, and the cash-inflow forecast (October 2026)

## Invoice register: actual dates and the phase
**Template:** the template (Invoices & Cash Flow → Invoice register → Download template) now has these columns:

| Column | Notes |
|---|---|
| Invoice number, Invoice date, Type | as before (Progress, Advance, Retention release, Variation, Other) |
| **Phase** | for a progress invoice: Engineering and design, Procurement and supply, Construction and installation, Testing and commissioning (the payment-terms phases); empty for an advance or retention release |
| Invoice amount, Submitted amount | as before |
| **Submission date** | required for a submitted amount |
| Approved amount, **Approval date** | the date is required when an amount is approved |
| Collected amount, **Collection date** | the date is required when an amount is collected |
| Remark | |

**A row is refused when:**
- an approved or collected amount has no date;
- the invoice was approved before it was submitted, or collected before it was approved;
- an actual date is in the future, or not a valid date;
- the phase is not one of the payment-terms phases.

A register in the earlier layout (amounts only) still loads; each row notes that the invoice date is used.

**On the page:**
- The register shows the type and phase, and each amount with its date.
- **Invoicing status by phase**, also on the forecast page, shows:
  - **phase value:** the phase's share of the client contract value (original + changes approved by the client) by the P6 price weights;
  - **invoiceable to date:** from the payment terms;
  - **submitted, approved and collected:** from the register;
  - **outstanding:** approved − collected, plus submitted not yet approved;
  - **balance to invoice:** phase value − submitted;
  - the last submission, approval and collection dates.
- Advance, retention release, variations and progress invoices without a phase are listed apart.

## Cash-inflow forecast (Invoices & Cash Flow, no longer "planned")
**Who sees it:** costing, planning, project managers and management. Site roles and foremen don't. It is also linked from the Cost Control dashboard and the invoice register, and RASA points to it.

**The payment period** is a new payment-terms field, *Client pays within (days of submission)*, in Settings → Projects (default 60 days). Invoices are raised at month end and collected after this period.

**New project** (nothing invoiced yet): the complete inflow is estimated from the **client baseline** (original baseline dates) and the **contractual payment terms**:
- each phase is billed on progress up to its cap;
- its milestone releases come at the baseline TCC / FAC dates;
- retention and advance recovery are deducted from each invoice;
- retention is released at TCC and FAC;
- the advance is invoiced at the contract start.

If the project has already started but nothing is invoiced, what the baseline earned before this month is invoiced this month.

**Running project:**
- **Actual collections:** from the register, by collection date.
- **Outstanding invoices:** collected after the payment period from their submission date. An invoice already past its period is forecast in the first month and listed in the notes.
- **The balance of each phase** (phase value − submitted against it) is invoiced as the **latest updated schedule** earns it:
  - each activity moves from today's progress to complete between its forecast start and finish;
  - an activity not in the schedule follows the original baseline;
  - with no schedule loaded, every activity follows the original baseline from today's progress.
- **Releases:** milestone releases come at the schedule's TCC / FAC (or the actual date).
- **Progress invoices without a phase** are set against the phases in proportion to what each has earned.
- **Over-invoicing:** an amount invoiced beyond a phase's value is set against the other phases' balance.
- **The advance received** (or the terms' advance, if more) is recovered at the terms' rate.
- **Register amounts** are taken as invoiced to and paid by the client. The retention and advance already deducted from past invoices are worked out from the terms.

**The baseline plan** is always shown beside the forecast.

**The page shows:**
- **KPIs:** client contract value, collected to date, outstanding, next 3 and 12 months, balance to invoice, last inflow month;
- **a chart:** actual and forecast collections by month, with cumulative actual + forecast against the cumulative baseline plan;
- the invoicing status by phase;
- **month by month:** baseline plan, actual collected, forecast invoicing, forecast collection, both cumulatives;
- **notes:** for example no schedule loaded, past-due amounts, over-invoicing, advance recovery, missing collection dates.

**Export to Excel:** `Cash_inflow_forecast_<PE>_<date>.xlsx`, with Monthly and Phases sheets.

## On the ProTrack server (live.html)
**Needs a server update:**
- the new register columns: phase, submission / approval / collection dates;
- the payment period in the payment terms.

**Works on the server now:**
- the forecast, worked out in the browser from what the server holds;
- the amounts, the invoice date and the phase-less rows.

**The v22 update is ready, not yet installed** (`supabase/schema-update-v22.sql`, STAGE-18-SETUP; it needs v17 only). Once it is in, live.html sees it (`bl_cash_features()`) and:
- **keeps the new register columns.** The invoice register keeps `phase`, `sub_date`, `appr_date` and `coll_date`. `import_invoices` refuses the same rows as the upload page:
  - a missing date for a submitted, approved or collected amount;
  - approved before submitted, or collected before approved;
  - a future date (Saudi Arabia date) or an invalid date;
  - a phase that is not one of the listed ones.

  The app leaves out the date columns a file does not have, so a register in the earlier layout still loads. `invFromDb` reads the four columns, so the status by phase and the forecast use the actual dates on the server too;
- **checks the payment period.** It must be a whole number of days from 0 to 365 (blank = 60).

Until then, live.html behaves as above, with a one-line note on the register. Registers loaded before v22 have no phase or dates; upload the register again.

**Also fixed in live.html (does not wait for v22):** **Save payment terms** now saves to the server straight away, with the payment period. Before, in live.html, the payment terms were not sent to the server until the project itself was saved, so a reload could show the server's older terms.

**Not yet checked:** the SQL has not been run (there is no PostgreSQL on the build machine), and live.html has not been opened against the real server. The demo page behaves exactly as before.

## Demo
- **Sample invoices:** each gets a phase and sample actual dates (approval about 3 weeks after submission, collection about 7 weeks after), never later than today.
- **Created on first open:** sample invoices are now created when the invoice register or the forecast is opened, not only from Performance.

## Checks
`tests/cash_inflow_demo.js` runs 23 checks in the browser console on the demo page. It covers:
- the template columns;
- row rules, and the earlier layout;
- the status by phase against the register, and phase values against the client contract value;
- actual collections by date, outstanding after the payment period, the balance invoiced from this month on;
- the baseline plan totalling the contract, and following the updated schedule;
- the payment-period effect, and the new-project estimate;
- the page and the export, the menu and rights, and the payment terms field.

The 25 contract value, 24 Project Visual, 22 Tender, 17 project import and 18 baseline checks still pass.
