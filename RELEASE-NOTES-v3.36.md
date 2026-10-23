# ProTrackAI v3.36: the WBS master's order, SAP WBS ID and user field (October 2026)

Built from your request to change the order of the WBS structure, to upload it from Excel, and to add a **SAP WBS ID** and a **user field** next to the WBS code.

## What changed

### SAP WBS ID
- **Each WBS element has a SAP WBS segment.** The **SAP WBS ID** on a project is the project's **PE number** followed by the segments down the tree, joined by "-":

  | Element | SAP WBS ID |
  |---|---|
  | Site Management | `PE-XXX-01` |
  | SM1 Salaries | `PE-XXX-01-001` |
  | Salaries - Project office team | `PE-XXX-01-001-01` |
  | Salaries - Site office team | `PE-XXX-01-001-02` |

- **Digits per level** are 2, 3 and 2 by default; the last one repeats for deeper levels. The separator and the digits are in **Thresholds and lists**, and changing them is a proposal like any other.
- **The checks:** a segment must have the digits of its level and must not already be used under the same parent. The server checks both.
- **Where the SAP WBS ID shows:** in the WBS master (for the project you choose), in the Classification Review table, in the line view, and in the exports of lines and of the WBS master.
- This is the ID as ProTrack builds it. Nothing is sent to SAP.

### User field
- **Each WBS element has a user field** from the **user field list** in Settings → Supplement lists. That is the same list as the budget supplements: SM, DE, TEC, MTRL.ELC, MAN.ELC, INSTL.ELC, MTRL.MECH, MAN.MECH, INSTL.MECH, MTRL.CVL, MAN.CVL, INSTL.CVL, SAD, FNE, PC ITEMS, PROV. SUM, CONT, MGT.RES and the others. The super admin keeps it, so it can be customised.
- **The server refuses a user field that is not in the list.** Matching ignores capital letters.

### Order
- **▲ ▼ on each element** propose a new order among its siblings. Like every master change, it applies once someone else approves it, and the tree shows the proposed order with the change waiting.
- **Number missing SAP segments from the order** proposes segments for the elements that have none, in their order. Existing segments are not changed.

### Excel
- **The WBS master workbook** now has the columns **Order**, **SAP WBS segment** and **User field**. The export adds the level, the **SAP WBS ID on the chosen project** and the user field description, in tree order.
- **The import:**
  - It reads the same columns.
  - Without an Order column, the order is the row order.
  - It refuses rows whose segment is not digits or whose user field is not in the list, with the reason.
  - Valid rows become proposals.

### The starting master in your company's layout
- **The order and segments follow your user field list:**
  - 01 SM, 02 DE, 03 TEC, 04 MTRL.ELC, 05 MAN.ELC, 06 INSTL.ELC;
  - 07 to 09 Mechanical Material, Manpower and inst (new);
  - 10 Civil;
  - 11 SAD, 12 FNE, 13 PC ITEMS (Prime Cost, new), 14 PROV. SUM (Provisional Sum, new), 15 CONT, 16 MGT.RES.
- **New sub-elements:** SM1 Salaries now has **Salaries - Project office team** (01) and **Salaries - Site office team** (02).
- **Moved and switched off:** Saudization, Financing, Contingency and Management Reserve move to the top level, and "Other approved categories" is switched off.
- **Prime Cost and Provisional Sum** always need individual review.
- **The Civil children:** Civil Material, Concrete and Rebar have MTRL.CVL; Civil Manpower MAN.CVL; Civil Equipment INSTL.CVL. Site preparation, investigation, excavation, backfill and other civil have no user field yet, for you to set.
- **On the server these are proposals of System seed** (STAGE-34-SETUP). Nothing is approved by the update, and a change waiting from a person is left alone.

## Setup
STAGE-34-SETUP.md:
1. Run `supabase/schema-update-v40.sql` and the check (expect 40, 57, 7).
2. Check the SAP WBS IDs and user fields in WBS Mapping Master, and correct them if needed.
3. The approver approves.

## Verified
| Check | Result |
|---|---|
| `supabase/tests/test_v40.py`, PostgreSQL 16 with every update v2 to v40, run after part of the master was approved under v39 and a person's change was waiting. It covers: <ul><li>the seven new elements</li><li>the System proposals on approved and waiting elements</li><li>the person's change left alone and logged</li><li>the moves to the top level</li><li>nothing approved by the update</li><li>approval in order, and SAP 01-001-01</li><li>digits by level</li><li>digits only</li><li>user field in the list (any case)</li><li>the order a whole number</li><li>a segment used twice under one parent refused at approval</li><li>a reorder as a proposal</li><li>running twice</li><li>rollback and again</li></ul> | 27 of 27 |
| `tests/bcm_demo.py`, the demo page. All the v3.35 checks, plus: <ul><li>SAP WBS IDs and user fields in the tree</li><li>the company layout</li><li>the Salaries sub-elements</li><li>▲ proposing the order</li><li>a wrong segment refused and a right one proposed</li><li>a user field outside the list refused</li><li>the export columns and the SAP WBS ID on the project</li><li>the import with order, segments and user fields (two refused, two proposed)</li><li>a browser holding the v3.35 sample master brought to the new layout</li></ul> | 67 of 67 |
| `tests/bcm_e2e.py`, the live app against the database v2 to v40. All the v3.35 checks, plus: <ul><li>SAP WBS IDs after approval</li><li>▲ on the server</li><li>wrong digits and an unknown user field refused by the server</li></ul> | 31 of 31 |
| `tests/bcm_engine_test.cjs` | 74 of 74 |
| The 25 console acceptance scripts, on this version and on v3.35, with the real SheetJS | The same results as v3.35 for all 25 (for example, budget supplements 57 of 57 and Cashflow Dashboard 28 of 28) |

**Not verified:** your company's real SAP numbering. The segments are numbered from your user field list's order; check them against SAP before approving.
