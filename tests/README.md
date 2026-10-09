# ProTrackAI automated tests (v2.5)

| Suite | Checks | What it covers | Needs |
|---|---|---|---|
| `test_v4.py` | 125 | The server rules: attacks that must fail, approval chain, imports, migration, people, rollback | PostgreSQL 16 on `/tmp:5499`, the SQL files next to it |
| `e2e_server.py` + `fake_supabase.py` | 55 | The app in server mode, end to end, against that database | PostgreSQL, Playwright, Chromium |
| `regression.py` | 77 | Every screen and report, P6 import with DCMA, approval chain and timers, domain menu, project overview, security behaviour, RASA (demo data) | Playwright, Chromium |
| `suites.py` | 58 | Billing terms, costing upload, invoice register, role access, approval matrix, RASA insights, date switch, exports | Playwright, Chromium |
| `reference.py` | 23 | Every formula against a hand calculation | Playwright, Chromium |
| `backup_demo.py` | 10 | Backup and restore in demo mode | Playwright, Chromium |

```
python3 tests/regression.py index.html sample.xer > results_regression_demo.json
python3 tests/regression.py "index.html?date=live" sample.xer > results_regression_live.json
python3 tests/suites.py index.html > results_suites.json
python3 tests/reference.py index.html > results_reference.json
python3 tests/backup_demo.py index.html > results_backup.json
python3 test_v4.py                                    # run from the folder with the SQL files
python3 tests/e2e_server.py index.html /path/to/sql > results_server_mode.json
```
`fake_supabase.py` stands in for Supabase's sign-in and web layer only; every permission decision comes from the database's own rules. It is a test tool and must never be deployed.
