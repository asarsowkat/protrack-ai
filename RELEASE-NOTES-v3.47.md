# ProTrackAI v3.47: RASA Intelligence, the central knowledge and learning hub (October 2026)

RASA used to be an assistant in a side panel. v3.47 makes it the central knowledge layer of ProTrackAI: one workspace, **RASA Intelligence**, that shows what RASA knows, where each piece comes from, and what it still cannot answer. RASA learns only what a reviewer approves.

It is built into the existing app: the same menu, records, rights, projects and design. The RASA assistant (chat and avatar) is unchanged and still opens from the menu and the RASA button.

## The workspace (menu → RASA Intelligence)

Eight tabs:

- **RASA Overview**
  - A welcome panel with Ask RASA and six shortcuts.
  - Eight measures, all counted from the app's own records: connected modules, active knowledge sources, approved documents, indexed document versions, pending reviews, unanswered questions, successful updates, sync errors.
  - The modules in two columns: **Needs attention or not connected**, and **Connected knowledge**. Each card shows:
    - its state;
    - its sources and passages;
    - its last successful sync;
    - what could not be read;
    - a coverage ring;
    - Configure, View knowledge and Sync.
  - Recent learning activity, knowledge gaps grouped by module and project, and the learning progress.
- **Ask RASA**: questions with evidence and citations (see below), feedback, and "Teach a correction".
- **Knowledge Sources**
  - The module registry, giving each module's connection, what RASA reads, how it uses it, its sync strategy and counts.
  - Each module's sources, with their project, type, revision, approval status, version, passages, indexing time and access class.
  - The passages of each source, and the recent syncs with a Retry.
- **Teach RASA**: upload documents (through the Document Rack), teach a correction, add a business rule, knowledge gaps, and import module knowledge.
- **Learning Activity**: every sync, indexing, update, supersession, failure, proposal, approval, publication, rollback, gap and negative feedback, filtered by kind and module. Each entry links to its record.
- **Knowledge Review**
  - Queues: to review, to publish, published, needs revision, mine, closed.
  - Each proposal shows the existing knowledge beside the proposed change, the conflicts, the approvals and the audit history.
  - The log of published knowledge versions.
- **Analytics & Performance**: the measures listed below, with charts and the evaluation set.
- **RASA Settings** (super admin):
  - switch each module on or off;
  - its sync strategy;
  - the approval policies;
  - how long questions are kept;
  - what is on hold.

## The module registry: every module, with its real state

The registry lists 15 modules:
- **Connectors** (11): Scheduling (Primavera P6), Cost Control, Document Rack, Contracts, Productivity & Daily Reports, Executive Reports, Invoices & Cash Flow, Claims & Variations, Materials & Procurement, Quantity Takeoff (BOQ Engine), Projects & Issues.
- **Taught knowledge**: what reviewers have published.
- **No connector yet** (2): Project Visual and Budget & Cost Management, shown as **Not connected** with the reason.
- **SAP**: **Disabled** until IT, SAP, Cybersecurity and Finance approve.

A module is **Connected** only after a successful sync. Otherwise it shows one of:
- **Configuring**: not indexed yet, or not live yet in the release plan;
- **Syncing**;
- **Attention required**: the last sync failed, or some of its sources could not be read;
- **Disabled**.

Connection and indexing are shown apart. Adding a module needs one connector function and one registry line.

## The knowledge index

- **What a connector reads.** Each connector reads the records of the projects the person has access to:
  - the schedule status calculated from the baseline and daily reports, milestones (with "at risk"), and activities with their WBS;
  - released cost reports and their revisions (budgets, actual cost, commitments, EAC by WBS), earned value and cost plans;
  - every rack document with the text read from it, passage by passage, with its page, slide or sheet and its clause numbers;
  - contract terms;
  - daily reports by week;
  - internal and client reports, both draft and released;
  - invoices and the cash-inflow forecast;
  - delay events, change orders and claims;
  - purchase orders and materials;
  - drawings and quantity calculations;
  - projects and issues.
- **What each source keeps:** its project, module, record, revision, approval status, effective date, owner, access class, content hash and version.
- **Syncing:**
  - Records that have not changed are not indexed again (idempotent).
  - A changed record becomes a new version, with its history kept.
  - A removed record is marked deleted, and its passages leave the index.
  - A sync that fails publishes nothing. The module shows Attention required, and the sync can be retried.
- **On change.** Modules set to "on change" refresh a few seconds after a record is saved, while ProTrackAI is open. "Manual" waits for a sync. Nothing claims to be real-time.
- **Original files.** The Document Rack stays the authoritative place for them. RASA keeps the passages and a link.

## Answers

- **How an answer is made.**
  1. RASA applies ProTrackAI's own rules and calculations first. These are the same answers the assistant gives, such as EAC, SPI and milestones.
  2. It then searches the index for evidence, using:
     - words and stems, record numbers, WBS codes, activity IDs and clause numbers;
     - filters for project and module;
     - rules on approval and revision.
  3. The modules it consults are chosen from the question, so a cross-module question reads only the relevant modules.
- **Citations.** Each source is cited with its module, project, location (page, WBS, activity or clause), revision, approval status and indexing time, with a link to the record or document. Each citation is checked before it is shown.
- **What is labelled:**
  - draft and submitted records are marked as not approved;
  - superseded versions appear only when the question asks for history;
  - approved taught knowledge is marked as the trusted statement where it corrects a record.
- **When it has nothing.** RASA says it has no evidence and does not guess. The question is recorded as a knowledge gap.
- **Records a person may not open.** A question about them is answered as "nothing you can open". It is never recorded as a gap, and the answer never hints that such records exist.
- **Ambiguous questions.** "this project" with several projects in scope makes RASA ask which project.

## Teaching and review

- **Correction**: the incorrect statement, the corrected information, why, the supporting source, and the project and IDs. It can come from a previous answer, or from a "not helpful" mark.
- **Business rule**: name, description, purpose, module, formula or criteria, source, effective date, owner, reviewer and version.
  - A high-impact financial formula is kept as knowledge.
  - ProTrackAI's calculations change only with a tested release.
- **Knowledge for a gap**: the question itself is never trusted. The proposed answer is, once it is approved and published.
- **Workflow**:
  - Draft → Submitted → Under Review → Approved → Published.
  - The other outcomes are Rejected, Needs Revision, Superseded and Withdrawn.
  - Returning or rejecting a proposal needs a comment.
- **Approval rules:**
  - nobody approves their own proposal;
  - company-wide knowledge needs a designated approver;
  - a financial formula needs two different approvers and a confirmed regression check;
  - a conflict with published knowledge must be resolved first: replace the existing knowledge, or keep both.
- **Publishing and rollback.** Publishing gives a new knowledge version and indexes the knowledge. Rolling back gives another version and restores whatever the rolled-back knowledge had replaced. Every step is in the audit history.
- **Approval policies.** The number of approvals for each kind is set in RASA Settings.

## Rights (Settings → Roles and rights, group RASA)

| Right | Who has it by default |
|---|---|
| `rasa.teach`: teach RASA | Executives, regional managers, portfolio, planning, costing and project managers |
| `rasa.sync`: refresh what RASA reads | Planning and costing engineers |
| `rasa.review`: knowledge reviewer of their projects | Given by the super admin |
| `rasa.company`: approve company-wide knowledge | Given by the super admin |

The screen `rasa` can be shown or hidden per role in Role access. Every search re-checks the reader's rights:
- projects in access;
- cost and billing figures;
- the document rack's rows;
- report visibility;
- claims, issues, materials and the BOQ Engine.

## Analytics

The analytics tab shows:
- total sources and sources by module;
- approved and pending knowledge;
- indexing jobs that succeeded and failed;
- unanswered questions, negative feedback and repeated gaps;
- retrieval success rate and citation validity;
- answer quality rated by knowledge reviewers;
- average response time;
- language model usage (on hold);
- knowledge freshness and approval turnaround;
- questions and knowledge changes by day.

It can be filtered by project, module and period. Each measure says how it is made:
- **operational**, from the logs;
- **automated evaluation**: 10 questions with the module that should answer each, checking retrieval relevance, citation validity, permission isolation and time;
- **human-reviewed**.

No single accuracy score is claimed.

## On hold until alfanar IT and Cybersecurity approve

- **The language model on ProTrack's server** (Claude or Azure OpenAI). The adapter of v3.33 (`RASA_ENTERPRISE.llm` in config.js, needing both enabled and approved) stays off. When it is approved:
  - it receives only the evidence the asker may open;
  - no key ever reaches the browser.
- **Embeddings and vector search (pgvector).** The column and index are written in the SQL as comments.
- **Malware scanning of uploaded files.**
- **A server worker for indexing.** Until then, indexing runs in the signed-in person's browser, with their rights.

RASA Settings lists each of these with its state.

## Server

`schema-update-v50.sql` (with `schema-rollback-v50.sql` and STAGE-44-SETUP.md):
- the four rights and the `rasa` screen;
- the index tables, with a full-text index;
- the workflow tables;
- `rasa_sync`, which checks the right, the project and each source's access class against its module;
- `rasa_search` and `rasa_passages`, which return only what the asker may open;
- `rasa_act`, which handles questions, gaps, feedback, teaching, the review state machine and settings, checking everything again on the server;
- the taught knowledge, rebuilt from the published proposals.

It needs v49. It has not yet been run on a database.

## Checks

**New suite:** `tests/rasa_hub_demo.js`, 25 checks, all passing on the demo page. It covers:
- the registry's states and the menu;
- the first index;
- idempotent syncs, new versions, removals, and a failed sync that publishes nothing;
- permission isolation for a foreman and a project manager;
- an unauthorised question that is not recorded as a gap;
- cited contract clauses;
- gaps and clarifying questions;
- teaching, review, company-wide approvers, the two-approver financial formula, conflicts, publishing and rollback;
- gap answers, feedback and module switches;
- refresh on change;
- the evaluation set;
- every tab.

The other browser suites were run again after the change.
