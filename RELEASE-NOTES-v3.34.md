# ProTrackAI v3.34: approval and report emails really sent (October 2026)

Built from your request to continue with **approval email sending**.

## What was wrong
ProTrack prepared an email when a daily report, an internal report or a cost report was approved, and when a reminder was sent from Reporting status. It handed each email to a server function called `send-daily-report`. That function was never installed, so **no email was ever sent** on the live server. And the browser chose the recipients itself: had such a function been installed as it was called, anyone signed in could have sent any text to any address.

## What changed

### 1. The server decides who receives each email (schema-update-v38.sql)
The app now asks the server to **queue** an email about an event it really made. The server checks the event and works out the recipients itself.

| Email | Who may queue it | Who receives it |
|---|---|---|
| Daily report approved | The person who approved it, or a super admin | The roles ticked in Settings → Email with access to the project. Site engineers and site managers receive only the reports they reviewed or approved, when that box is ticked. Never foremen |
| Internal or cost report released | The person who approved it, or a super admin | The report email list (the region's own list for internal reports). That means its roles with access to the project, its named people and its valid other addresses. Weekly internal reports only when the list says so |
| Reporting status reminder | The person who sent it, within the hour | The people it named who still have access to the project |
| Test email | A super admin | Themselves |

Each event is emailed **once**: asking again returns the email already queued. Someone who did not make the event cannot queue it, or read its recipients.

Every email is kept in the outbox with its subject, body, recipients, status (queued, sending, sent or failed), attempts and error. Nobody can write the outbox directly. Each person sees the emails they queued, and super admins see all of them.

### 2. The emails go out through the company mailbox (Edge Function send-mail)
A new Supabase Edge Function, `send-mail`, sends a queued email through:
- **Microsoft 365** (Microsoft Graph), from a ProTrack mailbox IT sets up and limits, or
- **an SMTP relay** on port 465.

It records **sent**, with the provider's reference, or **failed**, with the reason. An email is tried at most **5 times**, then waits for **Send again**. The function sends only what the server stored, so the browser cannot change the recipients. Without a mail service set up, emails stay queued with the reason, and nothing is lost.

### 3. Settings → Email
- **Mail service:** whether it is **Ready**, with the provider and the sending address, or **Not ready**, with the reason. **Check the mail service** checks it again.
- **Send a test email to me** (super admin).
- **Send queued emails now** (super admin): sends whatever is still queued.
- **Emails** (was "Sent emails"): every email with its status. Failed ones show their reason, and super admins get **Send again**. Opening one shows its recipients, attempts and a preview.
- **The approval email settings** (on, roles, site roles only for their own reports) are now kept **on the server**. Only a super admin changes them; they no longer live in one browser.

When an approval email cannot be sent at once, the person who approved sees why, and Settings → Email lists it.

The demo page is unchanged: emails are prepared and listed as "Demo: not sent".

## Setup
STAGE-32-SETUP.md:
1. Run `schema-update-v38.sql`.
2. Deploy the `send-mail` function from `supabase/functions/send-mail/index.ts`.
3. Add its settings (from IT: the Microsoft 365 app registration and mailbox, or an SMTP relay).
4. Send a test email.

## Verified
| Check | Result |
|---|---|
| `supabase/tests/test_v38.py`, PostgreSQL 16 with schema and every update v2 to v38. It covers: <ul><li>daily reports: the approver, settings, roles, chain, switched off</li><li>reports: approver, default and region lists, weekly flag, named people, other addresses, no duplicates</li><li>reminders: sender, access, age</li><li>test emails</li><li>content limits</li><li>queued once</li><li>no direct writes, each person's own emails</li><li>Send again</li><li>rollback and again</li></ul> | 46 of 46 |
| `supabase/functions/send-mail/test.mjs` (Node 22, with Microsoft sign-in, Graph, SMTP and the database simulated). It covers: <ul><li>settings and their problems; SMTP 587 refused</li><li>who may send what</li><li>sent once</li><li>Graph and sign-in failures recorded</li><li>5 attempts, one sender at a time</li><li>no service</li><li>SMTP 465</li><li>the queue for a super admin or a schedule</li></ul> | 27 of 27 |
| `tests/mail_e2e.py`, the real app in Chromium against PostgreSQL with every update v2 to v38. It covers: <ul><li>the approver's daily report email queued with the server's recipients (site roles only from the chain, no foreman) and handed to the function by its id only</li><li>approving twice queues one email</li><li>someone else refused, and cannot read the recipients</li><li>no direct writes; each person sees only their own emails</li><li>the internal report email to the report email list</li><li>Settings → Email: mail service check, test email, failed reason, preview, Send again, Send queued emails now</li><li>settings saved on the server, by the super admin only</li><li>after the rollback: listed as not sent with the reason, nothing handed to a function; v38 again keeps every email</li></ul> | 27 of 27 |
| The 25 console acceptance scripts in `tests/*.js`, on this version and on main | Same results as main, apart from two scripts brought up to date (a prepared report email now keeps its report; the version check accepts 3.33 or later). The remaining failures need the chart library from the internet and fail on main too |
| The older demo suites | Same results as main. Several have not been updated since v3.9 and fail on main too |

**Not verified:** the function on Supabase's own runtime, and a real Microsoft 365 or SMTP mailbox. The test email in Step 4 of the setup is the real test.
