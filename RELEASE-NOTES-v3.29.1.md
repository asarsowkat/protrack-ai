# ProTrackAI v3.29.1: change a budget supplement log in Excel and upload it again (October 2026)

A month's budget supplement log can now be changed in Excel and uploaded again: **Export to Excel**, change, add or delete rows, and upload the file for the same version. It replaces that version's log, and every screen and report shows the changes. Nothing changes on the server: v35 already takes a new upload for a month that has a log.

## What already worked

Uploading a changed file for a month that already has a log saves it as that month's log; the earlier upload stays in Import history. Only the same file twice is skipped (*nothing changed*).

## What did not, and is fixed

A file made with **Export to Excel** did not upload back cleanly:

- the **PE number** column was taken as the supplement number, and **User field description** as the description;
- the **Total** row at the bottom was refused as a row without a number;
- an export of **all projects in scope** could be uploaded into one project, putting every project's rows in its log.

Now:

- The export's columns are read as they are named: the supplement number, the description, the user field, the version and the amount (Net value) come back as they were exported.
- The Total row is left out.
- A row whose **Project** or **PE number** names another project than the one chosen for the upload is refused with the reason (*this row is for project …*).
- Before saving, ProTrackAI lists the rows of that version's log that are **not in the file** and asks to confirm: uploading replaces the log, so they leave it.
- The upload panel says how to do it.

## How to change a log in Excel

1. **Cost Control → Budget supplements**: choose the project and the version, clear the other filters, and press **Export to Excel**. (With a filter on, the file holds only the rows shown, and the others would leave the log.)
2. Change amounts or texts, add rows (a new supplement number) or delete rows. Keep the Version column the month of the log.
3. Under **Upload a month's log**, choose the same project and version, and the file. Check any refused rows, confirm the rows that leave the log, and save.

Changes made on the screen are still the way to change one row; the history of those changes is kept.

## Checks

- `tests/supplements_demo.js` now has 42 checks. New: an exported log reads back row for row (number, description, user field, amount, Total row left out); the changed file uploaded again for the same version replaces the log (a changed amount, a deleted row, a new row); the rows leaving the log are listed before saving; the same file twice changes nothing; in an export of many projects, the rows of another project are refused.
- The suites sharing the log upload pass: contract value 25, reporting status 28, cash-out 27, delay correspondence 16, executive report status 11, RASA modules 37.
