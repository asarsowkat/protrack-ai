# ProTrackAI v3.28.1: tender stages in the Project list (October 2026)

The **Project list** now shows where each project stands on the Tender list, and can be filtered by it.

## New columns

| Column | What it shows |
|---|---|
| Bid position | L1 or L2, from the Tender register |
| Tender stage | One of: *L1, awaiting NOA*; *L2, awaiting NOA*; *NOA received (date)*; *Awarded (NOA date not recorded)*; *Cancelled (date)*; *Not from the Tender list* |
| NOA date | The date the notice of award was received |
| Client | From the Tender register |
| Expected value (SAR M) | From the Tender register. Not shown to site roles |

These are in the Excel and PDF too. The PDF stays on A3, in a slightly smaller font for the 29 columns.

## New filter: Tender stage

The options are:
- **Pre-award, L1 and L2:** the pre-award projects;
- **L1, awaiting NOA**;
- **L2, awaiting NOA**;
- **NOA received**;
- **Awarded (NOA date not recorded)**;
- **Cancelled**;
- **Not from the Tender list**.

It combines with the region, sector and status filters. The status filter's **Pre-award** option gives the same pre-award list.

A new summary below the table counts projects by tender stage.

**In RASA**, ask for example:
- *"project list of L2 projects"*;
- *"pre-award project list"*;
- *"project list of NOA projects"*.

## Sample tenders on the demo page

Four sample tenders were added through the Tender register itself, so every stage can be shown. Each is marked SAMPLE in its name.

| PE | Project | Stage |
|---|---|---|
| PE-001 | Dammam 132 kV substation extension | L1, awaiting NOA |
| PE-002 | Taif water transmission pipeline, Lot 2 | L2, awaiting NOA |
| PE-003 | Riyadh data hall fit-out, Phase 3 | NOA received 16 Sept 2026, now active |
| PE-004 | Abha 380 kV overhead line | Cancelled by the client |

They also appear in Projects & Handover → Tender register.

## Two fixes found while testing

**Reporting status:**
- **The problem:** a project awarded after a period ended was still required to report for that period. Recording an NOA could therefore re-open a month or week that was already complete, and hold its executive report.
- **The fix:** a project now reports from the first full week or month after its NOA (or its start date when no NOA is recorded).

**RASA's cash-inflow answer:**
- **The problem:** it failed when a project in scope had no contract value or prices yet, for example a newly awarded tender.
- **The fix:** such projects are now skipped, as on the cash-inflow forecast page.

## Checks

- **Project list suite:** 26 checks, 6 of them new for tender stages.
- **All 20 suites pass**, re-run on the new sample data.
- **BOQ sample suite:** passes.
- **Smoke test:** 11 roles, 220 screens and 233 RASA suggestion answers, with no error.
