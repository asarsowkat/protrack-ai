# ProTrackAI v3.11: internal and client contract value (October 2026)

From v3.11 there are two revised contract values:
- **Internal:** measures contract value and margin in every internal report, the executive report and the dashboards.
- **Client:** used only in client reports, and only once the client has approved.

Both come from the change order and claim log, which the costing engineer keeps.

## The change order and claim log
**Claims & Variations → Change order and claim log.**

**New columns** (in the template and on the screen):

| Column | What it holds |
|---|---|
| **Client approved price** | the price the client approved (full or partial), once it has approved |
| **Price considered internally (SAR)** | the value management approved internally before the client: the full value or a part of it |
| **Internal WF no**, **Internal WF date** | the management approval workflow behind that value |

Below the estimated price, the value is marked **Partial**; at the estimated price, **Full**.

**Updating a row:** the costing engineer (or costing coordinator) can update a row of the project's latest log on the screen with **Update**:
- client approval status;
- client approved price;
- price considered internally, with its WF number and date;
- remarks.

Every change is kept under **Updates to the log**, with who made it and when. Earlier months stay as they were uploaded.

**A row is refused, on upload or update, when:**
- a price considered internally has no WF number and WF date;
- the price considered internally is more than the estimated price;
- it has a client approved price but the client status is not Approved or Partially approved;
- a rejected item has a client approved price;
- the WF date is in the future;
- a price is negative or not a number.

**Earlier logs:** a log in the earlier layout, where *Price considered internally* is Yes / No / Partial, still loads. Its text is kept, and the row counts once the new values are given.

**On the page:** the log shows the KPIs (approved by the client, considered internally, revised contract value) and the full contract breakdown.

## The breakdown
Taken from the latest log up to the month of the report:

| Line | Rule |
|---|---|
| Original contract value | the project's contract value |
| Change orders and claims submitted | Σ estimated price of the items submitted to the client |
| Change orders and claims approved by the client | Σ client approved price |
| Price considered internally | per item: the client approved price once the client has approved; before that, the price considered internally with its WF number and date; nothing for a rejected item |
| **Revised contract value (internal)** | **original + price considered internally** |
| Revised contract value (client-approved) | original + approved by the client |
| Gross margin (internal) | revised contract value (internal) − EAC of the released cost report |

## Where each value is used
**Internal revised contract value:**
- **Internal reporting:**
  - a *Contract value* card with the breakdown, plus the margin when the month's cost report is released;
  - the project information;
  - *Internal planned / actual amount* = internal revised contract value × planned / actual %.
- **Monthly cost report:**
  - the contract value is the internal revised value (read-only, with its breakdown), and the gross margin rows are measured on it;
  - **Fill from Excel:** a different contract value in the file is reported, and the internal value is used.
- **Executive report (released):**
  - a new *Contract value and margin* section (per project and total);
  - a new *Contract value, internal* tile; both can be shown, hidden and reordered with the others;
  - the region and sector value column;
  - progress and SPI weighting;
  - the project view (header, a breakdown card and the change orders with approved and considered prices);
  - the change order table now shows the client approved price and the price considered internally.
- **Cost Control dashboard:**
  - the contract KPI and column;
  - a new *Contract value and margin by project* table; a row opens the project's log.
- **Other screens:**
  - the project overview's contract and financial summary, which replaces the "planned" placeholders;
  - the Live summary project page;
  - the document rack figure;
  - portfolio progress weighting.

**Client-approved revised contract value:**
- **Client reports:**
  - a *Contract value* card: original, approved by the client, revised contract value;
  - the same lines in the Excel export and the printed report;
  - prices considered internally never appear.

## Frozen with each release
When an internal report, client report or cost report is approved, its contract breakdown is saved with it. A client report keeps only the client-approved part. A cost report's margin uses the approved value.

Later log uploads or updates never change a released report; a correction is a new revision. Reports released before v3.11 show the breakdown worked out from the log up to their month.

## On the ProTrack server (live.html)
**Works now:** uploads with the new columns go to the server as before. Figures computed in the browser are not sent with a release.

**Needs a database update (v20):**
- store the four new log columns;
- a row update with its history, and the right to make it (`logs.upload`);
- the contract breakdown computed and frozen by the server at approval.

Until then, on the server:
- **Update** on the log screen is switched off and the page says so;
- releases approved there are worked out from the log.

**The v20 update is ready, not yet installed:** `supabase/schema-update-v20.sql`, with `STAGE-16-SETUP.md` (how to apply it and check it) and `schema-rollback-v20.sql`. It needs v18 and does not need v19 (Project Visual).
- **Log columns:** `co_log` gets `client_price`, `internal_price`, `wf_no` and `wf_date`. `log_import` stores them and refuses a row with the same rules as the app (`voCheck`); a file of the earlier layout keeps its Yes / No / Partial text.
- **Row update:** `vo_update` changes a row of the project's latest log only, for people with `logs.upload` or the costing coordinator, with the same rules. Each change goes to the new append-only table `co_log_updates` and to the Change log. `co_log` stays append-only apart from those fields.
- **Frozen breakdown:** at approval a trigger on `report_releases` works out the breakdown as `contractOf` does and saves it in `contract_snapshot`. A client report keeps only the original, approved by the client and client revised value. A cost report also gets `figures.contract` and `figures.contract_value`. A released version cannot change it. `release_act` is not replaced, so v19 can still change it.
- **live.html:** when signed in to the server, the page reads the update history. When that works, it switches **Update** on, through `vo_update`. Released reports read `contract_snapshot`. Without v20 the page behaves as described above. The demo page is unchanged.
- **Not yet verified:** the SQL has not been run on a database. This machine has no PostgreSQL, and there is no `test_v20.py` yet. live.html has not been tried against the server. `tests/contract_value_demo.js` (25) and `tests/project_visual_demo.js` (24) still pass on the demo page.

## Demo
- **Sample log of each project:**
  - VO-001 approved by the client at its expected price;
  - VO-002 considered internally in full;
  - CL-001 considered internally in part;
  - each with a sample WF number and date.
- **Existing demo data:** gets these values once.
- **Reset demo data:** starts over.

## Checks
`tests/contract_value_demo.js` runs 25 checks in the browser console on the demo page and puts the demo data back afterwards. It covers:
- the formulas and the rules, updates and their history, and rights;
- frozen releases;
- the internal report, cost report, client report and executive report values;
- the upload of the new and the earlier layout.

`tests/cost_demo.py` now expects the contract value from the log, and a warning when the file's differs.
