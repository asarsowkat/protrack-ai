# ProTrackAI v3.32: the Cashflow Dashboard (October 2026)

**Invoices & Cash Flow → Cashflow Dashboard**, right below the Invoice register, puts the money coming in and the money going out side by side, actual and forecast. It shows the net cash flow as a surplus or a deficit, and the **finance cost** of the deficit.

## Where the figures come from

| | Actual | Forecast |
|---|---|---|
| **Inflow** | Collections in the invoice register, by collection date | The cash-inflow forecast from this month (payment terms, updated schedule, payment period) |
| **Outflow** | Finance's cash-out movements, up to the last Finance import | The cash-out forecast after it (PO payment milestones, material POs on P6 dates, cost report heads, payables, other lines) |

**What the dashboard works out:**
- **Net cash flow** = inflow − outflow, shown green as a surplus or red as a deficit.
- **Cash position:** the running total of the net from each project's first month, including months before the period shown.
- **Uses existing data only:** the figures are the ones the two forecast pages already show. Nothing new needs to be uploaded.

## What you see

**Figures for the period:**
- inflow, outflow and net cash flow;
- the cash position at the end of the period;
- deficit months, with the lowest position and when it falls;
- finance cost, and net after finance cost.

**Chart:** inflow, outflow, net, the cash position, and the finance cost.

**Tables:**
- **Month by month:** each month shows which side is actual (A) or forecast (F), the rate, the finance cost and how many projects were in deficit.
- **By project:** tap a project to show only it.
- **By sector** and **by region.**

**Filters** (they combine):
- region, sector, project status, one project;
- the months from and to;
- actual and forecast, actual only, or forecast only;
- only the projects with both inflow and outflow data. This is the default; the other projects are named as left out.

**Export to Excel:**
- the monthly table;
- by project, by sector and by region;
- a project × month sheet (net and finance cost);
- the rates.

## Finance cost

Treasury funds a project's deficit and charges interest on it. A surplus earns nothing.

**The calculation:**
- A month's cost = deficit × rate ÷ 100 ÷ 12.
- It is worked out project by project, so one project's surplus never lowers another project's cost.

**The rates, set by the super admin** (in *Finance cost: interest rates* at the bottom of the dashboard):
- the interest rate of each month, in % per annum;
- a **forecast average** for the forecast period. It applies from this month to every month without its own rate. An earlier month without a rate has no finance cost, and the dashboard says so.
- **Interest on:** each month's deficit (the month's net outflow, the default), or the cumulative deficit (the running cash position).
- Every change is kept with who made it. Everyone else sees the rates, read only.

**On the demo page:** the rates are SAMPLE rates, labelled as such: 6.35% in January down to 6.05% in August, and a forecast average of 6%.

## Who sees it

Those who see both the cash-inflow and the cash-out forecasts: super admins, executives, regional and portfolio managers, project managers, planning and costing. Each sees only their own projects.

Site managers, site engineers, foremen and read-only users don't see it.

## RASA

- **New:** ask *"What is the finance cost on our cash flow?"* or *"net cash flow"*. RASA gives the next 12 months' inflow, outflow and net, the deficit months and the lowest cash position, the finance cost and the weakest project.
- **Unchanged:** *"cash flow forecast"* still gives inflow, outflow and the net.

## Server

`schema-update-v37.sql` (with `schema-rollback-v37.sql` and STAGE-31-SETUP.md):
- adds the screen `cfd` to Role access;
- adds the rates tables, readable by those who see cost figures and changed only through `cf_rates_set` (super admin);
- keeps every change in a history that cannot be changed.

It has not yet been run on a database.

## Checks

- **New suite:** `tests/cashflow_dashboard_demo.js`, 28 checks, all passing.
  - inflow and outflow equal the two forecast pages month by month;
  - the net and the cash position;
  - the finance cost on both bases, and project by project;
  - the rates and their checks, every filter, and the totals adding up;
  - the screen and the Excel export;
  - who sees it and who can change the rates;
  - RASA.
- **Existing suites:** all 23 pass (549 browser checks, plus the BOQ sample suite).
- **Smoke test:** 11 roles, 227 screens and 240 RASA suggestion answers, with no error and no blank value.
