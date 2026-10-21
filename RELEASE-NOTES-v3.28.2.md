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

## Checks

- **Cash-out forecast suite** (`tests/cashout_demo.js`): 27 checks pass. One is new: Riyadh Metro's published July version is within budget and equals the July forecast.
- **Cash-out on P6 and the cost report suite** (`tests/cashout_p6_demo.js`): 24 checks pass.
- Both suites were run on the demo page, on a browser upgraded from v3.28.1 and on freshly reset demo data. The two give the same July version.
