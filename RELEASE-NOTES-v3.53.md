# ProTrackAI v3.53: site photos from the daily report to the weekly and monthly reports

Site photos now travel with the reports. The foreman adds them to the daily report, those who review and approve it see them, and the planning engineer picks from them when preparing the weekly and monthly reports. Every report has a photo preview.

## Daily report

**While preparing** (New report, or Edit report): **Evidence and remarks** has a **Site photos** section.
- **Add photos** picks JPG, PNG or WEBP photos from the computer or the phone's gallery.
- **Take a photo** opens the phone's camera. It shows only on touch screens.
- Each photo shows as a thumbnail with a caption field and **Remove**. Click a thumbnail, or **Preview all**, to see it full size before saving.
- Photos are resized to 1920 pixels. They are stored only when the report is saved (draft or submit), so leaving the form changes nothing.
- A report holds up to 20 photos. Each photo takes the report's date.
- Drawings and other documents are still listed by file name, under **Drawings or other documents**.

**During review and approval:** the report shows **Site photos** with their captions, above the audit trail and the review buttons. **Preview all** opens them full size. The report list shows how many photos each report has, and the approval email mentions them.

**Who can change the photos:** whoever may edit the report, by the same rule as before.
- While it is a draft: the one preparing it (a foreman only their own), the site engineers, the project manager and the super admin.
- Once submitted or reviewed: the assigned site engineer, those who approve daily reports and the super admin.
- Once approved or rejected: nobody.

## Weekly report

Internal report → a week → **Photos & videos**. Below the report's own photos is **Pick from the daily reports of this week**:
- It lists every photo of the week's daily reports that are submitted, reviewed or approved, with the report number, the date and the report's status. Drafts and rejected reports are left out.
- Tick photos, or **Select all**, then **Add selected to this report**. Each is copied into the weekly report as its own copy, with its caption and date, which the planning engineer can then change.
- Photos already in the report are marked **In this report** and cannot be added twice.
- **Add photos or videos** (from the computer or phone) and, on a phone, **Take a photo** still add the planning engineer's own photos.

## Monthly report

Internal report → a month → **Photos & videos** has **Pick from the weekly and daily reports of this month**, in two groups:
- **Weekly reports:** the photos of every weekly report of the weeks in the month.
- **Daily reports:** the photos of the month's daily reports. A daily photo already added to a weekly report is shown once, with that weekly report, and a note says how many.

Picking, adding and uploading work as in the weekly report. Nothing is added twice: a photo whose original is already in the month is marked **In this report**.

## Preview in every report

The photo viewer now steps through a whole set: a daily report's photos, a report's photos, or a gallery to pick from.
- **‹ ›** buttons, the **← →** keys, or a swipe on a phone move through the set, with "3 of 12" shown.
- **Escape**, ✕ or a click outside closes it, and the report stays open.
- Each photo shows its caption, date and source (the daily report and its status, or the weekly report).
- **Preview all** on the Photos & videos tab of the internal and client reports.
- On the **Approval** tab, a **Photos and videos** row gives the count and a **Preview** button, so the approver sees them before deciding.

A report that is with the reviewer or approver now says so ("Locked while the report is with the reviewer or approver") instead of calling it approved.

## Demo data

Recent daily reports of each project come with SAMPLE site photos, drawn in the browser and captioned with their activity. They are added once, and again after **Reset demo data**.

## Server

`supabase/schema-update-v54.sql` (STAGE-48-SETUP). The photos stay in report_media (v47), with kind `dpr`, in the private bucket `report-media` at `<project>/dpr/dpr-<report id>/`:
- **pt_dpr_edit** applies the daily report's edit rule above.
- **report_media_act** takes photos only for a daily report, at most 20.
- **media_features()** reports version 54.

The weekly and monthly copies use the existing rules of the internal report. Undo: `schema-rollback-v54.sql`.

## Checks

- `tests/report_photos_demo.js`: 21 checks in the demo, covering preparing with photos, the limit, editing, review, the viewer, the weekly and monthly galleries, approval and locking.
- `supabase/tests/test_v54.cjs`: 37 checks in PGlite, covering who adds photos at each status, photos only, the limit, reading, the copies, and rollback and reinstall.
