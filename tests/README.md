# ProTrackAI automated tests

Three suites, run in a headless Chromium browser against `index.html` on its built-in demo data.
Nothing is saved and no network is used.

| Suite | Checks | What it covers |
|---|---|---|
| `regression.py` | 77 | Every screen and report, P6 import with DCMA, approval chain and timers, domain menu, project overview, security behaviour, RASA |
| `suites.py` | 58 | Billing terms and the 0% cap rule, costing file upload, invoice register upload, role access, approval matrix, RASA insights, demo/live date switch, exports |
| `reference.py` | 23 | Every formula against a hand calculation on a reference project (see the Finance formula reference) |

Run (needs Python with Playwright and Chromium):

```
python3 tests/regression.py index.html sample.xer > results_regression.json
python3 tests/regression.py "index.html?date=live" sample.xer > results_regression_live.json
python3 tests/suites.py index.html > results_suites.json
python3 tests/reference.py index.html > results_reference.json
```

Limits: Excel files are read by a small stand-in for SheetJS (the app's own column matching,
validation and apply logic runs for real; SheetJS's binary parsing does not). PDF and PowerPoint
exports, Supabase sign-in and row-level security are not covered.

Results for v2.4 (9 Oct 2026): regression 77/77 in demo mode and 77/77 in live mode, suites 58/58,
reference 23/23. Two regression items are skipped by design: real Excel/PDF export and PMXML import.
