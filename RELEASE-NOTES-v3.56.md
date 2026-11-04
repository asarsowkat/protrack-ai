# ProTrackAI v3.56: invoiceable and the invoices on one basis

Invoiceable and the invoices are now compared on the same basis: **gross**. Gross means the value of the work under the contract's payment terms, before retention and advance recovery.

## Why

Invoices come in two ways, and both hold gross amounts:
- the **invoice register** (uploaded by costing);
- the **Client Invoice Builder** (Schedule C mapped to the P6 schedule). It records each issued invoice in the register at its gross value for the period.

The cash-inflow forecast and the "Invoicing status by phase" table already read the register as gross. Two places did not:
- the project **Home** page's Invoiceable;
- **Monthly invoicing**.

They showed invoiceable **net** of retention and advance recovery. On a project with 10% retention and a 10% advance, a fully invoiced project looked over-billed by those deductions.

## What changes

**Invoiceable** = the value earned under the phase payment terms + the advance, on the client contract value:
- each phase's price progress, up to its cap;
- plus the milestone releases achieved (TCC, FAC);
- plus the advance.

It is the same on:
- the project Home page and the portfolio billing tiles;
- the invoice register page;
- Monthly invoicing (Planned invoice, Invoiceable, Forecast invoicing);
- RASA.

**Retention release invoices** are left out of Submitted and Approved when they are compared with invoiceable, because the gross already holds their value. Home shows them apart ("plus retention released").

**Retention, advance recovery and the net payable** are unchanged and stay where the money is:
- the cash-inflow forecast and its collections;
- the Invoiceable value report, whose last line is now "Net payable to date";
- RASA, which gives the gross, then the deductions and the net payable.

**Invoice register template:** a line says that amounts are gross, before retention and advance recovery, with no VAT.

No change to the payment terms, the cash-inflow forecast or the Client Invoice Builder's invoices. No server change.

## Checks

`tests/cash_inflow_demo.js` has 32 checks, four of them new or changed:
- the template says the amounts are gross;
- with 10% retention and a 10% advance, invoiceable on Home and in Monthly invoicing is the same gross figure, above the net;
- the baseline plan in gross adds up to the client contract value plus the advance;
- a retention release invoice is left out of submitted and approved and shown apart.

Also run and passing: `client_invoice_builder_demo.js` (27), `cashflow_dashboard_demo.js` (28), `deck_reports_demo.js` (16), `money_view_demo.js` (28).
