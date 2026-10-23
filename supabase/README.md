# ProTrack Supabase updates (current: v3.9)

| File | Run it? |
|---|---|
| `schema-update-v4.sql` | **Yes, on your live project** (after v2 and v3 are in). Step 1 of STAGE-2B-SETUP.md |
| `schema-update-v5.sql` | **Yes, on your live project, after v4.** Step 1 of STAGE-3-SETUP.md |
| `schema-update-v6.sql` | **Yes, on your live project, after v5.** Step 1 of STAGE-4-SETUP.md |
| `schema-update-v7.sql` | **Yes, on your live project, after v6.** Step 1 of STAGE-4B-SETUP.md |
| `schema-update-v8.sql` | **Yes, on your live project, after v7.** Step 1 of STAGE-5-SETUP.md |
| `schema-update-v9.sql` | **Yes, on your live project, after v8.** Step 1 of STAGE-6-SETUP.md |
| `schema-update-v10.sql` | **Yes, on your live project, after v9.** Step 1 of STAGE-7-SETUP.md |
| `schema-update-v11.sql` | **Yes, on your live project, after v10.** Step 1 of STAGE-8-SETUP.md |
| `schema-update-v12.sql` | **Yes, on your live project, after v11.** Step 1 of STAGE-9-SETUP.md |
| `schema-update-v13.sql` | **Yes, on your live project, after v12.** Step 1 of STAGE-10-SETUP.md. Creates the private `project-docs` storage bucket |
| `schema-update-v14.sql` | **Yes, on your live project, after v13.** Step 1 of STAGE-11-SETUP.md. Regional approval of progress releases and the dashboard figures |
| `schema-update-v15.sql` | **Yes, on your live project, after v14.** Step 1 of STAGE-12-SETUP.md. Internal weightage, updated schedules, client reports, validation of differences |
| `schema-update-v17.sql` | **Yes, on your live project, after v16.** Step 1 of STAGE-14-SETUP.md. Material Tracking |
| `schema-rollback-v17.sql` | Only to undo v17. Back to v3.7; keeps every table, column and history entry |
| `schema-update-v18.sql` | **Yes, on your live project, after v17.** Step 1 of STAGE-15-SETUP.md. Material status saved with each released internal report; executive report layouts kept per person on the server |
| `schema-rollback-v18.sql` | Only to undo v18. Back to v3.8; keeps the saved material status and every layout |
| `schema-update-v20.sql` | **Yes, on your live project, after v18** (v19 is not needed first). Step 1 of STAGE-16-SETUP.md. Change order and claim log: client approved price, price considered internally with its WF number and date, row updates with their history; the contract breakdown saved with each released report |
| `schema-rollback-v20.sql` | Only to undo v20. Back to the v3.10 server rules; keeps the four columns, the update history and every saved breakdown |
| `schema-update-v22.sql` | **Yes, on your live project, after v17** (v18 to v21 are not needed first). Step 1 of STAGE-18-SETUP.md. Baseline comparison saved with internal and client reports; the baseline assigned in the updated schedule; invoice phase and submission, approval and collection dates; the payment period in the payment terms |
| `schema-rollback-v22.sql` | Only to undo v22. Back to the v3.13 server rules; keeps the seven columns, every saved comparison and the payment periods |
| `schema-update-v23.sql` | **Yes, on your live project, after v20 and v22** (v19 and v21 are not needed first). Step 1 of STAGE-19-SETUP.md. Report email lists kept on the server (default internal report and cost report lists, one per region for internal reports); the contract value of each cost report column (cv_by) worked out by the server and frozen at approval |
| `schema-rollback-v23.sql` | Only to undo v23. Back to the v3.16 server rules; keeps the email lists table and every saved cv_by |
| `schema-update-v24.sql` | **Yes, on your live project, after v10 and v16.** Step 1 of STAGE-20-SETUP.md. Delay events register (Claims & Variations): the events in the company register's columns, kept by the planning engineers of each project (new right delay.keep), read on the projects in each person's access, Excel upload, full history |
| `schema-rollback-v24.sql` | Only to undo v24. Removes the save and upload functions, the right and the screen; keeps every event and history entry |
| `schema-update-v25.sql` | **Yes, on your live project, after v24.** Step 1 of STAGE-21-SETUP.md. The delay register's drop-down lists, changed by the super admin only, and checked on every save and upload |
| `schema-rollback-v25.sql` | Only to undo v25. Removes the list check and delay_lists_set; keeps the lists and their history |
| `schema-update-v26.sql` | **Yes, on your live project, after v24** (v25 is not needed first). Step 1 of STAGE-22-SETUP.md. Correspondence and letters on delay events, with their files in the private `delay-docs` bucket |
| `schema-rollback-v26.sql` | Only to undo v26. Nobody can add or remove records; keeps every record and file |
| `schema-update-v27.sql` | **Yes, on your live project, after v7 and v16.** Step 1 of STAGE-23-SETUP.md. Cash-out forecast: Finance cumulative actuals and corrections, PO payment terms, other cash-out lines, versions, reviews, scenarios, all written through cashout_act |
| `schema-rollback-v27.sql` | Only to undo v27. Nobody can change cash-out data; keeps every record |
| `schema-update-v28.sql` | **Yes, on your live project, after v17 and v27.** Step 1 of STAGE-24-SETUP.md. Material PO payment terms (Material tracking PO numbers) and the cost report head treatments for the cash-out forecast |
| `schema-rollback-v28.sql` | Only to undo v28. Back to the v27 actions; keeps the material PO terms and head treatments |
| `schema-update-v29.sql` | **Yes, on your live project, after v14.** Step 1 of STAGE-25-SETUP.md. Reporting status: reporting rules, exemptions and reminders |
| `schema-rollback-v29.sql` | Only to undo v29. Nobody can send reminders, exempt or change the rules; keeps everything |
| `schema-update-v30.sql` | **Yes, on your live project, after v17 and v22.** Step 1 of STAGE-26-SETUP.md. Intermediate milestones from the P6 schedule, progress by phase with the daily-report comparison, energization as a phase |
| `schema-rollback-v30.sql` | Only to undo v30. Nobody can add or remove intermediate milestones; reports save without them; keeps everything |
| `schema-update-v31.sql` | **Yes, on your live project, after v16.** BOQ Engine: the screen in Settings → Role access (no step guide; run it as any update) |
| `schema-rollback-v31.sql` | Only to undo v31. The BOQ Engine screen leaves Role access; the app uses its default |
| `schema-update-v32.sql` | **Yes, on your live project, after v16 and v31.** Step 1 of STAGE-27-SETUP.md. BOQ Engine: rights, tables, the governed save boq_save, the private bucket boq-drawings |
| `schema-rollback-v32.sql` | Only to undo v32. Nobody can change BOQ Engine records on the server; keeps everything |
| `schema-update-v33.sql` | **Yes, on your live project, after v30.** E&P progress saved with each internal and client report (pt_ep_tbl, release_act_km). Run it as any update; check with `select ep_features();` |
| `schema-rollback-v33.sql` | Only to undo v33. Reports save without E&P progress; keeps what was saved |
| `schema-update-v34.sql` | **Yes, on your live project, after v13.** STAGE-28-SETUP.md. The release strategy (golive_cfg, golive_set) and the document text RASA reads (doc_text, doc_text_set, doc_text_search). Check with `select golive_features();` |
| `schema-rollback-v34.sql` | Only to undo v34. Every module counts as live again and RASA stops quoting documents; keeps the tables |
| `schema-update-v35.sql` | **Yes, on your live project, after v20.** STAGE-29-SETUP.md. The budget supplement log by user field and category: new columns, the lists (supp_lists, supp_lists_set), changes on the screen (supp_update, supp_audit), log_import and the budget change. Check with `select supp_features();` |
| `schema-rollback-v35.sql` | Only to undo v35. Nobody can change rows on the screen or the lists; uploads go back to the earlier layout; keeps the columns, lists and history |
| `schema-update-v36.sql` | **Yes, on your live project, after v35.** STAGE-30-SETUP.md. A version on each budget supplement row (budget_supplements.version, filled for the rows already logged); the cost report counts the rows whose version is up to the month. Check with `select supp_features();` |
| `schema-rollback-v36.sql` | Only to undo v36. A row's version is the month of its log again; keeps the column |
| `schema-update-v37.sql` | **Yes, on your live project, after v16.** STAGE-31-SETUP.md. The Cashflow Dashboard screen (`cfd` in pt_screens) and its finance cost rates (cf_rates, cf_settings, cf_rates_set). Check with `select cf_features();` |
| `schema-rollback-v37.sql` | Only to undo v37. The dashboard shows no finance cost and leaves Role access; keeps the rates |
| `schema-update-v38.sql` | **Yes, on your live project, after v16** (report emails need v23, reminders v29). STAGE-32-SETUP.md. Emails really sent: the mail queue (`mail_outbox`, `mail_queue`, `mail_retry`); the server checks each event and works out the recipients. Then deploy the Edge Function `functions/send-mail` with its settings |
| `schema-rollback-v38.sql` | Only to undo v38. Emails are listed as not sent again; keeps the outbox |
| `functions/send-mail/index.ts` | The Edge Function that sends a queued email through Microsoft 365 (Graph) or an SMTP relay on port 465. STAGE-32-SETUP.md steps 2 and 3. `functions/send-mail/test.mjs` tests it (Node 22) |

**v3.26.1:** v24 (and its rollback), v27, v28, v29, v30, v32 and v33 were corrected in place after the module review (see `../REVIEW-v3.26.1.md`). None had been run on a database, so run them as they are now, in order, once.

**v3.28.2:** `schema-update-v18.sql` is fixed: two of its functions were quoted with `$` instead of `$$`, so it stopped with *syntax error at or near "$"*. Every rollback (v4 to v34) is now safe to run even if its update was never applied: it checks for the first table, column or function that update adds, and if it is not there it changes nothing and answers one row, *schema-update-vN.sql is not on this database … nothing was changed*. Otherwise it runs the same rollback as before and answers *schema-update-vN.sql undone.* A rollback is still only for undoing an update that caused a problem: to move forward, run only the `schema-update-*.sql` files. After v34, `check-v18-v34.sql` (reads only) shows one row per update from v18 to v34, each **OK** when what it installs is all there; an error such as *function … does not exist* means an update is missing.
| `schema-update-v16.sql` | **Yes, on your live project, after v15.** Step 1 of STAGE-13-SETUP.md. Roles and rights set by the super admin, custom roles, All projects, every check reading the rights |
| `schema-rollback-v16.sql` | Only to undo v16. Back to the v3.6 rules; keeps every setting and the history |
| `schema-rollback-v15.sql` | Only to undo v15. Back to the v3.5 rules; keeps all data |
| `schema-rollback-v14.sql` | Only to undo v14. The Head approves progress releases again; keeps all data |
| `schema-rollback-v13.sql` | Only to undo v13. Keeps all data and files |
| `schema-rollback-v12.sql` | Only to undo v12. Keeps all data |
| `schema-rollback-v11.sql` | Only to undo v11. Keeps all data |
| `schema-rollback-v10.sql` | Only to undo v10. Keeps all data |
| `schema-rollback-v9.sql` | Only to undo v9. Keeps all data |
| `schema-rollback-v8.sql` | Only to undo v8. Keeps all data |
| `schema-rollback-v7.sql` | Only to undo v7. Keeps all data |
| `schema-rollback-v6.sql` | Only to undo v6. Keeps all data |
| `schema-rollback-v5.sql` | Only to undo v5. Keeps all data |
| `schema-rollback-v4.sql` | Only to undo v4. Keeps all data |
| `schema.sql`, `schema-update-v2.sql`, `schema-update-v3.sql` | Only on a **new, empty** project (staging, see STAGING.md). Your live project already has them |
| `tests/` | **Never on Supabase.** Test tools for a local PostgreSQL |
