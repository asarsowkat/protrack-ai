# Budget & Cost Management, Automatic WBS Classification: engineering handover (ProTrackAI v3.35 to v3.37, October 2026)

A module of the existing ProTrackAI application (menu: after Cost Control). It is not a separate app. It adds no second project, user or WBS database for budgets, and it does not change Cost Control.

## 1. Existing architecture found (and reused)

| Part | What is there | Used for |
|---|---|---|
| Application | One page of plain JavaScript (`live.html`; `demo.html` and `index.html` are made from it by `tools/make_demo.py`) | The module is one section of it (`v3.35: Budget & Cost Management`) |
| Server | Supabase: Postgres with row-level security; actions as `rpc` functions; private storage buckets | Update v39: tables, functions, bucket `bcm-tender` |
| Security | Rights by role and by person (`can()`, `pt_right`); screens by role (`pt_screens`, Settings → Role access); projects in access (`accessIds`, `user_sees`); positions (Head of Planning and Cost Control) | Four new rights, the screen `bcm`, project-level reads |
| Libraries already loaded | SheetJS 0.18.5 (Excel), SHA-256 (Web Crypto) | Reading workbooks, fingerprints, exports |
| Design | The app's panels, KPI tiles, chips, tables and drawers (the BOQ Engine module's layout) | The same classes; no second design system |
| Cost Control | Dashboard, EVA, Master Manpower Costing Sheet, monthly cost report, budget supplements, logs | Untouched; tested still opening |
| Not present | A server-side file processor; an approved AI provider; any SAP interface | See 5 and 7 |

## 2. Data model (v39)

| Table | One row per | Changes |
|---|---|---|
| `bcm_master` | WBS element (`W-…`; v3.36: with `order`, `sap_seg` and `user_field` in its data), rule (`R-…`), approved mapping (`M-…`), the settings (`cfg`); `cur` = version in force, `pend` = change waiting, `ver` | Only `bcm_master_act` (propose, approve, reject, approve_many) |
| `bcm_master_hist` | Proposal, approval, rejection or withdrawal, with the full content and version | Append only (trigger) |
| `bcm_batches` | Tender submission: project, tender reference, revision, currency, project type | `bcm_batch_save` (create, withdraw) |
| `bcm_files` | Workbook: name, SHA-256 (unique per project unless withdrawn), size, kind, stored path, status, run, sheets, control total, mappings, log, fingerprint, engine | `bcm_file_add`, `bcm_file_run` |
| `bcm_lines` | Extracted row of a run: sheet, row, kind, code, description, quantity, unit, rate, amount (numeric 24,6), source of the amount, formula, currency, cell references, section headings, breakdown, flags | Insert only, by `bcm_file_run`; never updated or deleted (trigger) |
| `bcm_class` | Classification of a line: status, WBS, cost type, confidence, layer, explanation, evidence, alternatives, flags, the mapping or rule and its version, normalized text, corrections, engine, decision | `bcm_classify` (engine results), `bcm_review` (people) |
| `bcm_class_hist` | Every status change of a line, with the previous state and the reason | Append only (trigger) |
| `bcm_audit` | Every material action | Append only (trigger) |
| Storage `bcm-tender` | Original file at `bcm/<project>/<batch>/<sha256>.<ext>` | Insert by `bcm.upload`; read by project and cost right; no update or delete rule |

Reads: master data needs the cost-figures right; everything else also needs the project in access (`pt_bcm_reads`). Lines are read with `bcm_lines_read`, which returns exact amounts as text.

### The specification's conceptual model, and where each part is

| Specification | Here |
|---|---|
| WBS_Master, WBS_Classification_Rules, Mapping_Learning_History | `bcm_master` (ent wbs, rule, map) + `bcm_master_hist` |
| Tender_Import_Batch, Source_Workbook, Extracted_Cost_Line | `bcm_batches`, `bcm_files`, `bcm_lines` |
| Classification_Result | `bcm_class` + `bcm_class_hist` |
| Audit_Log | `bcm_audit` |
| Duplicate_Link, Cost_Allocation, Reconciliation_Result, Budget_Version | v3.37: `bcm_roles` + `bcm_dups`, `bcm_alloc`, `bcm_totals` (computed) + `bcm_recon_notes`, `bcm_versions` + `bcm_version_lines` + `bcm_version_hist` |
| Budget_Change_Request | A new version of kind Approved revision, with its justification and comparison (v3.37) |
| SAP_Import_Batch, SAP_Cost_Record, SAP_Export_Batch | Stage 4 (not built) |
| Approval_History | Approval History page: the approvals and decisions of `bcm_audit` with the version histories (v3.37) |

## 3. The fifteen logical services

| Service | Where | State |
|---|---|---|
| 1. File upload | `bcmUpload`, `bcmStoreFile`; `bcm_file_add`; bucket rules | Built |
| 2. Workbook extraction | `BCME.checkFile`, `readBook`, `extractBook` (engine block) | Built, runs in the uploader's browser (see 5) |
| 3. Source normalization | `BCME.norm`, `normUnit`, `normCur`, `attrsOf`, `lexicon` | Built |
| 4. WBS master | WBS Mapping Master; `bcm_master_act` | Built |
| 5. Rule-based classification | `BCME.classify` layers 1–2; checked again by `bcm_classify` | Built |
| 6. AI classification | `BCME.classify` layer 3: similarity in ProTrack; provider hook validated by `BCME.validateAi`, **not configured** | Built as similarity; no outside AI (see 7) |
| 7. Duplicate & backup analysis | Same-file refusal (SHA-256); `BCME.proposeRoles`, `findDups`, `dupEffect`; `bcm_stage3` | Built (v3.37) |
| 8. Reconciliation | Control totals per file; Reconciliation Centre; `pt_bcm_eval`, `bcm_totals`, `pt_bcm_tol` | Built (v3.37) |
| 9. Human review | Classification Review, line view; `bcm_review` | Built |
| 10. Mapping learning | Remember-as on decisions; Mapping Learning History; performance report | Built |
| 11. Budget versioning | Budget Versions; `bcm_version_act` (from a batch, import, submit, review, approve, reject, cancel) | Built (v3.37) |
| 12. Cost summary | — | Stage 4 |
| 13. Excel export | Exception list, all lines, WBS master | Built (the SAP loading workbook is stage 4) |
| 14. SAP import | — | Stage 4 |
| 15. Audit and approval | `bcm_audit`, histories; master-data approvals with segregation | Built, with budget approvals (v3.37) |

## 4. Roles

| Specification role | In ProTrack |
|---|---|
| Costing Engineer | Role `costing`: `bcm.upload` and `bcm.review` by default |
| Cost Control Manager | A person given `bcm.master` and/or `bcm.approve` (Settings → Roles and rights), or the Head of Planning and Cost Control by position |
| Administrator | Super admin; proposes and approves, never their own proposal |
| Planning Engineer, Project Manager, Read-Only Executive | See the module with the cost-figures right; no write right by default |
| Budget preparer | `bcm.budget` (costing engineers by default) |
| Finance Reviewer | `bcm.review` |
| Budget Approver | `bcm.budget.approve` (Head of Planning and Cost Control by position, or given by the super admin) |
| SAP Authorized User | Right to come with stage 4 |
| Foreman (site roles without cost figures) | Never see the module |

Every rule is enforced by the server functions; hiding a button is only for convenience.

## 5. Where the file is read, and why

Supabase has no file-processing service in this project, and the app already reads Excel with SheetJS. So the uploader's browser reads the workbook. The server:
- keeps the original, unchanged, in the private bucket;
- stores each line as sent, inside a counted run (`bcm_file_run` start, lines, done);
- checks every rule that matters for money and control again, in the database:
  - only approved, active, postable elements as destinations;
  - automatic classification only from the named approved mapping or rule leading to that element, at or above the threshold, with a cost type, without forcing flags;
  - its own reading of the amount against the value limit, and of the element's mandatory review;
  - people's decisions never overwritten;
  - reasons for overrides, rejections, exclusions, corrections and undo;
  - bulk confirmation skipping what needs individual review;
  - segregation of proposal and approval.

**Verify reading** lets anyone with access read the stored file again and compare its fingerprint with the stored rows. A server-side reader (an Edge Function with SheetJS) can replace the browser reading later without changing the tables.

## 6. Arithmetic

Amounts are exact decimals (BigInt, 6 places) in the app and `numeric(24,6)` on the server, and they travel as text. They are rounded only for display, to the currency's places. A missing amount stays missing and is never zero. Totals are per currency; no conversion is done.

## 7. AI and outside services

No outside AI is called: ProTrack does not send company data to an outside service. Layer 3 is a word-similarity match against the approved master and mappings, computed in the page. It is labelled "Similarity (not AI)" and never classifies automatically.

The engine has a provider hook. Its output must name an approved, active element and a known cost type, carry a confidence from 0 to 1, and give no amount; otherwise it is refused and the line stays for a person. A provider can be added only as an approved server function (keys on the server).

## 8. Files

| File | What it is |
|---|---|
| `live.html` (and `demo.html`, `index.html`) | The engine (`BCM-ENGINE-BEGIN` … `BCM-ENGINE-END`), the module, menu, rights, server loading, demo sample |
| `supabase/schema-update-v39.sql`, `schema-rollback-v39.sql` | The server side |
| `supabase/tests/test_v39.py` | Database tests (105) |
| `tests/bcm_engine_test.cjs` | Engine tests in Node with SheetJS (74) |
| `tests/bcm_demo.py`, `tests/bcm_e2e.py` | The demo page, and the live app against the database |
| `tests/fixtures/bcm/` | Test workbooks and `make_fixtures.py` (all test data) |
| `STAGE-33-SETUP.md`, `RELEASE-NOTES-v3.35.md`, this file | Setup, release notes, handover |

## 9. Acceptance criteria of the specification

| Criterion | State |
|---|---|
| Original source values and references remain available | **Met**: lines frozen, file kept, runs kept |
| Every accepted amount can be traced to its source | **Met**: file, sheet, row, cells, formula on each line |
| No backup cost is counted twice | **Met** (v3.37): sheet roles and decided candidates; the server refuses a version while a blocking candidate is open |
| Accepted allocations reconcile to their source amounts | **Met** (v3.37): a split must add up to the line (within the tolerance, at most 1) and is approved by someone else; no percentage is assumed |
| Unresolved items cannot silently enter an approved budget | **Met** (v3.37): `bcm_totals` must be ready for a version from a batch |
| AI cannot create or approve WBS codes | **Met**: no AI; the provider hook is validated; codes only through proposal and approval |
| AI cannot alter financial amounts | **Met**: classification never writes an amount; outputs with amounts are refused |
| Historical approved budgets remain reproducible | **Met** (v3.37): version lines frozen after the draft (trigger), with the WBS version they used |
| The Excel export contains only eligible records | Stage 4 (SAP loading workbook) |
| Failed AI processing does not destroy imported data | **Met** (tested) |
| Unauthorized users cannot approve or change master data | **Met** (server tests) |
| Existing Cost Control workflows continue to function | **Met** (tested opening; console scripts as on main) |
| No unsupported SAP integration is presented as operational | **Met**: none exists; exports say nothing went to SAP |

## 10. For S/4HANA, after go-live and authorization
- **Optional SAP WBS on each element.** Each WBS element already has an optional SAP WBS mapping, and the budget export (stage 4) will use configurable templates.
- **Monthly SAP ECC reports are the current path.** Until go-live, they come in as Excel through the stage 4 import.
- **An approved interface later replaces the import and the export.** The tables are designed for it: imports and exports as batches with references and statuses. A load is confirmed only with the SAP reference returned by SAP.
- **No direct database writes.** ProTrack will never write directly to an SAP database, and no write-back is ever simulated.

## 11. v3.36: order, SAP WBS ID and user field
- **Each WBS element's data carries three more fields:**
  - `order` (among its siblings);
  - `sap_seg` (its SAP WBS segment);
  - `user_field` (a code of the user field list of Settings → Supplement lists, `pt_supp_lists()`, shared with the budget supplements).
- **SAP WBS ID on a project** = `pcode(project)` (its PE number from the Tender register, else the project code) + the segments from the top, joined by the separator. Separator and digits per level are in the settings (`cfg.sap`, default `-` and 2-3-2, the last repeating).
- **Checks** (`pt_bcm_check`, and the same in the app):
  - segment digits for the level;
  - user field in the list;
  - order a whole number.
  - At approval, a segment already used by an approved sibling (not moving away) is refused.
- **Ordering and numbering are proposals** like any master change. Someone else's waiting change is never overwritten by a reorder or a numbering.
- **Upgrading the starting master:** `schema-update-v40.sql` brings it to the company layout through `pt_bcm_seed_upd`, as System seed proposals only. The demo page does the same through `seedBcm336`.

## 12. v3.37: stage 3, financial controls
- **Which lines count** is one rule, in `pt_bcm_eval` on the server and `bcmEval` in the app: a cost line counts when its sheet's role is summary or breakdown (no role yet means summary), or a decided candidate includes it; and it is not a target of a decided candidate; and it is not Excluded with Reason. It is resolved when it has an approved split, or is Auto-Classified or Confirmed with a WBS.
- **Candidates** (`BCME.findDups`) have stable ids from their lines. Saving an analysis keeps decided candidates, refreshes open ones and marks the missing ones Obsolete. `dupEffect` (and the server, which works it out itself) gives `targets` (stop counting) and `includes` (count whatever their role).
- **Tolerance** (`tolOf`, `pt_bcm_tol`) = the larger of the absolute amount and the percentage of the base, from the settings by currency and project type (default 1 and 0.01%).
- **`bcm_totals(batch)`** returns readiness, the problems (unresolved, no amount, currency, WBS, open candidates, unconfirmed roles, waiting splits, unexplained file variances), the accepted amounts by WBS and cost type, and the counted, not counted and unresolved totals. `bcm_version_act` from_batch uses it and refuses a batch that is not ready.
- **Versions**: one row per WBS (and cost type) with the SAP WBS ID (`pt_bcm_sap_id`) and user field at the time. Imports keep the SAP WBS IDs as written and link a master element by WBS code or SAP WBS ID. Lines can be inserted only while the version is a draft. `prev_id` is the previous approved version of the project at approval.
- **Not built (stage 4):** the cost summary, the SAP report import, the SAP loading workbook, Ready for SAP Loading and SAP Loading Confirmed (the statuses exist).
