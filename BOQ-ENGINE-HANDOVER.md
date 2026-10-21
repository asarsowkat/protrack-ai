# BOQ Engine: engineering handover (ProTrackAI v3.25, October 2026)

BOQ Engine is a module of the existing ProTrackAI application (menu: after Invoices & Cash Flow). It is not a separate
app and it does not add a second project, user or cost database.

## 1. Existing architecture found

| Part | What is there |
|---|---|
| Application | One page of plain JavaScript (`index.html`; `demo.html` is a copy of it; `live.html` uses the server) |
| Demo copy | Data in the browser (`DB`, localStorage); files in IndexedDB (`DOCIDB`) |
| Live copy | Supabase: Postgres with row-level security, actions as `rpc` functions, private storage buckets |
| Security | Rights by role and by person (`can()`, `pt_right` on the server), screens by role, projects in access (`accessIds`, `user_sees`), audit logs |
| Libraries already loaded | pdf.js 3.11 (PDF reading and rendering), SheetJS (Excel), jsPDF, SHA-256 (Web Crypto) |
| Not present | OCR, a vision AI provider, a server-side job queue |
| Tests | Browser acceptance scripts in `tests/*_demo.js`, run on the demo page |

## 2. What was built

### Navigation
- **BOQ Engine** sits right after Invoices & Cash Flow, with all twelve sections live.
- Who sees it by default: management, planning, costing and project managers. The super admin can change this in Settings → Role access.

### Master data (super admin)
- Facility types and structure types (the specification's list).
- Each structure type has its required drawings and specifications, so the completeness check is configurable.
- Item categories with unit and discipline.
- Drawing statuses, with whether each one is eligible for estimating.
- Rounding rules, calculation templates (switch on or off, and add product templates), and AI and OCR settings.
- Everything can be added and switched off without code.

### Hierarchy
Project (from the project master) → estimation package (contract or package, site, voltage or project type) → structure (facility, discipline, structure type, unique name, WBS code from the P6 data) → drawings → dimensions → calculations → Estimated BOQ.

### Drawing register
- **One record per revision:** a revision is never overwritten or deleted.
- **Mandatory metadata:** every field in section 5 of the spec, plus the optional fields.
- **Duplicate checks:** the same file (SHA-256) is refused, and so is the same number with the same revision.
- **Superseding:** needs a reviewer.
- **Estimation basis:** changes only with an explicit confirmation.
- **Four separate statuses:** document, extraction, calculation and estimation.
- **Approved, IFC and as-built statuses** count for estimating only after a reviewer who did not register the drawing confirms them.

### Upload and classification
- **Checks:** PDF type, size (configurable, 40 MB by default), readability and passwords; PDFs with scripts, launch actions or embedded files are refused.
- **Storage:** the original file is kept unchanged.
- **Reading:** done in the background, with progress, retry and a record of each error. Running it again is safe and keeps everything verified or entered.
- **What the PDF text layer gives:**
  - the drawing number, revision, scale, title and units;
  - a structure type proposed only when its distinctive words appear and it clearly leads the next candidate, with a confidence and the matched words;
  - the discipline and the drawing contents (plan, sections, reinforcement detail, bar bending schedule, route, cross-section and so on);
  - dimension texts with their page and position: plain dimensions, levels, bar notation and chainages.
- **Confirmation:** every value is a proposal. A person confirms the metadata in a guided form, and uncertain classifications are left for the person to choose.

### Review and measurement
- **Viewer:** the page with page navigation and zoom. Extracted dimensions are drawn at their recorded position; one without a position shows its page and text only.
- **Checking dimensions:** verify, correct (a reason is required for a change of value, and dependent quantities are recalculated) or reject.
- **Naming:** a dimension can be named for use in calculations.
- **Calibration:** two points on a known dimension. It is checked against the written scale, and a difference over 2% is flagged.
- **Measuring:** a measured distance becomes an unverified dimension, with its calibration recorded.

### Calculation engine
- **Exact decimals:** BigInt with 12 decimal places. The stored values are unrounded; rounding is for display only.
- **Units:** values are converted, and a unit of the wrong kind is refused.
- **Inputs:** each one carries its source: a verified drawing dimension, a verified specification requirement, an approved assumption, another calculation's output, or a value a person entered with a note.
- **Missing or failed inputs:** a missing input gives *Incomplete*; an error gives *Calculation Error*. Neither is ever turned into a zero.
- **Recorded with each calculation:** the formula, inputs, sources, drawings and revisions, assumptions, wastage, net, allowance and estimated quantity, the working, the engine version, the date, the verifier and the full change history with its reason.

### Completeness, specifications and assumptions
- **Completeness check:** each requirement of a structure is Available, Missing, Not Applicable, Awaiting Clarification, or Available but Unverified (for example a scanned sheet that cannot be read). The structure is then Ready, Partial estimate only, or Not ready.
- **Specifications:** a register with optional PDFs. Requirement proposals are read from the text (concrete and steel grades, compaction, wastage, bedding, cover) and must be verified. Conflicting values are flagged and never chosen automatically.
- **Assumptions:** each has its ID, reason, source, value, affected items, and a review and approval by someone other than its author.

### Estimated BOQ
- **Content:** every field in section 11, with lines that are provisional where the drawing package is incomplete or a drawing is not eligible.
- **Views:** by discipline, structure, trench type, location and package, with totals.
- **Rates:** optional, entered only by people with the rate right and with their source. Amount = quantity × rate.
- **Labels:** *Drawing-Based Estimated Quantity* and *Internally Released Estimated Quantity*. Approved BOQ, approved budget and actual quantities are shown separately, as not available.
- **Line detail:** click through to the calculation, its inputs and the dimension on the drawing.

### Workflow
- **Statuses:** Draft → In Progress → Ready for Review → Under Review → Approved for Internal Use → Released → Superseded, or Returned for Correction.
- **Approval rules:**
  - nobody reviews, approves or releases a revision they prepared or submitted;
  - approval needs every quantity verified;
  - a submission is refused if the calculations changed after the draft was generated.
- **Freezing:** approved and released lines never change.

### Revisions
- **New drawing revision:** the calculations it affects are listed, and its dimensions are compared with the current basis.
- **Changing the basis:** needs confirmation and marks the dependent calculations *Recalculation Required*.
- **Re-linking:** moves named dimensions to the new revision.
- **Comparing estimate revisions:** each item is unchanged, added, removed or modified, with the variance, the % (only when the previous quantity is not zero) and the source of the difference from the recorded change reasons.

### Excel and dashboard
- **Excel workbook:** the eight sheets of section 11. The Estimated BOQ sheet has amount formulas, and Detailed Calculations shows every input with its source.
- **Dashboard:**
  - the eleven figures of section 19, counted from the records, each opening its list;
  - filters by project, package, discipline, facility, structure type, drawing status and estimation status;
  - the estimation summary, and the 17-step workflow with each step's state.

### Hand-off and audit
- **Hand-off:** recorded, confirmed requests to cost control, procurement or cash flow. BOQ Engine writes nothing to those modules.
- **Audit history:** every action, with filters.

## 3. Files

| File | What it is |
|---|---|
| `index.html`, `demo.html`, `live.html` | The module (section "v3.25: BOQ Engine"), its menu, rights, styles and live-mode loading |
| `supabase/schema-update-v31.sql`, `schema-rollback-v31.sql` | The screen in Role access (v3.24) |
| `supabase/schema-update-v32.sql`, `schema-rollback-v32.sql` | The server side of this release |
| `tests/boq_engine_demo.js` | 52 acceptance checks |
| `STAGE-27-SETUP.md` | The server setup, step by step |
| `RELEASE-NOTES-v3.25.md` | The release notes |
| `BOQ-ENGINE-HANDOVER.md` | This report |
| `README.md`, `guide.html`, `supabase/README.md` | Updated to v3.25 |

## 4. Database changes (v32, not yet run on a database)

**New:**
- Five rights: `boq.upload`, `boq.estimate`, `boq.review`, `boq.approve`, `boq.rate`. The Head of Planning and Cost Control holds review and approve by position.
- Tables `boq_packages`, `boq_structures`, `boq_drawings` (one per revision), `boq_dimensions`, `boq_calculations`, `boq_specifications`, `boq_assumptions`, `boq_estimates`, `boq_handoffs`, `boq_master` and `boq_audit`. Each row has id, project and the record, with project-level read access (`can_see`).
- Unique indexes on number + revision and on the file fingerprint.
- `boq_save(p)`, the only way to write. It enforces the rules in section 2 above and writes an audit entry.
- A private bucket `boq-drawings`, readable by people who see the project and writable by the upload and estimate rights.

**Not changed:** existing tables and functions, except that `pt_rights()` and `pt_right_default()` are extended.

**Undo:** the rollback removes the writes and keeps all data.

**Not verified:** no Postgres was available here, so v32 has not been run. Run it on a staging copy first.

## 5. AI, OCR and PDF processing: what is configured

| Capability | Status |
|---|---|
| PDF text and position extraction, page rendering | **Configured**: pdf.js 3.11, in the browser |
| Classification and dimension proposals | **Configured as rules** over the PDF text layer, with confidence and evidence; never approval |
| Vector geometry (lines, arcs, hatches) | **Not implemented**. Measurement uses calibration and two points |
| OCR for scanned sheets | **Not configured.** Such sheets are marked *Needs OCR*; their dimensions are entered or measured by hand |
| Vision AI provider | **Not configured.** Settings → AI records a provider and its authorization; no request is sent. A server function holding the key is needed |
| Document text as instructions | Never: text is only matched against fixed patterns |

## 6. Quantity calculations supported

| Template | What it measures |
|---|---|
| Rectangular excavation | Zones, optional working space and side slope (prismoidal formula), overlap deduction; each only when specified |
| Strip or trench excavation | By chainage; overlapping segments are refused |
| Cable trench (direct buried) | By chainage: excavation, sand bedding, ducts (m), protective tiles (No.), warning tape (m), selected backfill less sand and duct volume. Cables never multiply the trench |
| Backfilling and disposal | Excavation less displaced permanent works and exclusions. Material class; a factor only with a specification or approved assumption; disposal of surplus after reuse, or of all excavated material |
| Concrete | Solids less openings less interface deductions; blinding, plain or reinforced; the grade is required and never inferred |
| Formwork | By face; excluded faces are listed with their reason |
| Reinforcement from a bar schedule | d² ÷ 162 × length × number, with totals by diameter |
| Reinforcement from diameter and spacing | floor(distribution ÷ spacing) + 1 bars, laps and hooks only if detailed |
| Measured items | Volume, area, length or number, with deductions (masonry, plaster, paint, flooring, waterproofing, doors, roofing and so on) |
| Super-admin templates | Product of up to six inputs |

## 7. Tests run

| Suite | Result |
|---|---|
| `tests/boq_engine_demo.js` | **52/52** |
| Earlier suites: intermediate milestones 17, reporting status 28, executive report 11, cash-out 26 and 24, delay register 26, baselines 18, Project Visual 24 | All still pass |

The 52 BOQ Engine checks cover section 20 of the spec:

- **A. Drawing registration (11):**
  - a valid registration, and the classification proposal with its evidence;
  - missing metadata named;
  - duplicates refused, by file and by number + revision;
  - invalid files refused: not a PDF, a fake PDF, a PDF with scripts;
  - role permissions: site engineer, foreman;
  - status confirmation by someone else.
- **B. Calculations (13):**
  - the five fixtures of the spec: 30 m³, 6 m³, 96 m³, 158.02 kg, 24 m³;
  - mm-to-m conversion;
  - an overlap refused;
  - a missing input gives Incomplete, not zero;
  - wastage without a basis refused;
  - negative backfill an error;
  - sloped prismoidal volume 40.667 m³;
  - trench lines;
  - a wrong unit refused.
- **C. Workflow (21):**
  - verification of sources and calculations, and calculations built on calculations;
  - completeness: partial estimate;
  - the draft BOQ with provisional lines;
  - the rate right;
  - no self-review;
  - review, approval and release;
  - released lines frozen while the calculations change;
  - dependants recalculated;
  - revision comparison with the cause of each difference;
  - a new drawing revision, its explicit basis change, recalculation flags and re-linking;
  - the Excel sheets;
  - the audit;
  - the hand-off.
- **D. Budget protection (1):** every ProTrackAI record outside BOQ Engine is identical before and after the whole workflow.
- **E. Error handling (6):** unreadable PDF, conflicting requirements, invalid units, AI settings without authorization, a processing failure with retry, an unresolved line without a quantity.
- **Not runnable here:**
  - server-side tests: no database;
  - the AI provider and OCR: not configured;
  - processing timeouts are not simulated.

**Checked by hand in the browser:**
- all twelve sections and their forms open without errors;
- the calculation editor (zones, unit conversion, the working, item codes);
- the review buttons (the preparer is not offered the review);
- the viewer with highlighting and zoom;
- the phone layout at 375 px: no horizontal scroll.

## 8. Existing features and budget data protected

- BOQ Engine code writes only to `DB.boq` (on the server, the `boq_*` tables).
- Check D1 compares every other record before and after uploading, calculating, approving, releasing and handing off, and finds them identical.
- `boq_save` has no write path to any other table.

## 9. Configuration needed

| Item | Needed for |
|---|---|
| v31 and v32 database updates (STAGE-27-SETUP) | BOQ Engine on the live server |
| An OCR engine as a server function (e.g. Tesseract or a cloud OCR approved for project drawings) | Scanned sheets |
| A vision AI provider, through a server function holding the key and a data processing agreement | AI-assisted interpretation beyond the text-layer rules |

No API key is stored in the app or in these files.

## 10. Deployment

1. Run `schema-update-v31.sql`, then `schema-update-v32.sql` (STAGE-27-SETUP.md), on a staging copy first.
2. Publish the files. `live.html` loads BOQ Engine records at sign-in, and every change is saved through `boq_save`.
3. In Settings → Roles and rights, give *BOQ Engine: review* and *approve* to the lead engineers and estimation managers, or rely on the Head of Planning and Cost Control position.

## 11. Known limitations

- **Scanned sheets:** nothing can be read from them until OCR is configured.
- **Vector geometry:** lines are not measured automatically.
- **Unusual text:** dimension proposals come from text items. Dimension strings split across several text items, or rotated text, may be missed and are entered by hand.
- **DWG and DXF:** not accepted; export them to PDF first.
- **Where quantities are worked out:** in the app, with the engine version recorded. The server stores them and enforces the governance rules but does not recompute them.
- **Background jobs:** they run in the uploader's browser. Closing the tab stops a job; it can be retried.
- **Same-day codes:** item and assumption codes are numbered in the browser. On the live server, two people adding at the same moment can collide; the server refuses a duplicate drawing revision or file.

## 12. Remaining tasks

- Run v31 and v32 on staging and test live mode with several users.
- A server-side recalculation service, so the server recomputes and checks quantities.
- OCR and AI provider functions, once approved.
- Vector geometry extraction for vector PDFs.
- Cost-control interfaces that accept hand-offs, with their own approval.

## 13. Sample data on the demo page (v3.25.1)

The demo page opens BOQ Engine with sample data for the Riyadh–Qassim OHTL (QOT) and the Jubail 380 kV substation (JBS), all labelled sample, made through the module's own actions: see RELEASE-NOTES-v3.25.1.md. It is never on the server. Checks: `tests/boq_sample_demo.js` (14).

## 14. Testing with a real substation drawing package

1. Sign in as a planning engineer of the project, and choose **BOQ Engine → Project & WBS Setup**.
2. Create a package: code, name, site, voltage. Add the structures, for example *Transformer T1 Foundation* (Power Transformer Foundation, Structural, WBS code).
3. **Drawing Upload & Classification:** choose the PDFs (plans, sections, reinforcement details, bar schedule) and upload.
4. When reading is done, **Register** each one. Check the proposed number, revision, scale, units and classification against the title block. Choose the structure, status and contents.
5. As a lead engineer (another person), open **Drawing Register** and confirm the approved or IFC statuses.
6. **Specifications & Assumptions:** register the specification (the PDF is read for proposals) and verify the concrete and steel grades.
7. **Drawing Review & Measurement:** open each drawing and verify or correct the dimensions you will use, naming them (e.g. "foundation length L"). On drawings to be measured graphically, calibrate on a written dimension first.
8. **Project & WBS Setup → Completeness:** check each structure; mark what does not apply.
9. **Quantity Calculation Register → New calculation:** choose the structure and the template (excavation, concrete, formwork, reinforcement from the bar schedule, backfill). Pick each input's source from the verified dimensions, specification or assumptions, then **Work it out** and **Save**. Verify each calculation.
10. **Review & Approval Workflow:**
    - start a revision and generate the draft Estimated BOQ;
    - optionally enter rates (rate right), then submit;
    - another person reviews, approves and releases it.
11. **Reports & Excel Export:** export the workbook and check the eight sheets.
12. Register a revised drawing and make it the basis in **Revision Comparison**. Re-link and recalculate, then compare the new revision with the released one.
