# ProTrackAI v2.6: Phase 3, controlled imports (October 2026)

## What changed

Every upload now goes through the same five steps. The uploads are the invoice register, the costing file, the P6 baseline and the weekly engineering and procurement progress.

1. **File check:** only Excel (.xlsx, .xls), CSV, Primavera XER or P6 XML files are accepted, up to 10 MB. Workbooks with macros (.xlsm, .xlsb) are refused before they are read. Nothing in a workbook is ever executed. The browser reads values only, and the server receives values, never the file.
2. **Row checks** are made in the app and again on the server:
   - The row belongs to this project (when the file has a Project column).
   - The currency is SAR (when the file has a Currency column).
   - Dates are real dates (for example, 30 February is refused).
   - Numbers are numbers (text in an amount column is refused, no longer read as zero).
   - No duplicate invoice numbers or activity IDs.
   - Activities exist in the baseline.
   - Weekly progress cannot run backwards without a remark, and its dates are consistent.

   Every refused row carries its reason and its row number in the sheet.
3. **Preview with reconciliation:** shows the rows in the file, accepted, refused and warnings. For money, it shows the total in the file, the total accepted and the difference. It also shows the file's SHA-256 fingerprint. **Download exception report** gives every refused row and warning as a CSV that opens in Excel.
4. **Acknowledgement:** when any row is refused, **Apply** stays disabled until the user confirms they have reviewed the refused rows and want to load only the accepted ones. Their name and an optional note are recorded. The server enforces this independently: without the confirmation it refuses the whole load with "Reconciliation difference … Nothing was saved."
5. **One transaction:**
   - If anything fails part-way, nothing is saved and the previous data is unchanged.
   - A file with no valid row never empties the last good register or baseline.
   - The same content loaded again changes nothing.
   - Weekly progress, previously saved activity by activity, is now one server transaction covering every project in the file.

**Import centre** (Imports & Integrations → Import centre) lists every batch as IMP-000123. Each entry shows:

- type, project, file, source period, currency
- file fingerprint and content fingerprint, file size
- rows in the file, accepted, refused and warnings
- total in the file, total accepted and the difference
- reconciliation result, and who accepted a difference, with their note
- commit status, error, retry link and audit reference

You can filter by type and result. The exception report downloads from any batch. A failed attempt is logged, and a later successful load of the same file shows as its retry. Site roles do not see the Import centre.

**Concurrent uploads:** two people loading the same kind of file for the same project at once are handled one after the other, never mixed. The same file sent twice at once is saved once.

**SAP:** SAP ECC Excel exports are listed as planned, pending a sample export and Finance rules. Direct SAP and S/4HANA connections stay switched off.

## Behaviour changes to know about

- When rows are refused, you now tick a box before **Apply** is enabled. Previously the valid rows were applied straight away.
- Text in a number column is now refused. Previously it was read as 0.
- Uploading the identical file twice is now a no-op with a message. Previously it was re-applied with the same result.
- The P6 baseline import refuses the whole file when activity IDs repeat, a date is invalid, or a finish is before its start, and lists them. Previously the server gave a database error.

No formula changed. Reconciliation compares the totals in the file against the totals accepted. It does not alter how cost, earned value or billing are calculated.

## Database: `schema-update-v5.sql`

- **Additive only:**
  - new columns on `import_batches`: number, file fingerprint, size, currency, warnings, reconciliation status and difference, who accepted it and their note, retry link, error
  - new functions: `import_commit`, `log_import_failure`, `import_progress`, and checks for numbers, dates and milestones
- **Replaced functions:** the three v4 import functions, with the same names and inputs, now validate rows instead of failing on bad values. The v2.5 app keeps working with v5 installed.
- **No data is deleted or rewritten.** Existing batches are kept and numbered.
- **Safe to run twice.**
- **Reversible:** `schema-rollback-v5.sql` puts back the v4 functions and keeps all data.

## Verified

Results files are in `tests/`.

| Suite | Checks | Result |
|---|---|---|
| Database, imports (`test_v5.py`) | 64 | 64 pass |
| Database, Phase 2 rules (`test_v4.py`) | 125 | 125 pass |
| Server mode, end to end, through the app | 68 | 68 pass |
| Imports in demo mode (`imports_demo.py`) | 34 | 34 pass |
| Regression, demo date | 77 | 77 pass, 2 skipped |
| Regression, live date | 77 | 77 pass, 2 skipped |
| Functional suites | 59 | 59 pass |
| Formula reference | 23 | 23 pass |
| Backup and restore | 10 | 10 pass |

**`test_v5.py`** runs on PostgreSQL with the real schema, signed in as each role. It covers the master prompt's import tests:

- a valid file
- empty files, wrong file types, oversized files and too many rows
- wrong project, bad dates, wrong currency, text in numbers and negative amounts
- duplicate batches and duplicate transaction IDs
- partial errors and reconciliation differences
- a commit interrupted half-way by a simulated disk failure
- retry after that failure
- two simultaneous uploads
- unauthorized users and signed-out visitors
- rollback and re-apply

**The end-to-end suite** repeats the failure → retry sequence through the real app.

**Suite changes in this release:**
- The functional suites gained 1 check (the acknowledgement step).
- Two steps in the suites were updated for the new behaviour:
  - They now tick the acknowledgement box before applying.
  - A repeated invoice upload now uses changed content, because identical content is now a no-op.

**Not verified here:**
- Supabase itself: its sign-in and web layer were replaced by a local stand-in.
- Your live project.
- Real P6 XML (PMXML) files: no sample was available.
- Real SheetJS reading of binary Excel files: the tests use a stand-in that hands the app the rows. Check one real register and one real costing file on staging or after release.
