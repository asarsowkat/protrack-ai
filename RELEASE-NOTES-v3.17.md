# ProTrackAI v3.17: cost report margin by column, and report emails (October 2026)

## Monthly cost report: gross margin for every budget column
The **Contract value**, **Gross margin** and **% Gross margin** rows now fill every budget column, each on its own contract value:

| Column | Contract value used |
|---|---|
| Tender (A), Rev-0 (B1) | **original contract value** |
| Revised Rev-0 (B2), Current budget (D), EAC (I) | **internal revised contract value** (original + price considered internally, v3.11) |
| Prev. version (C) | **the previous month's contract value**: the contract value of the previous released cost report, else the internal revised value at the end of the previous month |

**Where it shows:**
- the cost report form, with live figures as you type;
- the released report (executive report project view, cost report page);
- the Excel export in the company layout. Its Contract Value row is per column, with a note saying which value each uses.

**Saving and approval:**
- The values are saved with the report.
- At approval, the original and internal revised values are set as of approval, as the contract breakdown already was.
- Reports saved before v3.17 keep one value for every column.

**Demo:** the sample released cost reports get their per-column values.

## Emails when reports are approved
**When it's sent:**
- An **internal report**, monthly (and weekly unless switched off), is approved and released.
- A **monthly cost report** is approved and released.

**What it carries:** the released figures and a link (`#rel=…`) that opens the report in ProTrack.
- **Internal report:** planned, actual, SPI, forecast finish, the baseline comparison, summary, key issues, recovery, next period, management remarks.
- **Cost report:** current budget, actual, EAC, VAC, commitments, the internal contract value, gross margin on EAC, and the tender margin.

**Who receives it:**

| List | Set by | Default |
|---|---|---|
| Internal reports | **Super admin**, Settings → Email → Report emails; per region, the **section planning manager** of the region (Planning & Scheduling → Internal Reporting → *Report email for your region*) or the super admin | project managers, portfolio managers, regional managers, executives, planning engineers, with access to the project |
| Monthly cost reports | **Super admin**, Settings → Email → Report emails | project managers, portfolio managers, regional managers, executives, costing engineers, with access to the project |

**Each list holds:**
- **roles:** everyone in the role with access to the project;
- **named people:** any project;
- **other addresses:** validated.

The list also has an on / off switch and, for internal reports, *weekly too*. A region without its own list uses the default.

**Rights:** a section planning manager can't change another region's list or the defaults. Other roles can't change any list.

**Where emails are listed:** with the daily report emails in **Settings → Email → Sent emails**, with recipients, status and a preview.
- **Demo page:** emails are prepared but not sent.
- **ProTrack server:** they go through the existing mail function, `send-daily-report`.

## On the ProTrack server (live.html)
**Works on the server now:**
- the emails are sent through the server's mail function when a report is approved there;
- the cost report margins are worked out in the browser.

**Needs a server update:**
- **The email lists** are kept in each browser for now. A list must be stored on the server so it applies whoever approves.
- **The per-column contract values (`cv_by`)** need to be stored with the cost report, or computed by the server.

**The v23 update is ready, not yet installed** (`supabase/schema-update-v23.sql`, STAGE-19-SETUP; it needs v20 and v22). Once it is in, live.html sees it (`margin_mail_features()`) and:
- **keeps the email lists on the server** (`report_mail_lists`), so a list applies whoever approves, in any browser. The page reads them at sign-in and saves each change through `report_mail_set`:
  - the super admin changes every list;
  - a region's section planning manager changes that region's internal report list only;
  - everyone who approves reports reads them;
  - the server refuses an unknown role or person, an address that is not an email address, and more than 50 addresses;
- **keeps `cv_by` with the cost report.** A cost report save sends the values the form shows, through `release_act_cv`. The server works them out itself with the same rules (a trigger, on every save of a draft) and sets A, B1, B2, D and I as of approval. Then they are frozen with the released version. If its values differ from the page's (the change order and claim log changed while the page was open), the page says which column. `release_act` and `release_act_bl` are not replaced.

Until then, live.html behaves as above, with a one-line note in Settings → Email → Report emails. Before v23 the page never sends `cv_by` to the server, since `release_act` would refuse it as not a number. Lists set in a browser before v23 are not moved to the server; set them again. Cost reports saved before v23 have no `cv_by` until their next save as a draft.

**Not yet checked:** the SQL has not been run (there is no PostgreSQL on the build machine), and live.html has not been opened against the real server. In the page, with the server calls stubbed, the lists load from the server's rows, a list change sends `report_mail_set`, and a cost report save sends `crCompute`'s `cv_by` to `release_act_cv`. The demo page behaves exactly as before.

## Checks
`tests/margin_mail_demo.js` runs 17 checks in the browser console on the demo page. It covers:
- the margin bases per column and the previous month;
- the table and the Excel export;
- the default internal report list;
- the internal report email: figures, link, demo status;
- a section planning manager's regional list, weekly switched off, and other regions refused;
- the cost report email with its margin;
- address validation, the Settings section, rights, and the link opening the report.

The 25 contract value, 28 cash, 18 baseline, 22 Tender, 17 import and 24 Project Visual checks still pass.
