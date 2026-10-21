# ProTrackAI v3.27: RASA across every module, and the release strategy (October 2026)

RASA now answers from all the modules of ProTrackAI, including the BOQ Engine and the documents you upload. It follows the go-live plan: as each stage goes live, RASA starts answering about its modules.

## Release strategy (Settings → Release strategy, super admin)

**Setting the plan:**
- Put each module in a stage and give each stage a name and a planned go-live date.
- Choose **Live up to**. "Nothing yet" is allowed, for before the first go-live.

**What it changes:**
- **RASA answers from live modules only.** About a module not live yet, it names the stage: *"BOQ Engine is not live yet. It goes live in Stage 4."*
- **Super admins can test early.** A super admin can still ask about a module that is not live yet. The answer is marked *Test answer*.
- **Optional:** hide the modules not live yet from everyone's menu. Super admins still see them.
- **Every change is recorded,** with who made it and when.

**The proposed plan, which you can change:**

| Stage | Modules |
|---|---|
| 1 | Daily Reports, Planning & Scheduling, Projects & Handover, Reports & Dashboards |
| 2 | Executive report & reporting status, Project document rack, Cost Control |
| 3 | Materials & Procurement, Claims & Variations, Invoices & Cash Flow |
| 4 | BOQ Engine |

Until the super admin saves a plan, every module is live, as before.

## RASA's new answers

Ask in plain words, or use the new suggestions. Each answer gives the screen's own figures, what they are based on, and a button to open the screen.

| Module | Example questions |
|---|---|
| BOQ Engine | *BOQ quantities*, *How much concrete is in the BOQ?* (from the released estimate; a newer revision under review is shown beside it) |
| Project document rack | *Contract documents*, *What does the contract say about retention?*, *What is the time bar for a notice of claim?* |
| Delay events register | *Delay events* (ongoing, schedule impact, notices past the time bar or due soon) |
| Invoices & Cash Flow | *Cash-out forecast*, *Cash-inflow forecast*, *Cash flow forecast* (both, and the net) |
| Materials & Procurement | *Material deliveries*, *Purchase orders* |
| Projects | *What is the contract value?* (original and revised) |
| Planning | *Intermediate milestones*, *Progress by phase*, *E&P progress* (as the internal report works them out) |
| Reporting status | *Reporting status* (what is released and what is overdue) |
| Every module | *find QOT-TL-CIV-101*, *find Event 01*, *where is the power transformer* (a search by name) |

"Cash flow forecast" used to get "no evidence"; it is now answered.

When nothing answers a question, RASA searches the live modules by name before saying "no evidence".

**New alerts from RASA:**
- a notice of claim past its time bar, or due within 7 days;
- a BOQ estimate waiting for your review.

## Documents: RASA reads their text

**How the text is read:**
- A file uploaded to the document rack has its text read in the browser and kept for RASA. This covers PDF (the text layer), Word, Excel, CSV, TXT, XER and XML.
- The document shows *"RASA: text read, N pages"*.
- A scanned PDF or a picture has no text layer. RASA says so and cannot quote it.
- Documents uploaded earlier: press **Read the text now** on the document, or **Read their text now** in Settings → Release strategy for all of them.

**How RASA answers from it:**
- RASA quotes the passage word for word, with the document, revision and page, and marks the words.
- It **does not interpret contract terms.** For a contractual position, ask the contracts team.
- When no passage holds all the words you asked about, RASA shows the closest passages and says so.

**Who can do what:**
- Only the people who keep the box, or a super admin, read a document's text.
- Only those who can read the document see its text.

**Sample text on the demo page:**
- The demo's sample contract (Riyadh Metro L7, box C01) has **sample text**, marked as sample on every page.
- Its price, payment, advance and retention clauses follow the project's own terms in Settings → Projects and terms.
- Its delay damages (0.1% a day, up to 10%), notice of claim (28 days), performance security (10%) and defects period (365 days) are sample values.

## What has not changed

- **Role and project access:** RASA answers only about what you can open. A foreman, for example, still gets no cost, delay or document answers.
- **No outside AI on the server:** signed in to the ProTrack server, no project data goes to an outside AI service. Document search runs in the database.
- **The language model is demo-only:** it is used only on the demo page, with sample data. It now also sees only the live modules.

## Server update

`schema-update-v34.sql`, with `schema-rollback-v34.sql`, and the step guide **STAGE-28-SETUP.md**. It has not yet been run on a database.

## Checks

- **New suite:** `tests/rasa_modules_demo.js`, 37 checks, all passing.
- **Existing suites:** all 19 pass, 411 checks.
- **Screens:** every screen opened as each of the 11 roles, 220 screen views in all, with no error.
- **RASA suggestions:** all 225 suggestion answers (across the 11 roles) were given, with no blank value.
- The Python test `tests/rasa_demo.py` no longer lists "cash flow forecast" as untracked.
