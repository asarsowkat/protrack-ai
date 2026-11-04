# ProTrackAI v3.57: the invoicing phase from a P6 activity code

An activity's invoicing phase decides which payment terms it is invoiced under: each phase's cap on progress and its milestone releases. The phases are Engineering and design, Procurement and supply, Construction and installation, and Testing and commissioning.

Until now ProTrack worked the phase out from the wording of the activity's WBS and name: engineering and design words, supply and procurement words, testing words, and the rest as construction. A supply item filed under a construction WBS could therefore be invoiced on the construction terms. Now the planning engineer can take the phase from a P6 activity code instead, value by value.

## At the baseline import

When the XER carries activity codes, **Invoicing phase taken from** offers:
- **The WBS wording**, as before;
- **Activity code: …** for each code type in the file. A code whose name mentions invoicing, billing or payment (for example "Invoice Phase") is chosen by default.

With a code, each of its values is listed with:
- its number of activities;
- its share of the price weight;
- the phase it is invoiced under, suggested from the value's name and changeable.

These follow the WBS wording, and the screen says how many there are:
- activities with no value for the code;
- values left on **The WBS wording**.

## What the phase changes

Each activity keeps its phase. The invoicing calculation reads it in one place, so it applies everywhere invoiceable is worked out:
- the phase prices;
- invoiceable value on the Home page and the invoice register page;
- Monthly invoicing;
- Invoicing status by phase;
- the cash-inflow forecast;
- the Invoiceable value report.

**Invoicing status by phase** says where the phases come from, for example: the P6 activity code "Invoice Phase" (412 activities), the others by the WBS wording.

The project keeps the chosen code and the phase of each value. The next import of a revised baseline starts from them. A changed mapping on the same file is imported again rather than taken as the same content.

Choosing **The WBS wording** again clears the phases of the activities imported and the project's choice.

An Excel or P6 XML baseline has no activity codes to choose from and keeps the WBS wording.

## Server

`schema-update-v56.sql` (STAGE-50-SETUP) adds:
- the column `activities.inv_phase`;
- the table `project_inv_phase` (the code and its map, read by those who see the project);
- `act_inv_phase_set`, for the project's planning engineers and super admins, the rule of the baseline import.

Without the update the import works as before, and a code chosen gives a note that it needs v56. The rollback keeps the phases already set.

## Checks

- `tests/inv_phase_code_demo.js`: 15 checks on a SAMPLE XER.
- `supabase/tests/test_v56.cjs`: 25 checks on PGlite.
- Also run and passing: `cash_inflow_demo.js` (32), `client_invoice_builder_demo.js` (27), `cib_wbs_weight_demo.js` (14), `contract_value_demo.js` (25), `baseline_compare_demo.js` (18), and `test_v55.cjs` (18).
