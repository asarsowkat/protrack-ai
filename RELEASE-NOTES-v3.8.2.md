# ProTrackAI v3.8.2: a material's history opens full screen (October 2026)

Built from your request: "i want full screen if i open history for any material".

## What changed
**Material tracking → History** on any material now opens full screen instead of a side panel. The window shows:

- **At the top:** the material's Delivery Status, its current stage, its status and the schedule data date.
- **PO Number, Supplier Name and Remarks** as they stand now.
- **The nine milestones** side by side: PR Creation, PO Creation, Base Design, GAFM Approval, Manufacturing, FAT, Release for Shipment, Delivery at Site and Civil Readiness. Each shows its status and its actual or forecast date.
- **Activities:** every activity of the material, with baseline start and finish, current start and finish (marked "actual" where achieved), % complete and status.
- **History of the manual fields**, beside the activities: every change to the PO number, supplier, remarks and monitoring, with before, after, who and when.

✕ or Esc closes it. On a phone the window already filled the screen; the milestones show two to a row.

## Database
No database update.

## Verified
| Check | Result |
|---|---|
| `mat_demo.py` (adds: history full screen with the nine milestones; closing restores the panel) | 52 of 52, app and sample-data page |
| `mt_auto_demo.py`, `fullscreen_demo.py`, regression, suites | unchanged results |
