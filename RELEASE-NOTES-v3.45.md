# ProTrackAI v3.45: client report formats, and the client report as PowerPoint, Word and PDF (October 2026)

Each client wants its weekly or monthly report in its own format. Saudi Electricity Company's weekly progress report, for example, has:
- a cover with both logos;
- a contents page;
- project main highlights, progress summary, S-curve and life cycle;
- major and planned activities, material delivery, outage plan, change orders;
- HSE, manpower, correspondence, QC report, T&C status;
- issues and site pictures;
- a classification footer on every page.

ProTrack now keeps that format per customer and prepares the client report in it.

## Settings → Client report formats (super admin)

**A format holds:**
- its **name** and **customer** (or "any customer": the default format);
- the **weekly and/or monthly** reports it is for;
- its **style**: main and second colour, font, report title, three cover lines and the footer printed on every page. The cover lines take {project}, {client}, {contract_no}, {report}, {period}, {week}, {project_week} (the week number counted from the project start), {date} and {company}.
- its **pages in order**. Each page has a title, a source, and guidance for the planning engineer.

**Page sources:**
- **From ProTrack:**
  - cover, contents;
  - project information and milestone dates;
  - progress summary by phase (weight, previous period, current period, cumulative);
  - S-curve, progress by phase chart, actual against baselines;
  - milestones, intermediate milestones, engineering and procurement;
  - look-ahead, manpower;
  - issues and concerns (from the issue register);
  - contract value and change orders;
  - site pictures (from Photos & videos);
  - any of the report notes;
  - the closing page.
- **Entered by the planning engineer:**
  - **text**: one point a line, # for a sub-heading;
  - a **table** with the format's columns, optionally with rows always listed (for example Fatalities, Lost time injuries … Safety index);
  - **pictures** chosen from the report's Photos & videos (layout drawings, location maps).

**Draft a format from a client's PowerPoint.**
- Upload the client's own report. Its slide titles become the pages, and its table headings become the columns.
- The importer also finds:
  - the main colour (from the slide layouts) and the font;
  - the classification footer.
- Pages ProTrack can fill are recognised by title: contents, highlights, progress summary, S-curve, life cycle, activities this period and next, manpower, issues and challenges, site pictures, thank you.
- Every other table page becomes a table to enter; a pictures page becomes pictures to choose.
- Repeated titles are kept once; pages for different sites stay separate pages.
- Check each page's source and the customer, then save.

**Choosing the format:**
- A report uses its project's chosen format, else its customer's format, else the built-in **ProTrack standard client report**.
- The planning engineer can choose another format for the project in the client report.

**Demo:** the demo has a **SAMPLE** format with the outline of the SEC weekly progress report: page titles and table headings only, no figures from the sample. It is set for the demo customer "Saudi Electricity Company" (project QOT).

## Client report → Client format and export (new tab)

The tab lists every page of the format with its source and state:

| State | Meaning |
|---|---|
| **From ProTrack** | Filled from ProTrack's data for this period |
| **Entered** | The planning engineer entered it |
| **Not applicable** | Marked not applicable this period |
| **Not updated: no data in ProTrack** | ProTrack holds nothing for this page this period |
| **Not updated: nothing entered** | A page to enter that is still empty |
| **Not updated: carried from (period)** | Taken from the last released report and not yet changed |

- The planning engineer enters the pages ProTrack does not hold: safety statistics, quality, correspondence, outage plan and the like.
- Any page can be marked **Not applicable**, and each page can be ticked **Reviewed**.
- Everything is saved with the report (**Save draft**), and approved and frozen with it.
- **A new period starts from the last released report's entered pages**, marked carried until they are changed, so nothing is re-typed and nothing old goes out unnoticed.

## Review, validate, export

**Export: PowerPoint, Word, PDF** first shows **Review before the client gets it**:
- the **disclaimer**: ProTrack prepared the report from the data recorded up to the data date and the entered pages; it does not check the report for the client; the planning engineer must review and validate the complete report before it is submitted;
- every page with its state and whether it was reviewed;
- the **pages not updated**, by name.

**Copy type:**
- A **review copy** marks each page not updated with a red NOT UPDATED band.
- A **client copy** needs the planning engineer to tick "I have reviewed and validated the complete report, including the pages not updated listed above".
- A report not yet approved is marked **DRAFT** in every copy.

**Files:**
- **PowerPoint (.pptx):** 16:9 slides in the format's colours and font, with the cover, logos, footer and slide numbers. Tables run over several slides when long, and pictures go four to a slide with their captions.
- **Word (.docx):** landscape A4, a heading a page, with the logos and footer in the page header and footer, and page numbers.
- **PDF:** landscape A4, laid out like the slides.

**Every export is logged** (who, when, which file, review or client copy, and the pages not updated) and listed in the tab.

## Not covered yet

A programme report covering several ProTrack projects in one file (the HVDC weekly report covers four converter-station sites) is not combined: each project's client report is its own file. A format drafted from such a deck keeps one page per site, to be pointed at the right project.

## Server

`schema-update-v48.sql` (with `schema-rollback-v48.sql` and STAGE-42-SETUP.md):
- `client_report_formats` with `crf_save` (super admin);
- `client_report_format_picks` with `crf_pick` (those who prepare client reports);
- `client_report_exports` (append only) with `crx_log`.

The entered pages travel with the client report's narrative, which the server already keeps whole. It needs v47 and has not yet been run on a database.

Word files use the **docx 8.5.0** library from jsdelivr, which is not on cdnjs. PowerPoint uses the pptxgenjs library the Presentation builder already uses. Porting to DevPlanning needs the team's approval for docx.

## Checks

**New suite:** `tests/client_formats_demo.js`, 17 checks, all passing on the demo page. It covers:
- the formats and who keeps them;
- which format a report uses;
- the format checks;
- a format for another customer;
- a format drafted from a PowerPoint (pages, columns, footer);
- the tab and the page states;
- entering, saving, not applicable and reviewed;
- carried pages, and someone who does not prepare reports refused;
- the disclaimer and the pages not updated;
- the client copy needing the confirmation;
- the PowerPoint (order, NOT UPDATED, DRAFT), the Word (headings, table, footer) and the PDF;
- the export log.

**Still passing:** `tests/logos_media_demo.js` (18) and `tests/deck_reports_demo.js` (16).
