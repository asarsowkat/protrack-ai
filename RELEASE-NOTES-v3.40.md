# ProTrackAI v3.40: delete an uploaded tender costing file (October 2026)

**Budget & Cost Management → Tender File Intake** can now delete a tender costing workbook uploaded by mistake: the wrong file, the wrong revision, or the wrong batch. Until now a file could only go with its whole batch (Withdraw this batch), and the same workbook could not be uploaded again.

## How it works

On each file of an open batch, **Delete**:
1. ProTrack asks **why** the file is deleted (3 characters or more).
2. It then asks to confirm. The confirmation says:
   - how many rows read from the file are removed;
   - how many of its lines people have already decided, when there are any (those decisions go too).
3. The file is deleted. ProTrack says how many rows were removed.

**What goes:**
- the file's record and its stored workbook;
- every row read from it (all its readings);
- their classification, their splits and the file's sheet roles.

The duplicate groups that used its lines become obsolete, so they no longer count in Duplicate & Backup Analysis. The batch, its other files and their lines are untouched.

**What stays:**
- the **classification history** of its lines;
- the **Audit Log** entry "File deleted": who, when, the file's name, SHA-256 fingerprint and size, the batch, its readings, how many rows and decided lines, and the reason.

**The same workbook can then be uploaded again.** It is read as a new file.

## Who and when

**Who can delete a file:**
- the person who uploaded it, if they still hold **bcm.upload** on the project;
- a reviewer (**bcm.review**);
- a super admin.

Others don't see the button.

**When it is refused:**
- **The batch is withdrawn:** its files are kept with it, as before.
- **The file is being read:** wait until it finishes.
- **A budget version was prepared from the batch** and is not rejected or cancelled: reject or cancel it first. The version's figures came from the file, so the file stays while the version stands.

## Server

`schema-update-v44.sql` (with `schema-rollback-v44.sql` and STAGE-38-SETUP.md):
- `bcm_file_delete` deletes a file with the same rules, in one transaction.
- The private bucket `bcm-tender` lets a stored workbook be removed only when no file record points to it any more.
- `bcm_features` says version 44. The live site shows **Delete** only after this update.

It needs v42. It has not yet been run on a database.

## Checks

**New suite:** `tests/bcm_file_delete_demo.js`, 15 checks, all passing on the demo page. It covers:
- the button and the note;
- the reason;
- the refusals: an open budget version, a file being read, someone who did not upload it, a foreman, a withdrawn batch;
- the confirmation for decided lines;
- deleting through the screen: the file, lines, classification and stored workbook gone; the splits, sheet roles and duplicate groups;
- the audit log entry and the history kept;
- the other file untouched;
- the same workbook uploaded again.
