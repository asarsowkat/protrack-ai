# ProTrackAI v3.19.1: the delay register's drop-down lists (October 2026)

The **Delay events register** (v3.19) now uses the drop-down lists of the company workbook. The **super admin** can add, remove and reorder their items.

| List | Items (as in the workbook) |
|---|---|
| **Event Status List** | Ongoing, Closed |
| **Entitlement List** | EOT Only, EOT + Cost, V.O (Cost Only), V.O (Time & Cost), To Be Determined |
| **Liability List** | Employer, Engineer / PMC, SubContractor / Supplier, Neutral / Force Majeure, Joint Venture |
| **Concurrency List** | No Concurrency, Contractor Concurrent Delay, Third Party Concurrent, Under Assessment |
| **Owner List** | Regional Manager, Portfolio Manager, Project Manager |
| **Mitigation List** | Notice submitted, Particulars under preparation, EOT Claim Submitted, EOT Claim Approved, Revised Schedule Submitted & Approved |
| **Claim Identification List** | Employer Delayed Approvals, Delayed access to Site, Delayed permits, Design changes, Employer / Engineer Variations, Suspension instructions, Employer / Engineer acts, such as verbal instructions or approval comments, Unforeseen conditions, Force Majeure, Legislative Change, Claims Related to S/C or Suppliers, Others,... |

The last Mitigation item was cut off in the sheet shared (*Revised Schedule Submitted & Appro…*). It is entered as **Revised Schedule Submitted & Approved**; the super admin can correct it.

## In the register
- **The window:** the seven columns are drop-downs: claim identification, status, entitlement type, liability party, concurrency flag, mitigation / recovery action and claim owner. Claim identification and mitigation used to be typed.
- **Filters:** the entitlement and liability filters follow the lists.
- **Matching:** values match the list whatever the case, and the list's spelling is kept.
- **Values outside the lists:**
  - a value outside the list is refused, in the window and on upload: *"Liability party: "The client" is not in the list. A super admin can add it in Settings → Delay register lists"*
  - an event keeps a value removed from its list since; it shows as *… (not in the list)* and the event can still be saved
- **The template** has a **Lists** sheet with the seven lists in the workbook's layout, and *How to fill* points to it.
- **Super admin shortcut:** *Edit the drop-down lists* above the register opens the settings.

## Settings → Delay register lists (super admin)
- **The tab:** a new Settings tab, also in the menu under *Administration*.
- **Each list:**
  - shows its items and how many events use each
  - **↑ / ↓** reorder, **Remove** (asks to confirm and says how many events keep the item), **Add** (Enter works too)
  - **Back to the workbook's list** once it has changed
- **Rules:**
  - 1 to 60 items per list
  - none empty, at most 200 characters
  - no two alike, whatever the case
- **Status list:** stays *Ongoing / Closed*. It decides the closing date and the claim duration, so it cannot be changed.
- **History:** every change is in the change log.

## Demo
The sample events use the list values. A browser that already held the v3.19 samples has them converted when the page loads.

## Checks
`tests/delay_lists_demo.js` runs 15 checks in the browser console on the demo page. They cover:
- the lists word for word, and the drop-downs
- refusal of values outside a list, and matching whatever the case
- adding, refusing duplicates and empty items, and the fixed status list
- removing an item an event keeps, reordering, the change log, and going back to the workbook's list
- only the super admin changing the lists
- refusal on upload, the template's Lists sheet, and the converted samples

The 26 checks of `tests/delay_register_demo.js` still pass.

## Server
`schema-update-v25.sql` (STAGE-21-SETUP.md) adds:
- the lists (`delay_lists`) and `delay_lists_set`, super admin only, with the same rules
- an append-only history
- the list check in `delay_act` and `delay_import`

Until it is run, live.html uses the workbook's lists and they cannot be changed. Undo: `schema-rollback-v25.sql`, which keeps the lists. The SQL has not been run on a database yet.
