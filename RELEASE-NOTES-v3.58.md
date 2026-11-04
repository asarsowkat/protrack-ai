# ProTrackAI v3.58: two warnings on the invoicing phases

Two situations used to pass silently and now get a warning.

## 1. A revised baseline without the project's invoicing code

Since v3.57 a project's invoicing phase can come from a P6 activity code, such as "Invoice Phase". If a revised baseline arrives without that code, the import fell back to the WBS wording without a word and cleared the phases of the activities in the file. That happened with:
- an XER exported without its activity codes;
- an Excel baseline;
- a P6 XML baseline.

Now the import says:

> **This file has no activity code "Invoice Phase"**. This project's invoicing phase came from that code at the last baseline import. Export the XER from P6 with its activity codes, or choose another code below.

It offers two choices for the activities in the file:
- **Keep the phases already set** (the default): each activity keeps the phase it had. New activities in the file follow the WBS wording. The project keeps its code and map for the next import.
- **Go back to the WBS wording**: the phases of the activities in the file and the project's choice are cleared, as before.

Choosing another code from the file works as in v3.57.

## 2. A phase with no priced activity

A phase's price is the sum of its activities' price weights. With no priced activity, that phase's payment terms (cap, milestone releases) are never used: the contract value is shared among the phases that have priced activities and invoiced under their terms.

A warning now lists those phases on:
- the payment terms (Settings → Projects → Billing and payment terms);
- Invoicing status by phase (Invoices & Cash Flow).

The warning:
- says what it means;
- counts the invoices in the register tagged to the phase, which count as invoiced beyond its value;
- says what to do: if the contract prices the phase, add a priced activity in P6 (a level-of-effort activity will do), or give activities the phase through the invoicing activity code at the next baseline import. If the contract has no such phase, nothing needs doing.

The demo's RMX project shows it: it has no priced testing activity.

## Server

No change. When the phases are kept, the import leaves `activities.inv_phase` as it is (`import_baseline` does not touch it) and does not call `act_inv_phase_set`.

## Checks

- `tests/inv_phase_code_demo.js`: 22 checks, 7 of them new.
- Also run and passing: `cash_inflow_demo.js` (32) and `baseline_compare_demo.js` (18).
