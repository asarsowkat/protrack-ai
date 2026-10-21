# ProTrackAI v3.28.2: Riyadh Metro's sample July cash-out version (October 2026)

A fix to the demo page's sample data. Nothing changes on the server or in how the cash-out forecast is worked out.

## The problem

On the demo page, Riyadh Metro's published **July 2026 cash-out forecast version** (Version 1, the original baseline of the version comparison) showed a **Forecast Overrun at about 186% of budget**: a forecast at completion of SAR 612.9M against a budget of SAR 328.6M.

The cause was the order of the sample data:
- the v3.20 sample data took the July version while the sample **other cash-out line** (own manpower, site overheads and materials not on subcontract POs) was still in the forecast;
- the v3.21 sample data then replaced that line by the **cost report heads (EAC − actual)**, but the July version had already been taken with the heads and the other line both, so that cost was counted twice.

The live forecast for Riyadh Metro was within budget (about 94.8%), so the July version did not match the sample story.

## The fix

- The sample July version is now taken **after** the v3.21 sample data: on the cost report heads, with the other line removed and Finance's cumulative actuals as recorded.
- It is **within budget**: forecast at completion SAR 312.2M against SAR 328.6M, headroom SAR 16.3M, 95.0% of the budget.
- It is still reviewed by the costing coordinator on 11 August 2026 and published by the Head of Planning and Cost Control on 12 August 2026, with the same comment. It remains sample data.

**A browser that already holds the old sample** gets the July version taken again when the page opens, once. This happens only if the version is still the untouched sample with the Forecast Overrun. Reset demo data gives the same result.

## The user guide (guide.html), brought up to v3.28.2

`guide.html` now covers every release from v3.9 to v3.28.2:

- **Section 4, roles and access:** every role; the head office positions (Head of Planning and Cost Control, costing coordinator, planning section manager); and two tables read from the app itself, the screens each role sees and the 27 rights each role has.
- **Section 5, the menu domain by domain:** all 13 domains. Each has a table of its screens (what it is for, who sees it, who changes it), followed by the full how-to. New how-tos include the Project list, Project Visual, the Live summary, the client report, baselines and the comparison reports, the cost dashboards, the costing sheet, unit rates, budget supplements, subcontract POs, the invoice register, payment terms, extension of time, BOQ Engine (all twelve sections), the Settings tabs and the release strategy.
- **Section 6, step by step:** all twelve roles and positions. Read-only, the Head, the costing coordinator and the planning section manager are new.
- **Version notes:** the missing ones (3.22.1 to 3.28.2) are filled in, and about 120 out-of-date statements are corrected.

The guide was checked against the app's code by an independent review. Its corrections are in.

## Server files: v18 fixed, every rollback safe to run

Two fixes to the `supabase/` files. Nothing changes in the app.

- **`schema-update-v18.sql` would not run.** Two functions (`pt_xr_default_stamp`, `pt_xr_default_log`) had their body quoted with `$` instead of `$$`, so Supabase stopped with *syntax error at or near "$"*. They now use `$$`, and nothing else in the file changed.
- **Every rollback, v4 to v34, is safe to run even if its update was never applied.** Before, `schema-rollback-v20.sql` stopped with *relation "co_log_updates" does not exist* on a database without v20. Some rollbacks did worse and quietly added functions of an update the database never had: v25 (the delay register's functions, so the app would think the register is on the server), v28 (cash-out) and v33 (E&P).
  - Now each rollback first checks for the first table, column or function its update adds.
  - If it is not there, the rollback changes nothing and answers one row: *schema-update-vN.sql is not on this database (never run, or already undone): nothing to undo, nothing was changed.*
  - If it is there, the rollback runs exactly as before and answers *schema-update-vN.sql undone.*

A rollback is still only for undoing an update that caused a problem. To bring a database up to date, run only the `schema-update-*.sql` files, in order.

**Checked** on PostgreSQL 16.4 (PGlite) with the test stand-in for Supabase (`supabase/tests/TEST-ONLY-supabase-stub.sql`):
- `schema.sql` and every update v2 to v34 apply in order, and each of v18 to v34 runs a second time without error.
- Every rollback was run on a database one version below its update, on one at v17 and on one at v3: in all 76 cases no error, nothing changed, and the "not on this database" answer.
- Undoing from v34 down to v4 one rollback at a time, run once and then again: after every step the database is the same as with the rollbacks before this change.
- As before, undoing all the way below v9 stops at v8, v7 and v4 (tables kept from later updates still use those functions), and changes nothing.

## Checks

- **Cash-out forecast suite** (`tests/cashout_demo.js`): 27 checks pass. One is new: Riyadh Metro's published July version is within budget and equals the July forecast.
- **Cash-out on P6 and the cost report suite** (`tests/cashout_p6_demo.js`): 24 checks pass.
- Both suites were run on the demo page, on a browser upgraded from v3.28.1 and on freshly reset demo data. The two give the same July version.
