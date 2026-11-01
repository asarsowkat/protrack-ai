# ProTrackAI v3.49: the Schedule-C item from the WBS, invoiced on the "Schedule C Invoicing" weight

In the planning practice, the price schedule **item number** sits on the **WBS**, not on each activity. A separate P6 resource, **Schedule C Invoicing**, is assigned only to the activities the contract lets the company invoice on. For example, for a material item the client pays after the material is delivered and inspected by the client and the consultant. So only the inspection activity carries that weight; the PR, PO, manufacturing and shipment activities do not. v3.48 read the item from an activity code and weighed every mapped activity. v3.49 follows the schedule as it is built.

## What changes

### The item number from the WBS

- The Client Invoice Builder reads the WBS field **"Schedule C"** from the XER.
  - Every activity takes the value of its own WBS, or of the nearest WBS above it that has one.
  - A child WBS with its own value keeps its own value. For example, "110kV GIB connectors" has A.SS.3.1.2.2.1.2 under "110kV GIB", which has A.SS.3.1.2.1.1.
- An activity code **"Schedule C"** on an activity still works. Where both are present, the activity code wins.
- The **code value** is used, not the code's description. Before, the description was taken first.

### The invoicing weight

- The builder finds the resource whose name or ID mentions "Schedule C" or "invoicing", for example **PE-308 SCH · Schedule C Invoicing**. Weightage resources such as INTERNAL WEIGHTAGE and SEC weightage are not used.
- Each activity's **budgeted units** of that resource are its invoicing weight.

### Progress of an item

- Where any mapped activity of the item carries the invoicing weight, only those activities count:

  P = Σ (invoicing weightᵢ × % completeᵢ) / Σ invoicing weightᵢ

  - The other activities of the item are shown but **not invoiced on**.
  - % complete is the activity's % complete as the updated schedule holds it (physical % for Physical activities).
- An item with **no** activity carrying the weight earns as before, on all its activities by schedule weight. In a project that uses the invoicing weight, such an item is:
  - named in the mapping audit;
  - warned on the invoice. This does not block.
- Example (SAMPLE): an item with nine activities. PR, PO, design, approval, manufacturing, FAT and shipment are 100%, delivery is 26% and installation readiness is 0%. Only the delivery activity carries the invoicing weight, so the item is at **26%**, not about 81%.

## Where you see it

- **Client Invoice Builder → Mapping audit → Read the Schedule C mapping from P6.** Load an XER and check three choices:
  - the WBS field;
  - the activity code;
  - the invoicing resource.

  All three are suggested from their names. The preview shows:
  - how many activities take an item from the WBS and how many from the code;
  - how many carry the invoicing weight;
  - any activity that carries the weight but has no item.
- **The same reading** runs by itself when an updated schedule is loaded in Planning.
- **Open an item** in the mapping audit to see each activity's schedule weight, its invoicing weight, its % complete and its source (P6 WBS, P6 activity code or by hand). Activities without the weight in a weighted item show "not invoiced on".
- **Invoice lines:**
  - the source shows "P6 · n invoicing-weighted";
  - the Excel invoice says "P6, n invoicing-weighted activities".
- An activity mapped **by hand** carries no invoicing weight.

## Demo

- **QOT:**
  - The SAMPLE price schedule has a new item, **S.3.2 ACSR conductor drums, supply (SAMPLE)**. Its value is taken from S.3.1, so the total is unchanged.
  - All nine activities of its WBS package are mapped from the WBS, and only the delivery carries the invoicing weight.
  - The other sample mappings now come from the WBS and carry the invoicing weight.
- Demo data already in a browser is brought up to date when the page opens.
- All values are SAMPLE. The P6 screenshots provided were used for their structure only.

## Server: schema-update-v52.sql

- `cib_maps` gets:
  - `w`: the invoicing weight;
  - `via`: `wbs` or `code`.
- `pt_cib_prog` weighs by `w` where an item has it.
- `pt_cib_compute`:
  - marks each line `iw`;
  - adds the warning.
- `cib_act` `map_save` keeps `w` and `via`.
- `cib_features()` reports version 52.

Rollback: `schema-rollback-v52.sql`. See STAGE-46-SETUP.md.

## Tests

- `tests/cib_wbs_weight_demo.js`, **14 checks**:
  - a SAMPLE XER: the WBS field inherited down, a child WBS with its own value, the code taking precedence and its value used, the invoicing resource and its units;
  - the mapping rows and the preview;
  - weighted progress;
  - the store;
  - the warning;
  - the screen.
- `supabase/tests/test_v52.cjs`, **27 checks** on PGlite:
  - the columns;
  - weighted progress on the server (40% instead of 88%; two weighted activities at 70%);
  - the fallback and its warning;
  - idempotent reading;
  - a changed weight;
  - bad weights;
  - by hand;
  - the audit;
  - rollback and reinstall.
- Still passing:
  - `client_invoice_builder_demo.js` 27/27;
  - `cash_inflow_demo.js` 28/28;
  - `cashflow_dashboard_demo.js` 28/28;
  - `rasa_hub_demo.js` 25/25.

## Not done

- v52 has not been run on Supabase. Try it on a staging copy first.
- Only the **WBS user field** is read on the WBS. A WBS category or a code held elsewhere is not. If "SCHEDULE C" in your P6 WBS view is not a user field, send an XER (or say where it is kept), and the reader will be extended.
