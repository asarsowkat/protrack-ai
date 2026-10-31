# ProTrackAI v3.41: the cost plan and the MER (Monthly Executive Report) (October 2026)

**Cost Control** gets two screens, and the monthly internal report gets an **Areas of concern** tab. Together they let ProTrack produce the company's **MER – Monthly Executive Report** (the PORTFOLIO COST STATUS REPORT, the DASHBOARD STATUS and the PLAN-006-FORM-01 page of each project) from what is already recorded in ProTrack, instead of filling the workbook by hand.

## Cost Control → Cost plan

Each project has a **cost plan for the year**, kept by its **costing engineer**:

- **Internal plan (I):** the planned cost of each month (SAR) on the budget the plan is made on, agreed with the **project manager**. Its monthly POC is the month's planned cost ÷ that budget; the page also shows the cumulative POC this year and the revenue by quarter (planned cost ÷ budget × contract value), as the company's COST PLAN (I) sheet.
- **Finance plan (F):** the conservative POC target given to Finance with **management's approval**: the target POC at year end (cumulative from the project's start), the planned POC % of each month and the approval reference. The page shows this year's target (target − POC at the end of last year) and checks that the monthly % add up to it, as the COST PLAN (F) sheet.
- **Actual and forecast:** the actual POC of each month comes from that month's released cost report; the costing engineer forecasts the months after the last one.
- **Year start:** the POC, budget and contract value at December of last year come from December's released cost report; without one, the costing engineer enters them (the DEC LAST YEAR sheet).

**Who:**
- the costing engineer of the project (Prepare monthly cost reports, with access to the project) or a super admin saves it;
- the project manager of the project marks the internal plan **Agreed**;
- the head of planning and cost control, an executive or a super admin marks the finance plan **Approved**;
- changing an agreed or approved plan returns it to **Draft**. Every save and decision is kept in the plan's history.

**Export the cost plans to Excel** writes COST PLAN (I) and COST PLAN (F) for the projects in scope.

## Planning → Internal Reporting → a monthly report → Areas of concern

Up to **three concerns** in each of five areas, each with **Action by** and **Action needed**:
- Design / Engineering
- Procurement
- Construction
- Resources
- Cost / Invoicing / Cash collection

A new month starts from last month's released concerns. **Fill from the issue register** puts the project's open issues (by impact) into the empty rows of their area, from the issue type: for example Delivery and FAT Test into Procurement, Funding and VO/EOT into Cost. The concerns are saved and approved with the report; the MER picks them from the released report. Weekly reports are unchanged.

## Monthly cost report: actual stock value

The cost report header has a new optional figure, **Actual stock value (SAR)**: material on site or in store that is included in the actual cost. The MER takes it out of the POC: cumulative actual POC = (actual cost − stock) ÷ current budget. It cannot be negative.

## Cost Control → MER – Monthly Executive Report

Choose the **cut-off month** (by default the latest month with released cost reports), the **cost plan** to measure against (Internal or Finance), and a region or sector.

**Cost (I) / Cost (F):** the overall portfolio, each region and each project, with:
- contract value, current budget, actual cumulative POC, P&L from the beginning of the year, contingency (Rev.00, available, utilized) and management reserve;
- KPI 1, gross profit %: Rev.00 and current budget, and the variance amount;
- KPI 2, the cost plan to the cut-off: planned and actual POC this year, and the variance amount on the budget;
- KPI 3, the year end: planned and forecast POC this year (actual + the forecast months), and the variance amount;
- KPI 4, cash flow: cash in and cash out to the cut-off, from the Cashflow Dashboard;
- KPI 5, invoices: cumulative approved invoices against the invoiceable value of the payment terms;
- KPI 6, site management: actual cost against earned value (actual progress × site management budget);
- with the finance plan: the POC at the end of last year, the target at year end, this year's target and the check.

Regions and the portfolio add up the amounts; POC is weighted by budget and gross profit by contract value, as in the company's sheet.

**Dashboard:** client, region, city, contract number, planned and actual %, start date, TCC / PAC / FAC (contract, revised, forecast), the EOT submitted and its days, revised contract value, advance, invoiced (excluding the advance), cash received, invoiceable % and amount, and the **areas of concern**.

**Project wise:** the PLAN-006-FORM-01 page: project information, progress by phase, schedule and claim status, commercial status, budget status by WBS head, manpower, areas of concern, the cost plan of the year (planned, actual, forecast and their cumulatives), POC for the year, cash status and site management analysis.

**Export to Excel** writes COST(I) or COST(F), DASHBOARD, one sheet per project and an About sheet.

A project without a released cost report, internal report, cost plan or invoice register says so on its row; the figures that need it show "—". **Who sees it:** those who see cost and billing figures (money.view), not the site roles.

## Sample data

The demo has **SAMPLE** cost plans for this year (labelled sample) and **sample** areas of concern in the released monthly internal reports. None of it is company data.

## Server

`schema-update-v45.sql` (with `schema-rollback-v45.sql` and STAGE-39-SETUP.md):
- the table `cost_plans`, read by those who see cost figures on their projects;
- `cost_plan_save` and `cost_plan_act`, with the same checks and rights;
- the screens `cplan` and `mer` join the role access list;
- the areas of concern and the stock value need no change: the server already keeps them with the report.

It needs v16. It has not yet been run on a database. Until it is, the live site's MER shows every figure that needs no cost plan, with a note.

## Checks

**New suite:** `tests/mer_demo.js`, 25 checks, all passing on the demo page. It covers:
- the menu and who sees the screens;
- the sample plans;
- the checks, and who saves, agrees and approves; back to draft after a change;
- the MER figures: POC without stock, KPI 2 and 3 on the internal and the finance plan, the finance check, gross profit, contingency, site management, the portfolio weighting;
- the stock value;
- the areas of concern: the tab, carried from last month, filled from the issue register, saved with the report, not on weekly reports;
- the three tabs and both workbooks.

The suites for money rights, contract value, the Cashflow Dashboard, RASA modules, key milestones, margin mail, supplements, reporting status, the executive report and the project list still pass. `ep_report_demo.js` stops at its check 8 on this demo date ("already released": it uses the fixed week 2026-W39), the same in v3.40.2.
