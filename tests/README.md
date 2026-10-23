# ProTrackAI automated tests (v3.8)

| Suite | Checks | What it covers | Needs |
|---|---|---|---|
| `test_v4.py` | 125 | The server rules (v4): attacks that must fail, approval chain, imports, migration, people, rollback | PostgreSQL 16 on `/tmp:5499`, the SQL files next to it |
| `e2e_server.py` + `fake_supabase.py` | 228 | The app in server mode, end to end, against that database (up to v3.5: Tender register, releases, logs; v10 to v17 applied mid-run: issues, quantities, cost report by WBS head, document rack with Storage uploads and signed downloads, progress release dashboard with regional approval and the project manager review, internal weightage, updated schedule upload, validation of differences, client report; v16: rights by role and person, custom role, All projects, screens, refusals by the server; v17: material tracking set-up, manual fields, statuses from an update, refusals) | PostgreSQL, Playwright, Chromium |
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
| `test_v17.py` (in supabase/tests) | 63 | Material Tracking on the server: who may set it up and keep it, baseline load checks, mapping, monitored materials, PO number, supplier and remarks with history, never overwritten by a revised baseline or an updated schedule, the updated schedule keeping the codes, reads, the new right and screen, rollback | PostgreSQL 16 |
| `project_visual_demo.js` | 24 | v3.10 Project Visual in demo mode: sample set-up, allocation limits and no double counting, zone and variance formulas, suggestions, route spread and stage units, refused uploads, drawing revisions, frozen releases and corrections, rights, GIS length, PDF export. Paste into the browser console on the demo page signed in as the Super Admin; it restores the demo data | A browser (no Playwright) |
| `contract_value_demo.js` | 25 | v3.11 contract value in demo mode: breakdown formulas, log rules and updates with history, rights, frozen releases, internal report, cost report, client report and executive report values, upload of the new and earlier layout. Paste it into the browser console on the demo page signed in as the Super Admin; it restores the demo data afterwards |
| `tender_noa_demo.js` | 22 | v3.12 Tender register in demo mode: full-window registration with the required bid position (L1 or L2, with a reason for L2), the NOA recorded by the costing coordinator or a super admin with its actual date, the finance WBS released the same day for the PBG cost, date rules, corrections, history, stage 3 evidence, rights. Paste it into the browser console on the demo page signed in as the Super Admin; it restores the demo data afterwards |
| `project_import_demo.js` | 17 | v3.13 project import in demo mode: template sheets, a 125-row file of 120 projects, refused rows with reasons, warnings, confirmation, creation with dates, value, Tender details and same-day finance WBS, team access, next PE number, Import centre batch, re-uploads and the current-list round trip, super admin only. Paste it into the browser console on the demo page signed in as the Super Admin; it restores the demo data afterwards |
| `baseline_compare_demo.js` | 18 | v3.14 actual progress against the chosen baselines in demo mode: original = headline (internal and client), revised-baseline formula, variance and SPI, unavailable reasons, earned-value fallback, check boxes with live update, saving, freezing at approval, client card, XER with and without a baseline project, cost reports tab moved to Cost Control. Paste it into the browser console on the demo page signed in as the Super Admin; it restores the demo data afterwards |
| `cash_inflow_demo.js` | 28 | v3.15 invoice register and cash-inflow forecast, and v3.16 monthly invoicing (planned, invoiceable, submitted, approved by month; months invoiced; Excel sheet), in demo mode: template columns, row rules (dates, order, future, phase), earlier layout, status by phase against the register, phase values against the client contract value, actual collections by date, outstanding after the payment period, balance invoiced from this month on, baseline plan, updated schedule, payment period, new-project estimate, page, export, menu and rights, payment terms field. Paste it into the browser console on the demo page signed in as the Super Admin; it restores the demo data afterwards |
| `margin_mail_demo.js` | 17 | v3.17 cost report gross margin by column (original, internal revised, previous month) in the table and the Excel export, and the report emails: default lists, internal and cost report emails on approval with figures and link, the section planning manager's regional list, weekly switch, rights, address validation, Settings, the link opening the report. Paste it into the browser console on the demo page signed in as the Super Admin; it restores the demo data afterwards |
| `deck_reports_demo.js` | 16 | v3.18 reports in the presentation builder in demo mode: the Reports group and parts, sections per report and project, internal report, client report, invoicing and cash flow, cost report with margins, change order log, productivity, parts left out, all projects, Excel sheets and contents, PowerPoint slides added, rights. Paste it into the browser console on the demo page signed in as the Super Admin; it restores the demo data afterwards |
| `money_view_demo.js` | 28 | v3.28.3 cost and billing figures only with the right to see them, in demo mode: cost reports closed even when ticked, the Full report pack, report columns, RASA extracts, Live summary and project view, Dashboard, early warnings and flags, the presentation (offered and built), the new report form and subcontractor lines, Role access; each checked for the site manager, site engineer or foreman and, with the right, for a project manager. Paste it into the browser console on the demo page signed in as the Super Admin; it restores the demo data afterwards | A browser (no Playwright) |
| `supplements_demo.js` | 57 | v3.29 to v3.30 budget supplement log by user field and category, in demo mode: the split into Supplement, Savings, VO Cost and VO Price and the net value, the budget change and the cost report, only WF-approved rows, the many-projects view and every filter, versions, add, change and remove with the history, starting a version, the template and an upload with refused rows, old-layout logs, Settings → Supplement lists, the executive report section and the export, and (v3.29.1) the exported file changed and uploaded again, and (v3.30) the grid: cells typed and chosen, the computed columns, a row stopping the save, add, change and delete saved with the history, a range pasted from Excel, a number twice, leaving with changes, a log started with no file, and (v3.30.1) the button with all projects in scope and the page title, and (v3.31) a version on each row: the Version drop-down, a row of last month with a WF date this month counted by last month's cost report, the screen by one version or up to it, an upload before the latest log refused. Paste it into the browser console on the demo page signed in as the Super Admin; it restores the demo data afterwards | A browser (no Playwright) |
| `mt_auto_demo.py` | 17 | v3.8.1: Material Tracking set up from the original baseline import, actual and forecast from the weekly update, set-up from the first weekly update for projects already loaded, no extra upload | Playwright, Chromium |
| `mobile_menu_demo.py` | 34 | v3.8.3: on a phone and a tablet, Menu in the bottom bar opens the full menu with every domain; screens open from it and it closes; ✕ and Esc close it; no sideways scroll; laptop unchanged | Playwright, Chromium |
| `ep_sched_demo.py` | 24 | v3.8.4: engineering and procurement progress from the weekly updated P6 schedule; no E&P upload on the page or in the import centre; compliance, planning dashboard, lifecycle and RASA name the updated schedule | Playwright, Chromium |
| `mat_demo.py` | 52 | Material Tracking in demo mode: synthetic XER set-up (codes, WBS, mapping, materials), milestone and delivery statuses, Delayed rule, schedule updates, manual fields and history, never overwritten, KPIs, charts, filters, search, sorting, Excel and PDF, rights, phone | Playwright, Chromium |
| `fullscreen_demo.py` | 21 | v3.7.2: daily reports opened for review or approval and Create / Edit project fill the screen; action buttons stay in view; other settings forms stay a side panel; desktop and phone | Playwright, Chromium |
| `mmcs_demo.py` | 10 | v3.7.1: the costing file shown as the Master Manpower Costing Sheet everywhere, stored values unchanged, tender documents untouched | Playwright, Chromium |
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
python3 tests/mat_demo.py live.html > results_mat_demo.json
python3 tests/rights_parity.py old-v3.6-live.html parity_v36.json && python3 tests/rights_parity.py live.html parity_v37.json   # then compare the two files
python3 test_v4.py                                    # run from the folder with the SQL files
python3 tests/e2e_server.py index.html /path/to/sql > results_server_mode.json
```
`fake_supabase.py` stands in for Supabase's sign-in, web layer and Storage file handling only; every permission decision comes from the database's own rules. It is a test tool and must never be deployed.

## v3.34: emails really sent

| Test | Checks | What it proves |
|---|---|---|
| `../supabase/tests/test_v38.py` | 46 | The mail queue on PostgreSQL 16 with every update v2 to v38: who may queue which email, the recipients the server works out, queued once, no direct writes, own emails only, Send again, rollback |
| `../supabase/functions/send-mail/test.mjs` | 27 | The send-mail Edge Function in Node 22 with Microsoft Graph, SMTP and the database simulated: settings, who may send, sent once, failures recorded, 5 attempts, the queue |
| `mail_e2e.py` (`python3 mail_e2e.py ../live.html ../supabase`) | 27 | The real app in Chromium against PostgreSQL with every update v2 to v38: the approver's and the report approver's emails queued with the server's recipients and handed to the function by id only; others refused; Settings → Email, test email, failed reason, Send again, Send queued emails now; settings saved on the server by the super admin only; after the rollback, listed as not sent with the reason |

`e2e_server.py` also has an Email (v38) section, but that script has stopped earlier, at the costing sheet upload, since v3.9.1 moved the costing sheet to its own page; `mail_e2e.py` is the one to run.

## v3.35: Budget & Cost Management, Automatic WBS Classification

| Test | Checks | What it proves |
|---|---|---|
| `../supabase/tests/test_v39.py` | 105 | The server on PostgreSQL 16 with every update v2 to v39: rights and access, master data proposed and approved by different people and versioned, the starting master waiting, storage rules, the same file refused, frozen lines, runs, every server check of an automatic classification, decisions kept, bulk rules, undo, corrections, rollback |
| `bcm_engine_test.cjs` (`node bcm_engine_test.cjs ../live.html path/to/xlsx.js`) | 74 | The engine taken from live.html with the real SheetJS 0.18.5 on `fixtures/bcm`: extraction, normalization, classification layers, controls, thresholds, mappings, failed or invalid AI output |
| `bcm_demo.py` (`python3 bcm_demo.py ../demo.html path/to/xlsx.full.min.js`) | see results | The demo page through the screens, from upload to approved mappings, with Cost Control still opening |
| `bcm_e2e.py` (`python3 bcm_e2e.py ../live.html ../supabase path/to/xlsx.full.min.js`) | see results | The live app against the database through the stand-in Supabase with its storage |

`fixtures/bcm/make_fixtures.py` makes the test workbooks (openpyxl, then LibreOffice to store calculated values; file 13 keeps formulas without values on purpose). SheetJS 0.18.5 is the version the app loads: `git clone --depth 1 --branch v0.18.5 https://github.com/SheetJS/sheetjs` gives `xlsx.js` and `dist/xlsx.full.min.js`.

## v3.39: budget supplement and change request forms, Approval Hub

| Test | Checks | What it proves |
|---|---|---|
| `../supabase/tests/test_v43.py` | 75 | v43 on PostgreSQL: rights and their defaults; forms prepared, numbered and checked line by line; the VP and EVP in the chain; submission and the queue; the hub token (super admin, kept as a hash, wrong token refused, switched off); the hub with the anon role taking a submission once, reporting the WF number and the approval; posting to the budget supplement log (rows, WF number, version, budget change); posted rows protected on the log screen; the version moved with its limits and reason; the link kept on a new log; decisions recorded by hand (rights, WF number, dates), returned, resubmitted, rejected; cancel; change requests added to or updating the change order log; read rules; rollback and again |
| `wf_demo.py` (`python3 wf_demo.py ../demo.html path/to/xlsx.full.min.js`) | see results | The demo page: a BRF in the company layout, its lines, the summary by user field, the Excel form, submission, the coordinator's decision by hand, the rows in the log and their protection, the version moved, a return and resubmission, the EVP for the management reserve, a change request to the change order log, rights |
| `wf_e2e.py` (`python3 wf_e2e.py ../live.html ../supabase path/to/xlsx.full.min.js`) | see results | The live app against the database v2 to v43, with Approval Hub played through the anon role and the token made on the screen |
| `bcm_engine_test.cjs` | see results | Now reads the SAP CN41 layout (`fixtures/bcm/25_sap_cn41.xlsx`) |

## v3.38: Budget & Cost Management stage 4

| Test | Checks | What it proves |
|---|---|---|
| `../supabase/tests/test_v42.py` | 67 | v42 on PostgreSQL: rights; templates; imports refused (file not stored, future period, not a number, repeated, no WBS element, total row, no amount column) and kept nothing; the figures by WBS element with totals at each level counted once; the same file refused; a report superseded and kept; frozen rows; line items (period, to the end of the period, commitments); read rules (and the v41 fix); the loading workbook refused (Tender estimate, no right, draft, invalid SAP WBS IDs, another waiting); original budget; confirmation (right, reference, dates); supplements and returns; return and a second workbook; an older version after a later one; nothing changing; rollback and again |
| `bcm_demo4.py` (`python3 bcm_demo4.py ../demo.html path/to/xlsx.full.min.js`) | see results | The demo page: the reports of `fixtures/bcm/20` to `24` imported (and the mistakes of 23 refused), a template, the Cost Summary with its 24 columns, statuses, filters and export, the loading workbook of Rev 0 and of the revision (supplements and returns), confirmation with the SAP reference, a return, Approval History |
| `bcm_e2e.py`, `bcm_engine_test.cjs` | see results | Now include stage 4 on the server and the engine functions (SAP report reading and checks, the figures of a period, the cost summary, the workbook content and sheets) |

## v3.37: Budget & Cost Management stage 3

| Test | Checks | What it proves |
|---|---|---|
| `../supabase/tests/test_v41.py` | 77 | v41 on PostgreSQL: roles, candidates and decisions (with the lines counted worked out by the server), splits that must add up and be approved by someone else, explanations, `bcm_totals`, budget versions from a batch and imported (unique IDs, numbers, user fields, the file total), the approval steps by different people, frozen lines, rollback and again |
| `bcm_demo3.py` (`python3 bcm_demo3.py ../demo.html path/to/xlsx.full.min.js`) | see results | The demo page: analysis, decisions and reopening, splits, the Reconciliation Centre, a Tender estimate through its approval, the import of `fixtures/bcm/18_budget_import.xlsx` (and the refused rows of `19_budget_import_invalid.xlsx`), the comparison, the export, Approval History |
| `bcm_e2e.py`, `bcm_engine_test.cjs` | see results | Now include stage 3 on the server and the engine functions (roles, candidates, decisions, tolerances, splits, the budget import) |

## v3.36: order, SAP WBS ID and user field

| Test | Checks | What it proves |
|---|---|---|
| `../supabase/tests/test_v40.py` | 27 | v40 on top of a partly approved v39 master: the System proposals, a person's change left alone, the checks of segments and user fields, uniqueness at approval, reorder, running twice, rollback |
| `bcm_demo.py`, `bcm_e2e.py` | 67, 31 | Now include the SAP WBS IDs, user fields, reorder, the Excel columns (`fixtures/bcm/17_wbs_import_sap.xlsx`) and the upgrade of a v3.35 sample master |
