# ProTrackAI v3.48: Client Invoice Builder (November 2026)

Monthly client invoices were prepared by hand: planning, cost control and the project team copied P6 progress into the client's invoice workbook item by item. v3.48 builds the invoice from three records ProTrackAI already holds or can hold: the approved **contractual price schedule (Schedule-C)**, the **progress of the updated P6 schedule**, and the **previous certified invoice**. It applies the contract's invoicing rules, checks the result, and produces the invoice workbook in the client's layout.

It sits under **Invoices & Cash Flow**, beside the invoice register, and uses the same projects, rights, schedules, milestones and design. The full design (functional specification, user stories, schema, API, screens, engine, validation matrix, AI review, dashboards, notifications, architecture, roadmap, test cases, acceptance criteria) is in **CLIENT-INVOICE-BUILDER-SPEC.md**.

The reference price schedule and client invoice you provided were used **for their structure only**: the column layout, the item numbering, the "Not Applicable" and "Included in Item …" rows, the 80% / TCC / FAC split, the 90/10 material split, the cover, summary, breakdown, retention, advance and forecast pages. None of their amounts, names or percentages is a default anywhere. Defaults come from the project's own payment terms. The demo's price schedule is **made from the demo schedule and labelled SAMPLE**.

## The screen (menu → Invoices & Cash Flow)

Three menu entries open the builder: **Client Invoice Builder** (the dashboard), **Schedule-C mapping audit** and **Client invoices**. Cashflow Dashboard stays right below the Invoice register. The builder has six tabs:

- **Dashboard**
  - Client invoice dashboard: contract value, certified to date, current claim, retention held, balance to bill, forecast for the next three months, days since the last invoice, and outstanding amounts.
  - Schedule-C health: items mapped, unmapped %, value coverage and an invoice risk score (0 to 100, with its formula shown).
  - Invoice readiness: approved Schedule-C, progress updated, every item mapped or reviewed, supporting documents, the review run, no blocking exception. It shows a "ready %".
  - **Waiting for you**: invoices to review, approve, issue or certify, and Schedule-C revisions to approve. The tab shows a count.
  - Portfolio: every project you can see, with its Schedule-C, coverage, risk, last invoice and open invoice.
- **Schedule-C**: upload, header, invoicing rules by component, items. Revisions with Draft → Approved → Superseded.
- **Mapping audit**: Item | Description | Contract value | Rule | Activities | Status (Mapped, Missing, Reviewed, Milestone), the "⚠ N price schedule items not mapped" alert, and reading the P6 code.
- **Client invoices**: preparing an invoice, loading the history of a running project, and each invoice with its workflow.
- **Forecast**: expected billing and collection by month.
- **Audit trail**.

## New project: the Schedule-C

1. **Upload** the contractual price schedule (XLSX, XLS or CSV). ProTrackAI finds:
   - the header row (Item Number, Line Type, Short and Long Description, Qty, Unit, Unit Price, Total Cost);
   - the sheet with the most priced items.

   It then reads every item:
   - item numbers such as `A.SS.4.1.2.2`, cleaned of stray spaces;
   - the parent of each item, from its number;
   - "Description" headings and "Breakdown" priced items;
   - "Not Applicable" items;
   - "Included in Item …" items, including the misspelt "Included in tem …";
   - the price component, from the heading the item sits under: General, Engineering & design, Equipment & materials, Construction, Installation, Testing & commissioning or Close-out.

   Duplicates, an item that is "included in" an item the schedule does not have, and a heading that carries a value as well as priced items under it are listed as notes.

   Tested on your reference price schedule: the 132 priced items add up exactly to the file's total row. The test printed counts only.
2. **Header**: contract number, title, client, issue date, approved contract value, currency (SAR), VAT %, payment period, retention (% of each invoice, cap, release at TCC and FAC), advance (% of the contract value and % recovered from each invoice). Pre-filled from the project's payment terms.
3. **Approve**: each upload is a draft revision; a person with `cib.approve` approves it, never the person who uploaded it. Approving a new revision supersedes the previous one. If the items do not add up to the approved value, the approver must give a reason.

## Invoicing rules

Set per price component, and per item where an item differs:

1. **Percentage of progress**: a share billed on progress (for example 80%), released at TCC and at FAC; the three add up to 100%.
2. **Split**: a share on progress (for example 90% on material delivery), the balance at FAC.
3. **Payable at TCC**.
4. **Payable at FAC**.
5. **Engineering phase billing**: phases (Phase I, II, …), each with its own % of the item and the P6 activity that completes it. Project-specific percentages; they must add up to 100%.

Each item also has an **invoice limit** (% of its value); a claim stops at the limit and is flagged.

## P6 mapping

- The P6 activity code **"Schedule C"** holds each activity's item number. It is read **automatically when an updated schedule is loaded** (Planning → updated schedule), or from an XER in the mapping audit. Mappings read from P6 replace the earlier P6 mappings; mappings added by hand stay.
- The **mapping audit** shows every priced item as Mapped, Missing, Reviewed (unmapped but reviewed) or Milestone (rules 3 and 4). It also shows:
  - the missing value and its %, the coverage and the risk score;
  - activities whose code is not in the price schedule;
  - weighted activities without a code;
  - mapped activities that are no longer in the schedule.
- An unmapped item is either mapped (by its P6 code, or by hand to an activity of the updated schedule), or **reviewed**:
  - "no work yet": nothing is billed until it is mapped;
  - "bill on a stated %": allowed only with a written reason and evidence, flagged on the invoice and in the review.
- **No invoice is submitted while an item is Missing.**

## Progress and the invoice

- **Progress** of an item = the weighted % complete of its mapped activities in the updated schedule in force at the period end. The activity weight is the schedule's client weight; activities without a weight count equally. Progress is never typed; the only exception is a reviewed, unmapped item, which is flagged.
- **Each line**: previously certified, this period and cumulative, each as an amount and a %, with the progress source (the P6 activities, the phase steps, the milestone, or a typed %).
- **Totals**:
  - gross this period;
  - retention, up to its cap, and its release at TCC and FAC;
  - advance recovery, until the advance is repaid;
  - net payable;
  - VAT;
  - total with VAT;
  - certified to date and the balance.
- **The next invoice** starts the day after the previous one, from the **client's certified figures** (not the amounts claimed). Its number follows the last one.

## Running projects: the latest client invoice

Load the last certified client invoice workbook (Excel):
- ProTrackAI finds each breakdown sheet with item numbers and picks the certified-to-date column of each sheet (Payment certified › Cumulative › Amount). You can change or skip any sheet.
- It matches the item numbers to the Schedule-C, including short numbers such as `2.1.1.1`. An item that appears on two sheets (Material and Material 90-10) is counted once.
- You confirm the invoice number, the period, the retention held, the retention released and the advance recovered to date.

The history is stored as a certified invoice. The next invoice continues from it: for example, after Invoice #08, the next is #09 and claims the difference.

A PDF's tables cannot be read reliably. Keep the PDF in the document rack as evidence, and either load the Excel workbook or type the certified amounts per component (spread over the items by value).

## Exceptions

**Blocking** (the invoice is not submitted):
- an unmapped item;
- no updated P6 schedule for the period, or one older than the period start;
- certified to date above the contract value;
- an earlier invoice not yet certified;
- a period that overlaps another invoice (a duplicate claim);
- an unapproved Schedule-C revision.

**To check**:
- an item at its invoice limit (over-claim stopped);
- schedule reversal: progress below what was already certified. The certified amount is kept and nothing is claimed;
- items billed on a typed %;
- codes not in the price schedule;
- items certified before but no longer in the revision;
- items that do not add up to the contract value;
- the month's internal progress report not yet released;
- nothing to claim.

## Review invoice

"Review invoice" runs a **rules-based review in ProTrackAI**. It checks:
- **mathematical accuracy**: every line worked out again from P6, the rules and the previous certificate; the totals, retention, advance and VAT;
- **contract compliance**: retention without a contract term, advance recovered beyond the advance, items at their limit, milestone items needing their certificate;
- **missing Schedule-C items** and **unmapped activities**;
- **abnormal progress**: jumps above 35 points a month, reversals and typed %;
- **over-billing risk**: billed beyond physical progress, and billing to date ahead of the schedule;
- **high-value lines**: any line above 15% of the claim;
- **forecast impact**: the claim against the month's forecast, and when the balance is billed.

It gives a score out of 100 and its findings. An invoice is submitted only after the review has run on its current figures.

A language model on ProTrack's server **stays on hold** until alfanar IT and Cybersecurity approve it (see STAGE-44-SETUP); this review needs none.

## Workflow and separation of duties

**Draft → Submitted → Reviewed → Approved → Issued → Certified → Paid.** An invoice under review or approved can be returned to Draft with a reason. A draft, or an invoice under review, can be cancelled with a reason. An issued invoice is never cancelled: the client certifies it or rejects it with a credit note.

- **Prepare, recalculate and submit**: `cib.prepare` (costing and planning engineers by default).
- **Review**: `cib.review` (project managers). Nobody reviews an invoice they prepared.
- **Approve**: `cib.approve` (regional managers, and the Head of Planning and Cost Control through the position). Nobody approves an invoice they prepared or reviewed. Every supporting document must be marked attached or not applicable first. The nine documents follow the client's attachment list:
  - payment approval and forecast;
  - summary and Schedule-C breakdown;
  - material certificates;
  - progress reports;
  - spare parts;
  - training;
  - contractor certificates (Zakat, VAT, GOSI, salary);
  - insurance;
  - completion certificates.
- **Issue**: `cib.prepare` or `cib.approve`, with the issue date.
- **Certificate and payment**: `cib.certify` (costing by default; give it to finance):
  - the client's certificate, as claimed or with the amounts the client certified per item (never more than claimed). Retention, the advance and VAT are then worked out on the certified amounts;
  - the payment (never more than the total with VAT).
- **Schedule-C and mapping**: `cib.setup` (costing and planning) and `cib.map` (planning). Foremen never see client invoices; read-only users see them.

## Cash flow

- An issued invoice joins the **invoice register** as a progress invoice: submitted on its issue date, certified with the client's amount, collected when paid. The uploaded register keeps its own rows; a row with the same number wins.
- So the Cash-inflow forecast, the Cashflow Dashboard, the cost report's billing and the client report's invoices page all use it.
- The **Forecast** tab gives expected billing, retention, its releases, advance recovery, net, VAT and the collection month, month by month to the finish. It spreads the remaining progress of each mapped activity evenly to its P6 forecast finish and applies the rules, with TCC and FAC at their forecast dates.

## The invoice workbook (Excel)

**Excel invoice** produces, in the client format's layout:
- Cover (contract value, change orders, invoiced to date and previously, remaining, this invoice, retention, advance deduction, net, VAT, total);
- Invoice summary (by price component, with the payment rule; previously, this period and to date);
- one breakdown sheet per component (General, Engineering, Material, Construction, Installation, Testing & Commissioning, Close-out), each with:
  - the contractual columns;
  - certified progress (previous, new and cumulative);
  - payment certified (previous, new and cumulative);
  - the SAP entry ratio.

It also includes Retention, Advance recovery, Forecast (previous, present and forecast invoices), **SAP upload** (item, ratio, this period, cumulative), Exceptions & review, and Audit.

A draft is marked "not approved for issue". Exporting marks the summary and breakdown document as attached.

## Audit trail

Every action is recorded with who, when, and the values before and after:
- Schedule-C uploads, approvals and header, rule and item changes;
- mapping read from P6 or changed by hand;
- mapping reviews;
- invoices prepared and recalculated;
- reviews run;
- documents;
- submit, review, approve, return, issue, certificate, payment and cancel.

On the server the trail is append-only.

## Server (schema-update-v51.sql, STAGE-45-SETUP)

- **Tables**:
  - `cib_schedules` and `cib_items`: revisions and items;
  - `cib_maps` and `cib_map_reviews`: the mapping and its reviews;
  - `cib_invoices`;
  - `cib_audit`: append-only.

  All tables have row level security: billing figures and project access are required to read. Nobody writes them directly.
- **Every write** goes through `cib_act(p)`. **The server works the invoice out itself** from:
  - `schedule_update_rows` and the mapping (`pt_cib_prog`);
  - the rules (`pt_cib_pay`);
  - the TCC and FAC actual dates in `milestones`;
  - the previous certified invoice.

  It never takes amounts from the browser. It checks every right, the separation of duties and every state change. Before submitting, it recalculates the invoice and refuses it if the figures changed or anything blocks.
- **Tests**: `supabase/tests/test_v51.cjs`, 85 checks on PGlite (schema.sql and every update to v51, v51 twice, rollback and reinstall), all passing. It has **not yet been run on Supabase**: run it on a staging copy first.

## Not in this release

- A language model for the review (on hold for alfanar IT).
- Reading PDF invoices' tables.
- Arabic text on the invoice pages.
- Automatic e-mail or Approval Hub routing of invoices; today, the "Waiting for you" list and its count on the Dashboard tab show each person what is due.
- Variation orders as Schedule-C items: a new revision covers them today.
- Bulk loading of many projects at once.

All are listed in the specification's roadmap.

## Tests

- `tests/client_invoice_builder_demo.js`: 27 checks in the demo page, covering:
  - the menu, rights and screen;
  - the SAMPLE data;
  - reading a Schedule-C;
  - the five rules;
  - weighted progress;
  - revisions and approval;
  - mapping on schedule load;
  - history;
  - unmapped blocking and the review of an unmapped item;
  - the line and total arithmetic;
  - exceptions;
  - the review;
  - the workflow with separation of duties;
  - the register;
  - a certificate with changes;
  - the payment;
  - the next invoice;
  - cancelling;
  - the forecast;
  - the Excel workbook;
  - the audit trail;
  - permissions;
  - every tab.

  All 27 pass.
- Re-run with the builder in place: `cash_inflow_demo.js` 28/28, `cashflow_dashboard_demo.js` 28/28, `rasa_hub_demo.js` 25/25.
- `supabase/tests/test_v51.cjs`: 85/85.
