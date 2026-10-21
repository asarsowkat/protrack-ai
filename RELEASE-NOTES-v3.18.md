# ProTrackAI v3.18: reports in the presentation, and as Excel (October 2026)

**Reports & Dashboards → Presentations** keeps its slides and now has a **Reports** group.

**How it works:**
- Choose the **month** and **one project** or **every project in the scope**.
- Tick any of the reports below; each opens its parts, all ticked by default.
- A part you untick is left out.

| Report | Parts |
|---|---|
| **Internal report** | headline figures (planned, actual, SPI, forecast finish, design, procurement, internal amounts, workforce), against the baselines, contract milestones, manpower, open issues as released, comments and remarks |
| **Productivity details** (for the scope) | by activity (planned against actual rates), by foreman over the last 30 days, chart |
| **Client report** | headline figures, against the baselines, progress by phase, milestones, look-ahead, contract value (client-approved only), report notes |
| **Invoicing and cash flow** | invoicing KPIs, monthly invoicing (planned, invoiceable, submitted, approved), invoicing status by phase, cash inflow month by month, charts |
| **Cost report** | headline figures, by WBS head with the contract value and margin by column, billing to date |
| **Change order details** | summary, every change order and claim (client approved price, considered internally with WF), contract value breakdown |

**Which version is used:**
- The internal, client and cost reports use the **released** version for the month, else the open draft, marked **DRAFT**.
- Invoicing and cash flow come from the invoice register and the cash-inflow forecast (v3.15–3.16).
- Change orders come from the log up to the month.

## Downloads
- **Download PowerPoint:** the chosen slides, then each report as a section (a divider slide, then its KPIs, tables, text and charts). Long tables continue on further slides with their header repeated. *Include charts as pictures* applies to the report charts too.
- **Download the reports as Excel:** `ProTrack_reports_<project or portfolio>_<month>.xlsx`, one sheet per report and project (for example *Internal PE-120*, *Invoicing PE-120*), with every block's title, table headers and rows.

## Rights
- Invoicing and cash flow, the cost report and the change order details are offered only to roles that see cost figures.
- The internal and client reports follow the same visibility as on their pages.

## Checks
`tests/deck_reports_demo.js` runs 16 checks in the browser console on the demo page. It covers:
- the Reports group and parts;
- one section per report and project, and every project in the scope;
- the internal report, client report, invoicing and cash flow, cost report with margins, the change order log, and productivity;
- unticked parts being left out;
- the Excel sheets and their contents, and the slides added to the PowerPoint;
- rights.

The 17 v3.17 margin and email checks also pass on the combined pages.

## Server
No server change is needed: the sections are built in the browser from what the page holds. The v23 server update (report email lists and margins by column) is included in these pages; its SQL hasn't been run on a database yet.
