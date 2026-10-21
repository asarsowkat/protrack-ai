# ProTrackAI v3.25.1: BOQ Engine sample data (October 2026)

The demo page now opens BOQ Engine with **sample data** for two projects. Everything is labelled sample:
- each drawing is a generated PDF stamped *SAMPLE DRAWING - DEMO DATA, NOT FOR CONSTRUCTION*;
- the rates say *DEMO sample rate, not a price*.

The data is made through the same actions people use: register, verify, calculate, review, approve and release. Every status and history can be seen, and every quantity is worked out by the engine from the sample dimensions.

## Sample data

### OHTL: Riyadh to Qassim 380 kV OHTL, Section 2 (QOT)

**Package:** TL-S2-FDN.

**Structures:**
- tower T-101 foundations (suspension type S, 4 legs);
- tower T-105 foundations (tension type T);
- access road AR-2.

**Drawings:**

| Drawing | Status |
|---|---|
| Type S foundation plan and sections, rev B | IFC, the estimation basis |
| Its rev C | Issued for review, not yet the basis |
| Bar bending schedule | Bar counts read as mm and corrected, with the reason recorded |
| Access road route and cross-section | IFC |
| Type T foundation | Issued for approval, so not eligible |

**Specification:** QOT-SPEC-TL-02.

**Approved assumption:** level ground at T-101.

**Quantities (T-101):**

| Item | Quantity | Note |
|---|---|---|
| Excavation | 322.56 m³ | With the 300 mm working space written on the drawing |
| Blinding C15 | 5.292 m³ | |
| Concrete C35/45 | 51.489 m³ | |
| Backfill with reused material | 265.779 m³ | |
| Disposal | 56.781 m³ | |
| Formwork | 81 m² | Pad soffits excluded: cast on blinding |
| Steel | 3,962.71 kg | From the bar schedule |

**Quantities (AR-2):** topsoil stripping 1,800 m³ and subbase 2,880 m³.

**Estimate:** rev 0 is released (quantities only) and handed off to cost control (recorded only).

**After the release:** T-105 is added as a provisional line.

### Substation: Jubail 380 kV Substation (JBS)

**Package:** SS-CIV-01.

**Structures:**
- Power Transformer T1 Foundation;
- Cable Trench CT-1;
- GIS Building.

**Drawings:**

| Drawing | Status |
|---|---|
| T1 foundation plan and sections | IFC |
| T1 reinforcement details | IFC |
| Cable trench route and sections, rev 2 | Replaced as the basis by rev 3 (road crossing extended to Ch 0+275) |
| GIS building foundation layout | IFC |
| GIS building GA | Approved, waiting for a reviewer's confirmation |
| Boundary wall | Uploaded, waiting for registration, with its proposals and evidence |

**Specifications:** JBS-SPEC-CIV-01, and a client standard whose structural concrete grade (C35/45 against C40/50) is flagged as a conflict.

**Assumptions:** working space 500 mm (approved), reuse of excavated material (approved), duct encasement excluded (draft).

**Quantities (T1 foundation):**

| Item | Quantity | Note |
|---|---|---|
| Excavation | 90 m³ | Working space from the approved assumption |
| Blinding | 5.85 m³ | |
| Concrete C40/50 below FGL | 54 m³ | |
| Concrete C40/50 above FGL | 3.6 m³ | |
| Backfill | 30.15 m³ | |
| Disposal | 59.85 m³ | |
| Formwork | 33.8 m² | |
| Raft steel | 2,944.41 kg | Includes the 2.5 % wastage from the specification |

**Quantities (trench CT-1, rev 3):**

| Item | Quantity |
|---|---|
| Excavation | 381.6 m³ |
| Sand | 82.8 m³ |
| Ducts | 1,290 m |
| Tiles | 370 No. |
| Tape | 550 m |
| Selected backfill | 272.863 m³ |

**GIS building:** footing excavation is *Incomplete* (depth awaited), so the building is *Partial estimate only*.

**Estimates:**
- rev 0 is released, with sample rates;
- rev 1 is ready for review, showing the trench change and its cause in Revision Comparison.

## Fixes

- **Text inputs from a source:** an input such as the concrete grade, taken from a verified specification requirement, was treated as missing.
- **Wastage from a source:** a wastage taken from a specification requirement or an approved assumption was not kept when the calculation was saved.
- **Conflicts:** requirements of one topic now conflict only when they apply to the same thing. Requirements have an optional "applies to", such as structural concrete or blinding, so C40/50 and blinding C15 no longer conflict.
- **Drawing lists:** access roads and earthing systems are checked against the general drawing list, not the foundation list.
- **Line descriptions:** lines from a calculation with several items name their item, for example *Ducts and conduits: Cable trench CT-1*.
- **Opening project:** BOQ Engine opens on the first project that has an estimation package.

## Notes

- **Demo page only:** the sample data is never on the server. *Reset demo data* reloads it.
- **Existing demo browsers:** they get it the first time the page opens.

## Checks

| Suite | Result |
|---|---|
| `tests/boq_sample_demo.js` | 14 checks |
| `tests/boq_engine_demo.js` | 52 checks (now on Riyadh Metro, which has no sample data) |
| Intermediate milestones | 17 checks, still passing |
| Reporting status | 28 checks, still passing |
