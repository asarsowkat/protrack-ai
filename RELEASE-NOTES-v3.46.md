# ProTrackAI v3.46: client report formats for Word reports, the SEC monthly progress report (October 2026)

Saudi Electricity Company's **monthly** progress report is a Word document, not a slide deck:
- a cover ("Monthly Progress Report No. 28") and a document revision record;
- an index of numbered headings (1 Project Details, 2 Project description, 2.1 Scope of works … 14 Appendix);
- a header line and a "CLASSIFICATION: Public" footer with the page number;
- portrait and landscape sections mixed;
- olive table headings.

v3.46 lets a client report format describe all of that, and drafts it from the client's Word file.

## In the format (Settings → Client report formats)

- **Levels.** A page is a heading (level 1) or a sub-heading (level 2) of the page above it, numbered 1, 2, 2.1, 2.2 … in every file and on the screen. The cover, the revision record, the index and the closing page carry no number.
- **Portrait or landscape.** The format has its page orientation for Word and PDF, and any page can override it (a wide risk register in landscape inside a portrait report).
- **Header line**, for Word and PDF, with the same fields as the cover: for example "{report} : {date}   {project}".
- **Table heading colour and its text colour**, for example olive shading with dark text.
- **{report_no}**: the report's number, counted from the project start (months for a monthly report, weeks for a weekly one), for "Monthly Progress Report No. {report_no}".
- **Two new pages ProTrack fills:**
  - **Document revision record:** each revision of the report with its description, who prepared, checked and approved it, and the date.
  - **Invoices:** the invoice register up to the period's end, with amount, submission and approval dates, and status. Used for the Financial section.

## Draft a format from a client's Word report

**Draft a format from a client's PowerPoint or Word report** now also reads Word (.docx):
- **Pages:** its level 1 and 2 headings become the pages at their level, with the heading numbers taken off.
- **Tables:** the table under a heading gives the page its columns. A title row such as "Quality Dashboard till Oct 2026" is skipped and kept as the page's guidance.
- **Pictures:** a heading with pictures only becomes a pictures page.
- **Repeated site sections:** sections repeated per site (Quality – Kudmi, Quality – 9041) are kept once, without the site.
- **ProTrack sources found by title:** revision record, index, project details, key project milestones, overall progress, S-curve, EPC curve, main achievements, design and engineering, financial, change management, issues, manpower, progress photographs.
- **Style:**
  - each page's orientation, from the document's sections;
  - the cover's report title and number;
  - the header line;
  - the classification footer;
  - the main colour (from the text);
  - the table heading colour (from the cell shading);
  - the font.

On the attached SEC monthly report it gives:
- 45 pages, with sub-headings at level 2;
- the landscape pages;
- the columns of every table (scope of works, health, quality, permits, risk register, escalated issues);
- olive 3B4121 with E6E9D5 table headings;
- "CLASSIFICATION: Public".

## The files

- **Word:**
  - a real **table of contents** (Index) that Word fills with page numbers when the file is opened (it asks to update the fields);
  - headings at two levels, so the contents shows both;
  - portrait and landscape sections as the format says;
  - level 2 pages following on the same page;
  - the header line with the logo, and the footer with "Page | n";
  - the table heading colours.
- **PDF:** each page in its orientation, with numbered titles, the header line and the contents by level.
- **PowerPoint:** numbered slide titles, and the contents by level.

## Demo

A **SAMPLE** format with the outline of the SEC monthly progress report (headings and table columns only, no figures from the attached report) is used for the demo customer's monthly client reports (project QOT). The weekly SAMPLE format stays for weekly reports.

## Server

`schema-update-v49.sql` (with `schema-rollback-v49.sql` and STAGE-43-SETUP.md): `crf_save` accepts the new page sources, levels, orientations and style fields. Nothing else changes. It needs v48 and has not yet been run on a database.

## Checks

**New suite:** `tests/client_formats_word_demo.js`, 12 checks, all passing on the demo page. It covers:
- the monthly format chosen for monthly reports;
- the new checks;
- a format drafted from a Word report (levels, columns, sites, orientation, footer, colours, report number);
- numbers by level;
- the revision record and invoices pages;
- the Word file (headings, contents, sections, header, colours), the PDF orientations, the PowerPoint titles;
- the editor.

`tests/client_formats_demo.js` (17) still passes.
