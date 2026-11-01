# ProTrackAI v3.50: client invoices in the client's own format

Each client wants its invoice in its own workbook. A typical one has:
- a bilingual tax invoice;
- a cover page;
- the invoice summary;
- a breakdown sheet per price component (general, engineering, material, construction, installation, testing and commissioning), each with previously / new period / cumulative progress and payment;
- a forecast of invoices;
- hidden sheets of its own.

Until now the Client Invoice Builder exported the ProTrackAI layout only. v3.50 keeps the client's workbook as a **format** and fills it from each invoice.

## Keeping a format

**Client Invoice Builder → Invoice formats** (right `cib.setup`):

1. **Upload** a certified invoice workbook of the client (.xlsx, up to 25 MB). Workbooks with macros are refused. Its figures are never used: every figure comes from the invoice being exported.
2. **ProTrack reads its layout:**
   - **Breakdown tables:** the column with the item numbers, and the role of every column from its headings. For example, CERTIFIED PROGRESS › PREVIOUSLY › % is the progress previously, and PAYMENT CERTIFIED › NEW PERIOD › AMOUNT is the payment this period.
     - A column that is a formula stays a formula.
     - A table can run across printed pages with a signature block between them.
   - **Each table's component:** taken from the project's Schedule-C, or else from the sheet's name.
   - **Header cells:** invoice number, date, due date, period from and to, contract number, project name, contract value, type of invoice, contractor, client, retention, advance recovery and VAT %.
     - The cell is the one beside or below the label.
     - Where that cell is a formula, the format works the figure out itself, so ProTrack does not write it.
     - Net payable, VAT and total with VAT, when they are formulas, are kept to check.
   - **The TCC and FAC lines** of the summary, the **invoice number inside a title** (PAYMENT CERTIFICATE # 01) and the **forecast** list.
3. **Check the map:**
   - each sheet (fill, keep as it is, or take out);
   - each table's component and rows (rebuilt from the Schedule-C, matching rows only, or left as it is);
   - the field of each header cell.

   Save it under a name, for one client or for any client.

## Exporting an invoice in a format

On an invoice, choose the format beside **Excel invoice**. The project's client's formats come first, and the ProTrackAI layout is always offered.

- **Only the mapped cells change.** Everything else in the client's workbook stays as the client made it:
  - logos, stamps and drawings;
  - comments and links to other workbooks;
  - styles and print settings;
  - hidden sheets and every formula.
- **Rows follow the project's price schedule.** Each breakdown sheet gets the Schedule-C items of its component, in order. Rows are inserted at the last item row, or taken out from the end, exactly as Excel does:
  - every reference moves with them: the summary's links to each TOTAL row, SUM ranges, merged cells, print areas, drawings and comments;
  - a reference into a removed row becomes #REF! and is counted.
- **ProTrack writes:**
  - progress previously and this period;
  - payment % or amounts where the format types them;
  - the TCC and FAC amounts where the format has those lines.
- **Formulas are worked out.** ProTrack works out the format's own formulas and writes their figures, so the file shows them before Excel recalculates it (Excel recalculates on opening).
- **Checks.** ProTrack compares the format's own figures with ProTrack's invoice:
  - each table's payment this period;
  - TCC and FAC;
  - net payable, VAT and total with VAT.

  Any difference is named. For example, a format that pays 80% on progress where the approved rules say 90% shows the difference on MATERIAL and on the net. Items missing from the format, and the format's rows that are not in this Schedule-C (set to zero), are named too.
- **Audit trail.** The export is noted with the format's name and what was found.

## Checked against a real client workbook (structure only, no figures copied)

- **Workbook:** 21 sheets, 63 links to other workbooks, 11 logos and stamps.
- **Formulas:** ProTrack's evaluator gives Excel's own figure for all 3,463 formulas.
- **Reader:** it finds the six visible breakdown sheets (MATERIAL with 55 item rows across its page blocks), the header cells of the tax invoice, cover page and summary, the TCC and FAC lines and the forecast.
- **Rebuilt rows:** filled with another price schedule (MATERIAL 55 → 15 rows, CONSTRUCTION 30 → 3), the file opens in Excel with exactly the same 80 error cells as the client's own file (from its external links) and no new one. The summary links reach the moved TOTAL rows, and the format's material total equals ProTrack's.

## Demo

**Utility client layout (SAMPLE)** is kept for any client. It has the same structure (tax invoice, cover page, summary, seven breakdown sheets, forecast) with SAMPLE names only.

Export QOT's invoice in it: the format's totals for this period, to date, net payable, VAT and total agree with ProTrack's.

## Fix: reading stored files on the server

The report-media read rule (v47) called `user_sees()`, which signed-in people may not run. PostgreSQL checks that right for every read rule of the storage, so once v47 was installed no stored file could be read from any bucket:
- report photos;
- project documents;
- delay documents;
- BoQ drawings;
- tender files.

v53 replaces the rule with `pt_rm_see()`, which signed-in people may run, and a server check proves files can be read again.

## Server: schema-update-v53.sql

- `cib_formats` and the private bucket `cib-formats` (fmt/<id>.xlsx).
- `cib_fmt_act`: fmt_add, fmt_map, fmt_del.
- `cib_act`: inv_export.
- `cib_features()` reports version 53.
- The storage read fix.

See STAGE-47-SETUP.md. Rollback: `schema-rollback-v53.sql`. It keeps the table, the bucket and the read fix.

## Tests

- `tests/client_invoice_formats_demo.js`: **21 checks**.
- `supabase/tests/test_v53.cjs`: **43 checks** on PGlite.
- Still passing:
  - `client_invoice_builder_demo.js` 27/27;
  - `cib_wbs_weight_demo.js` 14/14;
  - `cash_inflow_demo.js` 28/28;
  - `cashflow_dashboard_demo.js` 28/28;
  - `rasa_hub_demo.js` 25/25.

## Not done

- **Supabase:** v53 has not been run on Supabase. Try it on a staging copy first.
- **Not filled from the client's workbook:** the attachment checklist, the SAP upload sheet and the price-schedule detail sheets. They are kept as they are, or can be taken out.
- **Charts and pivot tables:** they are kept, but their cached data is not refreshed until Excel recalculates.
- **Older formats:** .xls and .xlsm workbooks must first be saved as .xlsx.
