# ProTrackAI v3.25: BOQ Engine (October 2026)

**BOQ Engine**, *AI-Powered Quantity Take-Off, Engineering Estimation & BOQ Generation*, now works end to end in all twelve sections:
- registering drawing packages;
- reading PDF drawings and specifications;
- verifying and measuring dimensions;
- deterministic quantity calculations with sourced inputs;
- the drawing completeness check, assumptions and specifications;
- the Estimated BOQ with review, approval and release;
- revision comparison, Excel export, the dashboard and the audit history.

An Estimated BOQ can be made without an approved BOQ. Every quantity traces back to its calculation, its inputs, the drawing revision and page, and the assumptions behind it.

**How it treats the numbers:**
- **Nothing is guessed:**
  - values read from a PDF are proposals for a person to confirm;
  - a missing input leaves a quantity incomplete, never zero;
  - rates are never invented;
  - every result is labelled an estimate.
- **Approval:** nobody reviews or approves their own estimate, and released estimates never change.
- **Budget protection:** BOQ Engine never writes to budgets, cost reports, purchase orders, commitments, actual costs, forecasts or earned value. A hand-off to cost control is a recorded request only.

**Configured and not configured:**
- **Configured:** PDF reading uses the text layer (pdf.js).
- **Not configured:** OCR for scanned sheets, and a vision AI provider. Scanned sheets are marked and their dimensions are entered or measured by hand (calibrated measurement).

**Details:** see `BOQ-ENGINE-HANDOVER.md` for:
- the architecture and what was built;
- the calculations supported;
- the tests;
- what is configured and what is not;
- deployment, limitations, remaining tasks;
- how to test with a real drawing package.

**Server:** `schema-update-v31.sql` and `schema-update-v32.sql` (STAGE-27-SETUP.md). They have not yet been run on a database.

**Checks:**
- `tests/boq_engine_demo.js`: 52 checks.
- The earlier suites still pass.
