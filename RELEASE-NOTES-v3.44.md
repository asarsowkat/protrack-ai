# ProTrackAI v3.44: the MER's Project wise in the company format, Excel and PDF; logos; report photos and videos (October 2026)

## 1. MER → Project wise, as the company's PE sheet (PLAN-006-FORM-01)

Project wise is now laid out as the PE sheet of the MER workbook.

**Left side, numbered rows:**
1. **Project information**
2. **Progress percentage:** weight, planned, actual, var.
3. **Schedule status:** overall project, civil works, TCC, PAC, FAC; contract, revised and forecast finish, var.
4. **Claim status**
5. **Commercial status:** 16 rows, in SAR.
6. **Budget status:** gross profit %, overall project, then every WBS head from Site Management to Potential Risks; actual cost, Budget Rev.00, current budget, var. %.
7. **Manpower**, with the supervision ratio.

**Right side:**
- the company logo and the client's logo;
- the four charts of the sheet: **cost plan for the current year** (planned, actual and forecast POC by month, with the cumulatives), **POC for the current year** (target, actual, forecast), **cash status**, and **site management earned value**.

**Below:**
- **Areas of concern:** five areas, three rows each, with action by and action needed;
- the footer: project manager, planning engineer, PLAN-006-FORM-01;
- the chart data, folded away.

**Formulas, as the sheet:**
- schedule var. = revised (else contract) finish − forecast finish, in days; negative is late;
- budget var. % = (Rev.00 − current) ÷ Rev.00;
- manpower var. = (actual − planned) ÷ planned.

## 2. MER export to Excel and PDF

**Export to Excel** and **Export to PDF** take the whole MER: Cost, Dashboard and Project wise. On Project wise, **This project to Excel** and **This project to PDF** take one project.

**Excel:**
- **COST (I) / COST (F)** and **DASHBOARD**, styled: KPI group headers, the portfolio and region rows shaded, number and percent formats, frozen headings.
- **One sheet per project** in the PE sheet's cell layout. Columns A–P, the same rows and the same merged cells: the project name in E2, the revised contract value in G36, the overall budget in G53, manpower in row 74, areas of concern from row 81, PLAN-006-FORM-01 in N102.
- The logos and the four charts (as pictures) sit where the sheet has them. The print area is A1:P103, on one A4 page.
- The chart data is below the print area, from row 106, as in the PE sheet.

**PDF:**
- Cost and Dashboard on A3 landscape pages, with the logo.
- Then one A4 portrait page per project, with the logos and the charts.

The Excel styling uses **ExcelJS 4.4.0**, loaded from cdnjs like the other export libraries. Porting this to DevPlanning needs the team's approval for that library.

## 3. Logos: Settings → Logos and customers (super admin)

- **Company logo:**
  - Upload the official logo; PNG with a transparent background or SVG works best.
  - It is made web-sized (at most 800 × 400 pixels, 400 KB).
  - The company name is written where there is no logo.
- **Customers:**
  - Create each customer with its name and logo.
  - The **Client** field of a tender suggests the customers, and a project's client takes its customer's logo.
  - Renaming a customer renames the client of its tenders and projects.
  - A customer that is a client cannot be deleted; make it inactive instead.
  - The list offers to create a customer for each project client that has none.
- **Where the logos appear:** the MER's Project wise page, the MER Excel and PDF, and the client report's Print or save as PDF.
- **Nothing is invented:** the demo has no logos until you upload them.

## 4. Progress photos and videos in the internal and client reports

The internal report (monthly and weekly) and the client report have a new **Photos & videos** tab.

- **Adding:**
  - Those who prepare the report add **photos** (JPG, PNG, WEBP) and **videos** (MP4, WEBM, MOV, up to 100 MB).
  - Photos are resized to 1920 pixels. Videos are kept as they are, with a preview frame and their length.
  - At most 40 per report.
- **Each item:** a caption (300 characters) and the date taken (from the file, changeable). Click to view full size or play.
- **Locking:** they can change while the report is not approved: before its first release, or while a revision is a draft. Once the report is approved, they are locked.
- **Client report:**
  - **Copy from the internal report** takes the internal report's photos and videos of the same period, once each. Each report keeps its own.
  - **Print or save as PDF** now prints the logos at the top, the photos with their captions, and a list of the videos.

## Server

`schema-update-v47.sql` (with `schema-rollback-v47.sql` and STAGE-41-SETUP.md):
- `pt_branding` and `customers`, read by everyone signed in; `branding_set` and `customer_act` for the super admin;
- `report_media` and the private bucket **report-media** (100 MB a file);
- `report_media_act` and the storage rules: read by those who see the project; added and changed by those who prepare the report while it is not approved; a file removed only once its record is gone.

It has not yet been run on a database.

## Checks

**New suite:** `tests/logos_media_demo.js`, 18 checks, all passing on the demo page. It covers:
- logos and customers, and who sets them;
- the logo size and the SVG check;
- duplicates, renaming, delete refused, the client suggestions;
- the PLAN-006 sections and rows;
- the Excel cells, merges and pictures;
- the PDF page count and size;
- photos resized, captions, a video, other files refused;
- locked after approval, and someone who doesn't prepare reports refused;
- copying to the client report, its print, the tab in each report, deleting.

**Updated:**
- `tests/mer_demo.js` (25 checks): check 22 expects the PLAN-006 section titles, and check 23 loads SheetJS to read the workbook.
- `tests/cost_plan_import_demo.js` (21 checks) still passes.

**Already failing:** `tests/key_ms_demo.js` and `tests/ep_report_demo.js` stop early on this demo date. Both use the fixed week 2026-W39, and fail the same way on v3.43.
