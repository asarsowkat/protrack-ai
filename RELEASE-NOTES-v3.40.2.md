# ProTrackAI v3.40.2: an untouched WBS master never undoes a waiting change (October 2026)

**What was wrong in v3.40.1:**
- Importing a WBS master workbook compared each row with the element's **waiting change**, when it had one, and otherwise with its approved content.
- But **Download the WBS master (Excel)** writes the **approved** content.
- So downloading the master while a change waited, and importing the file back untouched, showed that element as **Change of …**.
- Proposing it would have replaced the waiting change with the approved content: the change would have been quietly undone.

**Now** a row says **No change** when it matches either the element's approved content or its waiting change:
- An untouched download, imported while a change waits, proposes nothing, and the waiting change stays for its approver.
- A row you really changed is still proposed as **Change of …**.
- A file saved from an earlier import, matching the waiting change, still says **No change**, as before.

## Checks

- `tests/bcm_wbs_excel_demo.js`: 11 checks, all passing. The new check 11: SM3 has a waiting change; importing the first download untouched says No change for SM3, proposes nothing, and the waiting change is kept.
- `tests/bcm_file_delete_demo.js`: 15 of 15.

No server change.
