# v3.36 setup: the WBS master's order, SAP WBS ID and user field

This takes about 10 minutes. **Do not** upload a new `config.js`. It needs v39 (STAGE-33-SETUP) and v35 (the user field list, STAGE-29-SETUP).

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `supabase/schema-update-v40.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select bcm_features() ->> 'version' as version, (select count(*) from bcm_master where ent = 'wbs') as wbs_elements, (select count(*) from bcm_master where id in ('W-SM1-01','W-SM1-02','W-MEM','W-MEP','W-MEI','W-PC','W-PS')) as new_elements;
   ```

   Expect **40**, **57** and **7**.

**What the update does:**
- **Each WBS element can carry three new fields:**
  - Its **order** among its siblings.
  - Its **SAP WBS segment**: 2 digits at the top level, 3 at the second, 2 below. You can change this pattern in Thresholds and lists.
  - Its **user field**, from the user field list in Settings → Supplement lists (the same list as the budget supplements).
- **The server checks them.** A segment must have the right number of digits for its level, and must not already be used under the same parent. A user field must be in the list.
- **The SAP WBS ID of an element on a project** is the project's **PE number** followed by the segments down the tree:
  - `PE-XXX-01` Site Management
  - `PE-XXX-01-001` SM1 Salaries
  - `PE-XXX-01-001-01` Salaries - Project office team
  - `PE-XXX-01-001-02` Salaries - Site office team
- **The starting master follows your user field list**, in this order, with these segments:

  | Order and segment | User field | Element |
  |---|---|---|
  | 01 | SM | Site Management |
  | 02 | DE | Design |
  | 03 | TEC | Testing & Commissioning |
  | 04 | MTRL.ELC | Electrical Material |
  | 05 | MAN.ELC | Electrical Manpower |
  | 06 | INSTL.ELC | Electrical inst |
  | 07 | MTRL.MECH | Mechanical Material (new) |
  | 08 | MAN.MECH | Mechanical Manpower (new) |
  | 09 | INSTL.MECH | Mechanical inst (new) |
  | 10 | (none) | Civil Works. Its children: Civil Material, Concrete and Rebar are MTRL.CVL; Civil Manpower is MAN.CVL; Civil Equipment is INSTL.CVL |
  | 11 | SAD | Saudization |
  | 12 | FNE | Financing |
  | 13 | PC ITEMS | Prime Cost (new) |
  | 14 | PROV. SUM | Provisional Sum (new) |
  | 15 | CONT | Contingency |
  | 16 | MGT.RES | Management Reserve |

  - SM1 to SM9 are 001 to 009, and **SM1 Salaries** has two new sub-elements: **01 Project office team** and **02 Site office team**.
  - Saudization, Financing, Contingency and Management Reserve move to the top level. "Other approved categories" is switched off.
- **Nothing is approved by the update.** These arrive as **proposals of System seed**:
  - An element not approved yet gets the change in its proposal.
  - An approved element keeps its approved version, and gets a proposal next to it.
  - An element with a change waiting from a person is left alone, and the Audit Log says so.
- **Running the update twice is safe.**

## Step 2: Check and approve (5 minutes)

1. Open **Budget & Cost Management → WBS Mapping Master** and choose a project at the top. The tree shows each element's **SAP WBS ID** on that project (from its PE number in the Tender register) and its **user field**.
2. If your SAP numbering differs:
   - Change an element's segment with **Propose a change**.
   - Or download the master to Excel, correct the **Order**, **SAP WBS segment** and **User field** columns, and import it.
3. **▲ ▼** reorder siblings. **Number missing SAP segments from the order** fills the segments that are still empty.
4. The approver (bcm.approve, not the proposer) presses **Approve all waiting**.
5. To add or rename a user field, use **Settings → Supplement lists** (super admin). That list is shared with the budget supplements.

## If something goes wrong

| What you see | What to do |
|---|---|
| **At level 2 the SAP WBS segment has 3 digits** | Give the segment the digits of its level, or change the pattern in Thresholds and lists |
| **The SAP WBS segment … is already used under the same parent** | Give one of the two another segment |
| **The user field … is not in the user field list** | Add it in Settings → Supplement lists, or choose one from the list |
| The SAP WBS ID shows the project code instead of a PE number | The project has no PE number yet in the Tender register |

## To undo

Run `supabase/schema-rollback-v40.sql`. This goes back to the v39 checks; the order, segments and user fields stay in the records, and the proposals stay waiting, so they can be rejected.
