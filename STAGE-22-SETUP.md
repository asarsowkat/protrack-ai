# v3.19.2 setup: letters and correspondence on delay events, on the server

This takes about 8 minutes. **Do not** upload a new `config.js`. The v24 update must be in first (STAGE-20-SETUP, the delay events register). v25 is not needed first.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v26.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
   - If it says **"Run schema-update-v24.sql (STAGE-20-SETUP) first"**, do STAGE-20-SETUP, then run this again.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select (select count(*) from pg_proc where proname in ('delay_corr_act','delay_corr_features','pt_dly_corr_link','pt_dly_file_can','pt_dly_corr_guard')) + (select count(*) from storage.buckets where id = 'delay-docs' and not public) + (select count(*) from pg_policies where (tablename = 'delay_corr' and policyname = 'dc_read') or policyname in ('protrack_delay_docs_read','protrack_delay_docs_add')) + (select count(*) from pg_trigger where tgname = 'trg_dly_corr_guard') as installed;
   ```

   Expect **10**: five functions, the private bucket, three access rules and the trigger.

**What the update does:**
- **`delay_corr`** keeps the letters, e-mails, notices, site instructions and minutes behind each delay event:
  - type, direction (received from the Employer / Engineer, sent by alfanar, internal), date, reference, subject, from, to, notes
  - the file, when there is one
- **Files** go to a new private bucket, **`delay-docs`**: up to 50 MB, the same file types as the document rack.
- **Who reads** (the server checks it, whatever the page shows): the people who read the register. That is everyone who sees cost figures, on the projects in their access.
- **Who records:** the people who keep the register (right *Keep the delay events register* on the project). The same rules apply to the files.
- **Removing a record:**
  - needs a reason
  - the record and its file stay, marked removed, and the history keeps it
  - an event with letters cannot be deleted until they are removed
- **Add its reference to the register** (ticked by default):
  - a received letter's reference goes to *Supporting documents ref.*, a sent one to *Notice of claim documents ref.*
  - a sent notice of claim also sets the notice submission date when the event has none
  - the event's rules apply (for example, no notice dated before the event)

Nothing else changes. Running it twice is safe.

## Step 2: Publish

Tell Claude "it showed 10". Claude publishes v3.19.2, and **live.html** uses it within about 2 minutes. Then press **Ctrl + F5**.

Until the update is in, an event's window says *"Recording letters needs the v26 database update (see STAGE-22-SETUP)"*. The rest of the register works.

## Step 3: Check it (5 minutes)

| Do | Expect |
|---|---|
| As a planning engineer: open a delay event → *Correspondence and letters*. Record a **Letter**, **Received**, with a reference and a PDF | Listed with its file; **Preview** shows the PDF; *Supporting documents ref.* now ends with the reference and the date |
| Record a **Notice of claim**, **Sent**, on an event with no notice date | The event's notice submission date is set; *Days to notice deadline* says *Notice served* |
| Attach the same PDF again to the same event | Refused: "This file is already attached to this event" |
| **Download the EOT pack (ZIP)** | `EOT_pack_<PE>_<event>_<date>.zip`, holding `00_Chronology.xlsx` and the files, numbered in date order |
| **Remove** a record without a comment, then with one | Refused, then removed; it stays in the history |
| As a project manager of the project | The letters are listed and open; no *Record a letter* form and no *Remove* |

To see what the server saved (it only reads):

```sql
select (select event_no from delay_events where id = event_id) as event, corr_date, kind, direction, ref_no, subject, file_name, removed_at from delay_corr order by event_id, corr_date;
```

## If something goes wrong

| What you see | What to do |
|---|---|
| "Recording letters needs the v26 database update" | Step 1 has not run, or live.html was not refreshed. Run the check in step 1, then press Ctrl + F5 |
| "The file was not stored: … row-level security …" | The person does not keep this project's register, or the event was deleted. Check their right and access |
| "The file was not found in storage; upload it again" | The upload was interrupted. Add the record again |
| "Run schema-update-v24.sql (STAGE-20-SETUP) first" | Do STAGE-20-SETUP, then run this update again |

**To undo:** run `schema-rollback-v26.sql`. Nobody can add or remove records any more, and events with letters can be deleted again. Every record and file is kept and can still be opened.
