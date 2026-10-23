# v3.34 setup: approval and report emails really sent

This takes about 30 minutes once IT has given the mailbox details. **Do not** upload a new `config.js`. It needs the v16 update (STAGE-13-SETUP). Report emails need v23 (STAGE-19-SETUP); reminder emails need v29 (STAGE-25-SETUP). Try it on a staging copy first: the database part has run only on a test database, and the send-mail function has run only with Microsoft Graph and SMTP simulated.

## What you need from IT (ask first)

Choose **one** way out. Microsoft 365 is recommended if the company mail is on Microsoft 365.

| Way | What IT gives you |
|---|---|
| **Microsoft 365 (Microsoft Graph)**, recommended | 1. A mailbox for ProTrack, for example `protrack@company.com` (a shared mailbox is enough).<br>2. An app registration in Microsoft Entra ID with the **Mail.Send** application permission, admin consent granted.<br>3. An application access policy that limits the app to that one mailbox.<br>4. The **tenant ID**, the **client ID** and a **client secret** (and its expiry date). |
| **SMTP relay** | Host name, user name and password of a relay that accepts **port 465** (SSL). Supabase does not allow ports 25 and 587. |

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v38.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select mail_features(), (select count(*) from pg_proc where proname in ('mail_queue','mail_retry')) as functions, to_regclass('public.mail_outbox') is not null as outbox;
   ```

   Expect `{"queue": true, "version": 38}`, **2** and **true**.

**What the update does:**
- **The outbox** (`mail_outbox`): one row per email, with the recipients the server worked out and its status (queued, sending, sent, failed).
- **Who receives an email** is decided by the server, never by the browser:
  - **Daily report:** the roles in Settings → Email with access to the project; site engineers and site managers only for the reports they reviewed or approved, when that box is ticked.
  - **Internal or cost report:** the report email list, for the region where one is set.
  - **Reminder:** the people it named who still have access.
- **Only the person who made the event** (approved the report, sent the reminder), or a super admin, can queue its email. Each event is emailed once.
- **Rollback:** nothing else changes, and running the update twice is safe.

## Step 2: Install the send-mail function (10 minutes)

1. Supabase → **Edge Functions** → **Deploy a new function** → **Via editor**.
2. Name it exactly **`send-mail`**.
3. Open `supabase/functions/send-mail/index.ts` from this package in Notepad. Select all, copy, and paste it over the sample code. Press **Deploy**.
4. Leave **Verify JWT** switched on.

## Step 3: Give the function its settings (5 minutes)

Supabase → **Edge Functions** → **Secrets** (or Project Settings → Edge Functions). Add these:

| Name | Microsoft 365 | SMTP relay |
|---|---|---|
| `MAIL_PROVIDER` | `graph` | `smtp` |
| `MAIL_FROM` | the ProTrack mailbox, for example `protrack@company.com` | the sending address |
| `MAIL_FROM_NAME` | optional, for example `ProTrack` | optional |
| `GRAPH_TENANT_ID` | from IT | |
| `GRAPH_CLIENT_ID` | from IT | |
| `GRAPH_CLIENT_SECRET` | from IT | |
| `SMTP_HOST` | | from IT |
| `SMTP_PORT` | | `465` |
| `SMTP_USER` | | from IT |
| `SMTP_PASS` | | from IT |

You do not need to add `SUPABASE_URL` or the keys: Supabase provides them.

## Step 4: Check (5 minutes)

1. Reload the live app.
2. Sign in as super admin and go to **Settings → Email**.
3. **Mail service** should say **Ready**, with the provider and the sending address.
   - If it says **Not ready**, the reason is shown (for example a missing setting). Fix the secret and press **Check the mail service**.
   - If it says the function is not deployed, repeat Step 2 and check the name is exactly `send-mail`.
4. Press **Send a test email to me**. It should arrive in your mailbox within a minute, and the Emails list shows it **Sent**.
5. Approve a daily report on a test project. Its email appears in the list as **Sent**, with the recipients the server chose.

## If something goes wrong

| What you see | What to do |
|---|---|
| Emails listed as **Queued: No mail service is set up** | Step 3: `MAIL_PROVIDER` is missing or misspelt |
| **Failed: Microsoft sign-in failed** | The client ID or secret is wrong, or the secret has expired. Ask IT for a new secret and update `GRAPH_CLIENT_SECRET` |
| **Failed: Microsoft Graph refused the email** | The app has no Mail.Send permission for that mailbox, or `MAIL_FROM` is not the mailbox IT allowed |
| **SMTP port 587 is blocked** | Use port 465, or Microsoft 365 |
| **Not sent: the server needs the v38 update** | Step 1 has not run |

After fixing the problem, press **Send queued emails now**, or **Send again** on one email. An email is tried at most 5 times before it waits for Send again.

## Optional: send queued emails on a schedule

If an email cannot be sent at once (for example while the mailbox is being set up), it stays queued. **Send queued emails now** sends them. A Supabase scheduled job can also call the function every 15 minutes with `{"pending": true}` and the service role key; ask Claude to set it up when you want it.

## To undo

Run `schema-rollback-v38.sql`. The app then lists emails as not sent, as before v3.34. The outbox and every email in it are kept. To stop sending without undoing, delete the `MAIL_PROVIDER` secret.
