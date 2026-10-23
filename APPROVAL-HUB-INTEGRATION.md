# ProTrack ↔ Approval Hub: integration specification (ProTrackAI v3.39)

**For the IT team.** It describes how Approval Hub, or a small connector written by IT, exchanges workflows (WF) with ProTrack for two forms:
- the **Budget Supplement / Returns Request** (BRF, form AP/Planning-BRF);
- the **Change Request** (CRF).

ProTrack prepares and submits the forms. Approval Hub runs the approvals and reports the outcome. ProTrack then posts each approved request to its log on its own.

Nothing in ProTrack calls Approval Hub directly. The hub, or the connector, **pulls** the submissions and **pushes back** the status. This works whatever Approval Hub's own interface is, and it needs no inbound firewall opening to Approval Hub.

## 1. Connection

| Item | Value |
|---|---|
| Base URL | The Supabase project URL of ProTrack, e.g. `https://<project>.supabase.co` |
| Endpoint style | `POST /rest/v1/rpc/<function>` with a JSON body `{"p": {...}}` |
| Headers | `apikey: <the project's anon key>`, `Content-Type: application/json` |
| Authorisation | A **token** in the body (`"token"`). In ProTrack, the super admin opens **Cost Control → Budget & change requests → Approval Hub** and presses **Connect: make the token**. The token is shown **once**; ProTrack keeps only its SHA-256 hash. Making a new token stops the old one; **Switch the link off** stops all calls. |
| Transport | HTTPS only. Keep the token in the connector's secret store. |

Every call checks the token. A wrong or switched-off token returns HTTP 4xx with the message `Not authorised`.

## 2. Taking submissions: `wf_hub_next`

```http
POST /rest/v1/rpc/wf_hub_next
{"p": {"token": "pthub_…", "limit": 20}}
```

Response:

```json
{"items": [
  {"message_id": 17, "action": "submit", "payload": {
     "form_id": "WF-261023-a1b2c3", "kind": "BRF", "form": "Budget Supplement / Returns Request (AP/Planning-BRF)",
     "ref_no": "BR-07", "project": {"id": "P1", "pe_number": "PE-262", "name": "…", "region": "R1"},
     "title": "…", "totals": {"supplement": -167650, "savings": 1939967, "net": 1772317, "lines": 3},
     "lines": [{"description": "…", "category": "Project Execution", "user_field": "SM", "wbs_id": "PE-262-01-001-01", "amount": "-120000", "remarks": "…"}],
     "data": {"…": "general information, budget summary by user field, impact, …"},
     "approvers": ["Project Manager", "Costing Manager", "Portfolio Manager", "Planning Manager", "Regional Manager", "Vice President"],
     "prepared_by": "…", "submitted_by": "…", "submitted_at": "2026-10-23T10:15:00Z", "link": "live.html#wf=WF-261023-a1b2c3"}},
  {"message_id": 18, "action": "cancel", "payload": {"form_id": "…", "ref_no": "BR-06", "wf_no": "WF-1001", "reason": "…"}}
]}
```

- **Delivery.** Each message is handed out once. It is marked *Taken*, and handed out again after 15 minutes if it is not acknowledged (at most 10 times).
- **Amounts.**
  - Line amounts follow the budget supplement log: **negative = supplement** (raises the budget), **positive = saving**.
  - Change requests carry their prices and cost in `data`: `price_submitted`, `price_client`, `price_internal`, `cost_rev0`, `cost_current`, `client_status`, `client_ref`, `sub_date`, `description`.
- **Approvers.** `approvers` is the routing ProTrack expects, from the company approval box:
  - the **Vice President** is included when contingency is used;
  - the **Executive Vice President** when the management reserve is used.

  Approval Hub keeps its own routing rules; this list is for information and checking.
- **Cancellations.** A `cancel` message means the preparer withdrew the request. Close the WF in Approval Hub.

## 3. Reporting back: `wf_hub_update`

```http
POST /rest/v1/rpc/wf_hub_update
{"p": {"token": "pthub_…", "message_id": 17, "status": "received", "wf_no": "WF-1001", "step": "Project Manager"}}
```

| `status` | When | Required fields | Effect in ProTrack |
|---|---|---|---|
| `received` | The WF was created in Approval Hub | `message_id` (acknowledges the message), `wf_no` | The form becomes **In approval** with the WF number |
| `failed` | The WF could not be created | `message_id`, `error` | The message is marked *Failed* and shown to the super admin |
| `in_approval` | Any step changes (optional) | `form_id`, `step`, optionally `approver`, `comment` | The current step is shown on the form |
| `approved` | Final approval | `form_id` (or `project_id` + `ref_no`), `date` (YYYY-MM-DD), optionally `approver`, `comment`, `wf_no` | The form is **Approved** and **posted at once** (below) |
| `rejected` | Final rejection | `form_id`, `date`, `comment` (the reason) | The form is **Rejected**; nothing is posted |
| `returned` | Sent back for correction | `form_id`, `date`, `comment` (the reason) | The form goes back to the preparer; resubmitted, it keeps the same WF number |

Rules ProTrack checks:
- The WF number is required, up to 40 characters.
- The decision date cannot be in the future (Saudi time) or before the submission.
- Rejected and returned decisions need a reason of at least 5 characters.
- A decision on a form that is no longer submitted is refused with the reason. Retrying a `received` after the form moved on is harmless.

## 4. What ProTrack does on approval

- **BRF:** each line becomes a row of the project's **budget supplement log**:
  - the row number is `BR-07/1`, `BR-07/2` …, or `BR-07` for a single line;
  - it carries the WF number, its user field, category, WBS, amount and remarks;
  - its **WF date** is the approval date;
  - its **version** (the month of the cost report it counts in) is the month of the approval.
  - The costing engineer or coordinator can move the version to the month before the approval, or any month up to the current one, with a reason.
  - These rows keep their amounts: on the log screen only their version and remarks change, and they cannot be removed there.
- **CRF:** the request is added to the **change order and claim log** as a VO, with its prices, cost, client status and the WF number and date. If the log already has that reference, the WF number and date are written on it.

## 5. Until the link is live

The **costing coordinator** (right `wf.record`) opens the form and records the Approval Hub decision by hand: decision, WF number, date, approver and comment. The form says it was recorded by hand, and by whom.

Once the link is connected, recording by hand is refused unless the person ticks that the hub's decision did not arrive.

## 6. Testing

1. Make a token on a test project.
2. Submit a BRF from ProTrack, then call `wf_hub_next` and acknowledge with `received` and a test WF number.
3. Call `approved`.
4. Check that the form shows **Approved** and that the budget supplement log shows the rows.
5. Switch the link off, and make a new token for production.

The database tests (`supabase/tests/test_v43.py`) run these calls with the anon role.
