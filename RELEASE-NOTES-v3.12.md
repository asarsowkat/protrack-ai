# ProTrackAI v3.12: L1 and L2 tenders, and the notice of award (October 2026)

## Register an L1 or L2 project
**Projects & Handover → Tender register → Register an L1 or L2 project** now opens as a **full window**, in three parts:
- **Tender:** TE number, PE number, date Tender notified, expected value.
- **Our bid position:** L1 or L2.
- **Project:** name, short name, region, client, location.

**The bid position must be chosen:**
- **L1:** we are the lowest bidder.
- **L2:** we are second lowest. The client may still award us, for example on our past performance, or because it is not happy with the L1 bidder. An optional reason (300 characters) is kept with the project.

**In the register:**
- The table shows the bid position and a new column, *NOA and finance WBS* (or *Awaiting NOA*).
- The Pre-award tile counts L1 and L2 separately.
- The bid position can be changed in the Tender details until the NOA is received; each change is in the history.
- Projects registered before v3.12 count as L1.

## The notice of award (NOA)
The NOA date is no longer typed into the Tender details. When the NOA is received, the **costing coordinator** or a **super admin** opens the project and presses **Record NOA received** with the actual date. That right is a new one, *Record the notice of award*, under Settings → Roles and rights. It goes to the costing coordinator position, and super admins always have it.

**On that date:**

| What happens | Where it shows |
|---|---|
| The project becomes **Active** (from Pre-award) | Status in the register |
| The **finance WBS is released the same day to record the PBG cost** | *NOA and finance WBS* column, the history |
| Stage 3 (*Award, finance WBS and SAP activation*) records both | Stage 3 history and evidence: *NOA received …* and *finance WBS released …, the NOA date, for the PBG cost* |
| A notification goes out | The bell |

**Rules:**
- The NOA date cannot be in the future, before the date Tender notified, or after the contract signing.
- Correcting it needs a reason. The correction moves the finance WBS date with it and is kept in the history as *NOA date corrected*.
- Once the NOA is received, the bid position is fixed.

## Lifecycle wording
- Stage 1 is now **Tender L1 / L2 notification**, and its first deliverable includes the bid position.
- The stage 3 deliverable *Finance WBS sent to Tender for the advance bank guarantee charges* is now **Finance WBS released on the NOA date to record the PBG (performance bank guarantee) cost**.
- Ticks already given are kept.

## On the ProTrack server (live.html)
**How it works for now:** the server's `tender_act` (v7) has no bid position or NOA action yet. Signed in to the server:
- **Record NOA received** saves the date as the award date, as before. The project becomes Active.
- The bid position and the L2 reason are not sent, so server projects show as L1.
- The finance WBS release is not recorded.

**Needs a server update:**
- the bid position and reason;
- the `noa` action with the rights and rules above;
- the finance WBS date, in `tender_act`, with the register history.

## Checks
- `tests/tender_noa_demo.js` runs 22 checks in the browser console on the demo page. It covers:
  - the full window and the required bid position;
  - registering L2 with its reason, and L1;
  - the register columns and that the award date can no longer be typed;
  - rights, and the date rules;
  - recording the NOA, the same-day finance WBS, the history, stage 3 and the notification;
  - corrections, and the fixed bid position;
  - the new right.
- `tests/tender_demo.py`, `tests/lifecycle_demo.py` and `tests/e2e_server.py` now choose the bid position, record the NOA with **Record NOA received**, and use the new stage 1 name.
- The 25 contract value checks and the 24 Project Visual checks still pass.
