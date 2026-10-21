# ProTrackAI v3.28.3: cost and billing figures only with the right to see them (October 2026)

A fix to the app's own rule: people without **See cost and billing figures** (`money.view`) never see a cost or billing figure. By default these are site engineers and site managers; foremen never have the right. Nothing changes on the server, and nothing changes for anyone who has the right.

## The problem

While the user guide was brought up to v3.28.2, a reading of the code found places where cost figures still reached site roles. Checked in the demo page as the site manager (Eng. Mansour Al-Qahtani), the site engineer (Eng. Omar Hassan) and the foreman (Rajesh Kumar), they were:

- **All reports → Full report pack** exported every report, not only those the role may open: the site manager's workbook had the EAC, Unit rate analysis, Invoiceable value and Invoicing and collection sheets, with every SAR figure.
- **Reports site roles may open by default** carried cost columns: *Progress by project* the labour budget (BAC) in SAR and CPI; *Progress by region* the contract value (SAR M) and CPI; *Early warnings* a Cost (CPI) warning with the forecast overrun in SAR. A super admin could also tick a cost report for a site role in Settings → Role access.
- **Live summary → Project view**: the Cost (CPI) gauge with EAC and VAC in SAR, and the contract value in the project line. The project list and *Critical projects* had a CPI column, a CPI under 0.95 flagged a project, and the SPI tile said *Ahead by SAR 16k*.
- **Dashboard**: the SPI tile showed EV and PV in SAR; *Project health* and the portfolio by region and sector had a CPI column; the region table showed the contract value.
- **Presentation** (site managers): the Unit rate analysis, Estimate at completion and Invoiceable value slides were offered, the KPI slide had a CPI card, and the Project health and region slides carried BAC, CPI and contract value.
- **Daily reports**: the new report form showed the *Labour cost*, and a report's subcontractor line showed its PO rate and cost (*SAR 190 per m³ = SAR 2k*), to foremen and site engineers.
- **Bottlenecks** (Live summary) and **RASA**'s report extracts took the same cost warning and report columns.

## The fix

Without the right to see cost and billing figures:

- **Reports.** The four cost and billing reports (EAC, Unit rate analysis, Invoiceable value, Invoicing and collection) cannot be opened, even when ticked for the role; Settings → Role access marks them. Every other report is built without its cost and billing columns (any amount in SAR, CPI, contract value, the Project list's expected value), on screen, in Excel and PDF, in the presentation and for RASA. The **Full report pack** holds only the reports the person may open.
- **Early warnings** leave out the Cost (CPI) warning, so Bottlenecks and the Live summary's *Main issue* do too. The notes say *Checks: SPI below 0.95*.
- **Live summary.** No CPI gauge, EAC or VAC, no contract value in the project line, no CPI column in the project list and *Critical projects*; CPI does not flag a project. The SPI tile says *Ahead of plan* or *Behind plan*.
- **Dashboard.** The SPI tile shows done and planned as percentages; no CPI column, no contract value by region.
- **Presentation.** The three cost slides are not offered, nor built if picked before; the KPI slide shows the *Progress variance* instead of CPI.
- **Daily reports.** No labour cost on the new report form; a subcontractor line shows its PO number, without the rate or the cost.

People with the right (super admin, executives, regional and portfolio managers, planning and costing engineers, project managers, read-only users by default, and anyone a super admin gives it) see exactly what they saw before.

## Not changed

- **BOQ Engine** shows estimated rates and amounts to anyone who can open it, whatever their right to see cost figures. By default only management, planning, costing and project managers open it. Left as it is, pending a decision.
- The Dashboard's *Risk* score still blends SPI, CPI and productivity into one number (no cost figure is shown).

## The user guide

`guide.html` is at v3.28.3: what's new, the Full report pack, who may open the reports and the presentation now say what is left out without the right. The rule *Site roles never see cost or billing* is unchanged.

## Checks

- **New suite `tests/money_view_demo.js`** (28 checks): the four cost reports closed even when ticked; the Full report pack only with the allowed reports and no cost column; the progress, region and Project list reports without BAC, CPI and values; RASA's extracts; Live summary, project view and Dashboard for the site manager and site engineer; the cost warning, bottleneck and flag with a CPI forced under 0.95; the presentation offered and built with every slide ticked; the new report form and the subcontractor line for the foreman and site engineer; Role access; and, for each, that a project manager (or a site engineer given the right) still sees the figures.
- **Every other browser suite passes on the changed page:** baseline comparison 18, BOQ Engine 53, BOQ sample 14, cash inflow 28, cash-out 27, cash-out on P6 24, contract value 25, presentation reports 16, delay correspondence 16, delay lists 15, delay register 26, E&P in reports 14, key milestones 20, margin and mail 17, project import 17, Project list 26, Project Visual 24, RASA modules 37, reporting status 28, Tender NOA 22, executive report status 11 (478 checks).
- **A sweep of every screen** in the menu of the demo site manager, site engineer and foreman, for every project scope, every report and every Performance tab, finds no SAR amount, CPI, EAC, VAC or contract value. The Python Playwright suites (`regression.py`, `suites.py`, `rights_demo.py` and the others) were not run: Python is not installed on the machine used.
