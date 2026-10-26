# ProTrackAI v3.40.1: the WBS master in Excel, downloaded and imported back (October 2026)

Two fixes for building the WBS master in Excel and loading it into ProTrack (**Budget & Cost Management → WBS Mapping Master → Excel import and export**).

## 1. "Download the WBS master (Excel)" downloads

**What was wrong:** some places host ProTrack in a sandboxed frame and offer their own download feature. The Claude artifact is one: the shared ProTrackAI Demo link runs there. In those places the button did nothing, because the workbook was written straight to the browser's download instead of through ProTrack's own save. Every other export in ProTrack already used that save, so it worked everywhere.

The same was true of the other workbooks added since v3.35, now fixed with it:
- the Classification Review exports (exception list, all lines);
- the budget version export, and the budget import template;
- the Cost Summary export and the SAP loading workbook;
- the Budget Supplement / Returns Request and Change Request forms.

All of them now save through ProTrack's own save, so they download in a browser tab, from a saved demo file, and inside a host with its own downloads (which may ask you to confirm). Nothing changed in their content.

## 2. Importing the master back proposes only what you changed

**What was wrong:** download the master, change a few rows in Excel, import it back, and every row in the file became a proposal waiting for approval: about 57 for the starting master.

**Now** each row is compared with the element's latest content (its waiting proposal, otherwise its approved content):
- **New element:** a code not yet in the master. It is proposed.
- **Change of …:** an element whose row differs in any column. It is proposed.
- **No change:** a row that says what the element already says. It is not proposed.

When every row matches, the preview says *Nothing to propose: every valid row matches the master*. Refused rows are refused with their reason, as before. Each proposal still waits for someone else to approve it.

**How rows are matched:**
- A blank order matches an element without one.
- A user field matches ignoring capital letters, as the user field list does. For example, the list's "INSTL.MECh" matches "INSTL.MECH".

## How to build the WBS in Excel

1. **WBS Mapping Master → Excel import and export → Download the WBS master (Excel).**
2. In Excel, change or add rows. Keep the column names of the first row. The columns read back are Order, WBS code, Parent code, Description, SAP WBS segment, User field, Aliases, Keywords, Cost category, Project types, Effective from, Effective to, Active, Postable and Mandatory review. Separate lists with semicolons. The columns after them (level, SAP WBS ID, status, version, id) are for reading only.
3. **Import a WBS master workbook.** Check the preview, add a note for the approver, and press **Propose**.
4. Someone else with **bcm.approve** approves the proposals in WBS Mapping Master.

## Checks

- **New suite:** `tests/bcm_wbs_excel_demo.js`, 10 checks, all passing on the demo page. It covers:
  - the download through ProTrack's save;
  - no direct workbook writes left anywhere;
  - the workbook's columns and rows;
  - the master imported back unchanged: nothing to propose;
  - one row changed and one added: exactly those 2 proposed;
  - a bad parent still refused;
  - imported again: rows matching the waiting proposals say No change.
- **Existing suite:** `tests/bcm_file_delete_demo.js`, 15 of 15. Its version check now accepts 3.40 or later.

No server change.
