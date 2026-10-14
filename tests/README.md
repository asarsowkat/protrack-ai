# ProTrackAI automated tests (v3.7)

| Suite | Checks | What it covers | Needs |
|---|---|---|---|
| `test_v4.py` | 125 | The server rules (v4): attacks that must fail, approval chain, imports, migration, people, rollback | PostgreSQL 16 on `/tmp:5499`, the SQL files next to it |
| `e2e_server.py` + `fake_supabase.py` | 228 | The app in server mode, end to end, against that database (up to v3.5: Tender register, releases, logs; v10 to v16 applied mid-run: issues, quantities, cost report by WBS head, document rack with Storage uploads and signed downloads, progress release dashboard with regional approval and the project manager review, internal weightage, updated schedule upload, validation of differences, client report; v16: rights by role and person, custom role, All projects, screens, refusals by the server) | PostgreSQL, Playwright, Chromium |
| `test_v5.py` (in supabase/tests) | 64 | Controlled imports on the server: checks, reconciliation, failure, retry, concurrency, authorization, rollback | PostgreSQL 16 |
| `test_v6.py` (in supabase/tests) | 53 | Lifecycle rules on the server: who may change, submit, approve, return, reopen; no self-approval; history | PostgreSQL 16 |
| `test_v7.py` (in supabase/tests) | 104 | Tender register on the server: PE proposal, duplicates, release and reallocation, cancel and reinstate, stages 1 to 5 approver, 7-day handover, checklist update, rollback | PostgreSQL 16 |
| `test_v8.py` (in supabase/tests) | 28 | Cost and billing rows only for roles that may see them; writes unaffected; rollback | PostgreSQL 16 |
| `test_v9.py` (in supabase/tests) | 79 | Released reporting on the server: prepare, approve by the Head, no self-approval, revisions, frozen releases, cost formulas, log uploads, rollback | PostgreSQL 16 |
| `test_v10.py` (in supabase/tests) | 51 | Issue register on the server: who may change and review, validation, upload matching and refusals, snapshot at approval, billing amounts, site staff reads, rollback | PostgreSQL 16 |
| `test_v11.py` (in supabase/tests) | 46 | Quantities beyond the scope on the server: justification at review, kept and frozen, approval refused when unjustified, same-day and draft rules, reads, rollback | PostgreSQL 16 |
| `test_v12.py` (in supabase/tests) | 44 | Cost report by WBS head on the server: line and total formulas, previous version, header, validation, justification at submit, freezing, revisions, rollback | PostgreSQL 16 |
| `test_v13.py` (in supabase/tests) | 75 | Document rack on the server: storage rules per row and role, registering, revisions, reads, status, files that cannot change, boxes, rollback | PostgreSQL 16 |
| `test_v14.py` (in supabase/tests) | 56 | Progress release dashboard on the server: worked-out delays, variances, SPI and manpower, validation, regional planning section manager approval, project manager review step, set-up by super admin only, frozen review fields, rollback | PostgreSQL 16 |
| `test_v15.py` (in supabase/tests) | 76 | Internal weightage and mapping, updated schedules and their formulas, append-only, reads, reports compared with the schedule, validation, client reports, rollback | PostgreSQL 16 |
| `test_v16.py` (in supabase/tests) | 114 | Roles and rights on the server: every permission helper gives the v3.6 answer until a right is changed (17 people x 89 answers), only a super admin changes rights, super admins cannot be limited, foremen never see cost figures, role rights, person exceptions, positions, screens, custom roles, All projects and regions for any role, daily reports, releases, logs, issues, documents, Tender and lifecycle reading the rights, reads, the history that cannot be changed, rollback | PostgreSQL 16 |
| `rights_demo.py` | 59 | Roles and rights in demo mode: the tab and its defaults, rights and screens by role, custom roles, All projects and regions for any role, rights for one person, the rules that never change, history, reload, phone width | Playwright, Chromium |
| `rights_parity.py` | 48 people | With no rights changed, every demo person's menu, access and every permission the app checks are the same as on the v3.6 page (run on both pages and compare) | Playwright, Chromium |
| `sched_demo.py` | 62 | Internal weightage, updated XER upload (synthetic file), phase mapping by WBS or activity code, internal progress in every report, invoiceable by client weightage, internal and client reports, validation, Excel and print, phone width, in demo mode | Playwright, Chromium |
| `reldash_demo.py` | 68 | Progress release dashboard in demo mode: full screen, tabs, KPIs and trends, calculations and traffic lights, validation, regional approval, project manager review, executive report, filters, phone width | Playwright, Chromium |
| `docs_demo.py` | 44 | Document rack in demo mode: rows, boxes, rights, upload, revisions, status, preview and download, arranging, separation from other data | Playwright, Chromium |
| `cost_demo.py` | 28 | Cost report in the company format in demo mode: formulas, form, Excel fill and export, justification, totals-only drafts | Playwright, Chromium |
| `qty_demo.py` | 28 | Scope, executed to yesterday, balance, plan for today, beyond-scope warning, justification at review and approval, in demo mode | Playwright, Chromium |
| `issues_demo.py` | 60 | Issue register, Excel upload, snapshot at approval, billing in the cost report, executive Summary and Project view, RASA, in demo mode | Playwright, Chromium |
| `release_demo.py` | 53 | Progress releases, cost reports, executive report, logs and RASA in demo mode (v3.5: fills the dashboard tabs) | Playwright, Chromium |
| `rasa_demo.py` | 32 | Governed RASA answers: sources and data date, no-evidence replies, role and access limits, language-model labelling | Playwright, Chromium |
| `tender_demo.py` | 62 | Tender register, PE numbers, designations and stages 1 to 5 in demo mode | Playwright, Chromium |
| `lifecycle_demo.py` | 36 | Lifecycle, actions and approvals, dashboards in demo mode | Playwright, Chromium |
| `imports_demo.py` | 34 | Controlled imports and the Import centre in demo mode | Playwright, Chromium |
| `regression.py` | 77 | Every screen and report, P6 import with DCMA, approval chain and timers, domain menu, project overview, security behaviour, RASA (demo data) | Playwright, Chromium |
| `suites.py` | 59 | Billing terms, costing upload, invoice register, role access, approval matrix, RASA insights, date switch, exports | Playwright, Chromium |
| `reference.py` | 23 | Every formula against a hand calculation | Playwright, Chromium |
| `backup_demo.py` | 10 | Backup and restore in demo mode | Playwright, Chromium |

```
python3 tests/regression.py index.html sample.xer > results_regression_demo.json
python3 tests/regression.py "index.html?date=live" sample.xer > results_regression_live.json
python3 tests/suites.py index.html > results_suites.json
python3 tests/reference.py index.html > results_reference.json
python3 tests/backup_demo.py index.html > results_backup.json
python3 tests/tender_demo.py index.html > results_tender_demo.json
python3 tests/rasa_demo.py index.html > results_rasa_demo.json
python3 tests/release_demo.py live.html > results_release_demo.json
python3 tests/issues_demo.py live.html > results_issues_demo.json
python3 tests/qty_demo.py live.html > results_qty_demo.json
python3 tests/cost_demo.py live.html > results_cost_demo.json
python3 tests/docs_demo.py live.html > results_docs_demo.json
python3 tests/reldash_demo.py live.html > results_reldash_demo.json
python3 tests/sched_demo.py live.html > results_sched_demo.json
python3 tests/rights_demo.py live.html > results_rights_demo.json
python3 tests/rights_parity.py old-v3.6-live.html parity_v36.json && python3 tests/rights_parity.py live.html parity_v37.json   # then compare the two files
python3 test_v4.py                                    # run from the folder with the SQL files
python3 tests/e2e_server.py index.html /path/to/sql > results_server_mode.json
```
`fake_supabase.py` stands in for Supabase's sign-in, web layer and Storage file handling only; every permission decision comes from the database's own rules. It is a test tool and must never be deployed.
