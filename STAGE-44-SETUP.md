# v3.47 setup: RASA Intelligence

This takes about 5 minutes. **Do not** upload a new `config.js`. It needs v49 (STAGE-43-SETUP). It passed 93 checks on a test copy of the full schema (PGlite), but has not yet been run on Supabase, so try it on a staging copy first.

## Step 1: Update the database (2 minutes)

1. Supabase → **SQL Editor** → **New query** (use an empty tab).
2. Open `supabase/schema-update-v50.sql` from this package in Notepad. Select all, copy, paste and press **Run**.
   - The result should be **"Success. No rows returned"**.
3. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select rasa_features() ->> 'version' as version, rasa_features() ->> 'vector_search' as vector_search;
   ```

   Expect **50** and **false**. The vector search stays off until it is approved.

**What the update adds:**
- **Four rights:** `rasa.teach`, `rasa.sync`, `rasa.review` and `rasa.company`.
- **The `rasa` screen**, in Role access.
- **The knowledge index:** sources, and their passages with a full-text index.
- **The review workflow tables:** proposals, published versions, gaps, feedback, questions, activity and settings.
- **Server functions that check every write and search again:**
  - the reader's projects;
  - cost figures;
  - the document rack's rows;
  - report visibility;
  - every state change of a proposal.
- **A fix for four earlier tables:** cost plans (v45), report pictures (v47), and client report format choices and exports (v48). Their read rules refused the app with "permission denied for function user_sees". After this update the app can read them again.

## Step 2: Give the review rights (1 minute)

In **Settings → Roles and rights**, group **RASA**:
- give **"RASA: review, approve, publish and roll back knowledge"** to the knowledge reviewers, for example the Head of Planning and Cost Control;
- give **"RASA: approve company-wide knowledge"** to the designated approvers.

Teaching and refreshing are already on for their default roles (see RELEASE-NOTES-v3.47).

## Step 3: Index and check (2 minutes)

1. Sign in as a planning engineer or the super admin. Open **RASA Intelligence**.
   - The first visit indexes the modules of your projects. The Overview then shows the connected modules with their sources.
   - Project Visual and Budget & Cost Management show **Not connected**.
   - SAP shows **Disabled**.
2. In **Ask RASA**, ask "What notice period does the contract give for a claim?". The answer cites the contract document's passage, if its text has been read in the Document Rack.
3. In **Analytics & Performance**, press **Run the evaluation set**.

## On hold until alfanar IT and Cybersecurity approve

Nothing below is switched on by this update. When IT approves an item, the ProTrack team switches it on and records the approval.

| Item | What to do once approved |
|---|---|
| Language model on ProTrack's server (Claude or Azure OpenAI) | Deploy the server endpoint described in v3.33. It reads the asker's rights and receives only the passages `rasa_search` returns for them. Then set `RASA_ENTERPRISE.llm.enabled` and `approved` in config.js. No key in the browser. |
| Embeddings and vector search | `create extension vector;`, add the `embedding` column and HNSW index (comments in schema-update-v50.sql), and fill them from a server worker with the approved embedding service. |
| Malware scanning of uploads | Connect the approved scanning service to the `documents` storage bucket before a file is offered for text reading. |
| Server worker for indexing | A scheduled Supabase Edge Function that rebuilds the index from the tables with a service role, instead of the signed-in person's browser. |

## To undo

Run `supabase/schema-rollback-v50.sql`. It removes the RASA Intelligence tables and functions, and the rights and screen. The RASA assistant keeps working.
