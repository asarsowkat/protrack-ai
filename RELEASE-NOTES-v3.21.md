# ProTrackAI v3.21: cash-out from the material POs on P6 dates and the cost report (October 2026)

The cash-out forecast (v3.20) is now built from what the system already holds:
- **the material POs of Material tracking**, paid on their stage dates from the P6 updated schedule;
- **the subcontract POs**, as in v3.20;
- **the monthly cost report** for every head without a PO (site management, manpower and the rest).

It is reconciled with Finance's monthly cash-out, and the timing differences are shown apart from what is unexplained.

## Material POs: payment terms on the Material tracking PO numbers
- **Every PO number entered in Material tracking** is a material PO. One PO can cover several materials.
  - In **Material tracking**, each PO number now shows its value and terms, with **Add payment terms** / **Payment terms**.
  - In **Cash-out forecast → PO payment schedules**, the same POs are listed first.
- **Per PO:** value (SAR), payment terms text, status. A changed value needs its **revision reference and reason**, and the original value is kept.
- **Per milestone:** % of the PO value or a fixed amount, contractual payment days, retention or deduction, status (paid needs its date and Finance evidence), approval. Each milestone is **paid at** one of these:
  - a **Material tracking stage**: PR creation, PO creation, base design, GAFM approval, manufacturing, FAT, release for shipment, delivery at site, civil readiness
  - the **P6 TCC** or **final acceptance** milestone
  - a **fixed date**
- **Expected payment** = the stage's date + the payment days.
  - The stage's date is the actual date once the stage is done, otherwise the **P6 forecast** of the latest updated schedule.
  - For a PO with several materials, the latest of them.
  - **When the schedule slips, the payments move with it.**
- **Standard schedule:** 10% at PO creation, 20% at FAT, 60% at delivery to site, 10% retention at TCC.
- **Not ordered yet:** materials without a PO number are listed as not ordered; their cost is in the cost report ETC.
- **Approval:** as for the subcontract POs. The first approved date is each milestone's baseline.

## The cost report by WBS head
**PO payment schedules → Cost report heads** shows the latest released monthly cost report by WBS head. Each head has a treatment:

| Treatment | Default heads | In the forecast |
|---|---|---|
| **Material POs** | Electrical, Mechanical, Civil Material | the material PO milestones, plus the head's **ETC (H)**: cost not yet ordered |
| **Subcontract POs** | Electrical, Mechanical inst, Civil Equip | the subcontract PO milestones, plus the head's ETC |
| **Cost report** | Site Management, Design, Testing, the Manpower heads, Saudization, Financing | **EAC − Actual** (= Commitment F + ETC H), spread evenly from the month after the cutoff to the **P6 forecast TCC** |
| **Excluded** | Contingency, Management Reserve, Prime Cost, Provisional Sum | nothing: not cash-out until used or instructed |

- **Changing a treatment:** the keepers can change any head and switch off the ETC of the PO heads. A head belongs in one place only; for example, a manpower head paid through a manpower supply PO goes with the subcontract POs.
- **A PO head with no PO recorded** (for example, material heads on a project without POs in Material tracking) falls back to the cost report, with a warning.
- **The planned baseline** of the cost-report heads is their current budget (D), spread over the project.

## Reconciliation with Finance's monthly cash-out
**Reconciliation** now opens with a bridge:

| Line | |
|---|---|
| Finance actual cumulative | |
| − paid PO milestones (verified) | material and subcontract |
| − cost booked on the cost-report heads | Actual (E) of the cost report |
| − other lines paid to date | |
| **= difference** | |

**Timing items:**
- **Cost booked, not yet paid**, when Finance has paid less. This is a payable: it is **forecast in the month after the cutoff**, so it is neither lost nor counted twice.
- **PO milestones due, not marked paid:** Finance may have paid them.
- **Retention held** on paid milestones.

**Unexplained** = what Finance paid beyond the records and the milestones due. Above the tolerance (1% of the actual, at least SAR 100k), the status is **Reconciliation Required**.

**Month by month:** expected cash-out = PO payments scheduled + the cost booked that month (the movement between two released cost reports), against Finance's actual.

**Cross-check:** the cash forecast at completion against the cost report EAC without the excluded heads. They converge once retention is paid. A gap over 5% is flagged: the PO values or the head treatments do not match the cost report.

Forecast at completion = Finance actual + PO milestones remaining + cost-report heads (EAC − actual) + ETC of the PO heads + payables (+ other lines).

## Other lines
The v3.20 *other cash-out lines* stay, for cash-out the cost report does not hold. The demo's v3.20 sample line is replaced by the cost report heads.

## Demo
- **Material POs:**
  - Riyadh-Qassim has 3 (ACSR conductor, lattice towers, OPGW) and Jubail has 5 (GIS, transformer, cables, panels, steel)
  - their values come from the material heads' actual + commitment, on the standard terms
  - the milestones whose stage is done and date passed are paid
- **Head treatments:** manpower heads paid through manpower supply or measured POs are set to Subcontract POs.
- **Finance's demo cumulative:** now the paid milestones plus 97% of the cost booked, so a month of payables shows. Ras Tanura keeps SAR 1.2M unexplained.
- **Result:**
  - Riyadh Metro, Jubail and Jazan are within budget
  - Jeddah DC is a Forecast Overrun (102%), with a cross-check gap
  - Riyadh-Qassim is Forecast Incomplete (PO-2026-051 has no terms)
  - Ras Tanura is Reconciliation Required

## Checks
`tests/cashout_p6_demo.js` runs 24 checks. They cover:
- the material POs and the materials not ordered; stage dates and P6 TCC retention; the standard schedule
- a three-month slip moving the payments; value and revision rules; paid milestones locked; incomplete terms
- the default treatments; the spread to the P6 TCC; contingency excluded; the fallback for PO heads without POs; the ETC switch
- payables without double counting; unexplained reconciliation; the EAC cross-check; the monthly expected cash-out
- the screens, the Material tracking link, the Excel sheets, and a project manager reading only

The 26 v3.20 checks pass, with tests 4, 10 and 11 updated to the new composition.

## Server
`schema-update-v28.sql` (STAGE-24-SETUP.md) adds `co_mat_po`, `co_heads` and the new actions. Undo: `schema-rollback-v28.sql`. The SQL has not been run on a database yet.
