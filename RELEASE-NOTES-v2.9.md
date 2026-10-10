# ProTrackAI v2.9: Phase 5, governed RASA answers (October 2026)

## What changed

### Every answer says what it is based on
Under every RASA answer, quick action and insight there is now a **Based on** line. It names:
- **Daily reports:** how many, their dates, how many are approved, and how many are submitted or reviewed and counted before approval.
- **The baseline:** its activities, and when and in which batch it was loaded.
- **Cost and billing sources**, where used: the costing file or invoice register batch (for example IMP-0012), the contract billing terms and the dated rates.
- **Other records:** the weekly engineering and procurement update and its data date, lifecycle stages, the Tender register.
- **Scope and data date.**
- **Not available:** anything the answer would have needed but ProTrackAI does not hold.

### "No evidence" instead of a guess
- **No data:** when there is no data for the question, RASA says **No evidence in ProTrackAI** and what is missing. A project with no baseline or reports no longer gets "every project is within tolerance" or "no early warnings".
- **No invoice register:** if none is loaded, invoiced, approved and collected amounts are reported as unknown, not as SAR 0.
- **Things ProTrackAI does not track** are named as such:
  - SAP actual cost (no SAP connection; actual cost in ProTrackAI is not SAP actual cost)
  - commitments, accruals and budget revisions
  - cash-flow forecast, variation register, claims register and material tracking (all planned)
  - safety and weather
- **Unanswerable questions:** a question RASA cannot answer from the records gets a no-evidence reply listing what it can answer.

### Only what the person can open
- **Projects:** a project outside the person's access is refused. A project in their access but outside the current scope is pointed to the Scope menu, so they never get figures for the wrong scope.
- **Site roles** (foremen, site engineers and site managers) get no cost, budget or billing figures from RASA:
  - Invoiceable value, collection, unit rates and EAC reply "not available for your role".
  - Subcontractor answers show productivity without SAR.
  - Their insights and suggested questions hold no cost topics.
  - The Tender register is not offered.
- **On the server** (`schema-update-v8.sql`), their browsers no longer receive invoice rows, invoice and costing import batches (which carry file totals), or costing and invoice upload history. Every other role sees exactly what it saw before.

### No project data leaves ProTrackAI
- **On your ProTrack site:** the language model is never called. Settings → System states the policy.
- **On the demo page inside claude.ai:** a question RASA cannot answer from the records may go to the model, using sample data only. The answer is labelled **Language-model answer**. If the question comes from a site role, no billing or cost figures are sent.

### New questions RASA answers from the records
- **What is waiting for me:** from Actions and approvals.
- **Lifecycle stages:** each project's current stage, stages awaiting approval (and who they wait for) and overdue stages.
- **Tender register:** pre-award and cancelled counts and the next PE number. Asking about a PE or TE number gives that project's register row.

## Database: `schema-update-v8.sql`
- Changes three read rules (invoices, upload history, import batches) and adds one helper function. **No table, column or row changes.**
- Safe to run twice.
- `schema-rollback-v8.sql` puts back the previous rules.

## Verified

| Suite | Checks | Result |
|---|---|---|
| Database: cost rows by role, writes unaffected, rollback (`test_v8.py`) | 28 | 28 pass |
| Server mode, end to end through the app (RASA checks added) | 105 | 105 pass |
| RASA governance in demo mode (`rasa_demo.py`), app and demo page | 32 + 32 | all pass |
| Tender register / lifecycle / imports in demo mode | 62 / 36 / 34 | all pass |
| Regression, demo date and live date (with your PE-329 XER) | 77 + 77 | all pass, 2 skipped each |
| Functional suites / formula reference / backup and restore | 59 / 23 / 10 | all pass |
| Demo page: regression / lifecycle / Tender register | 77 / 36 / 62 | one expected difference (its own storage key) |

No earlier check had to change.

**Not verified here:** Supabase itself (a local stand-in was used) and your live project.

## Still open
- **Site staff and earned value:** site engineers and site managers still see earned value in SAR (EV, PV) and CPI on their dashboard and executive summary. Activity budgets and price weights also still reach their browsers, because the daily report needs the activity list. RASA no longer gives them cost answers, but the screens are unchanged. Tell me whether site staff should see earned value in SAR; if not, I can hide it on their screens and move those fields behind the server.
- **No log of RASA questions:** questions and answers are not recorded anywhere. If you want an audit trail of what RASA told whom, that would be a later addition.
