# ProTrackAI review, module by module (v3.26.1, October 2026)

Every module of the prototype was checked for errors and logic gaps after the v3.19–v3.26 changes. The check had two parts:

1. **Automated runs in the browser:**
   - every acceptance suite;
   - every screen opened as each of the 11 roles;
   - every report window opened.
2. **A read-through of the code in four groups:**
   - reporting;
   - BOQ Engine;
   - cost and commercial;
   - the server updates v24–v33 against the app.

Each finding was checked against the code before anything was changed.

## Result

| | Before the fixes | After the fixes |
|---|---|---|
| Acceptance suites | 19 of 19 passing (410 checks) | 19 of 19 passing (411 checks; one check added) |
| Screens opened, 11 roles (with every report, Settings tab and BOQ Engine section) | 456, no error | 456, no error |
| Report windows opened (internal and client, every tab, weekly and monthly, 3 users) | 729, no error | all, no error; plus 48 cost report windows |
| Console errors | none | none |
| Findings from the code read-through | 92 (19 reporting, 25 BOQ Engine, 23 cost and commercial, 22 server, 3 found during the runs) | 84 fixed, 8 left with a reason (below) |

The automated runs found no runtime error. All the defects below are logic gaps: wrong figures, rules that could be bypassed, or data that could be lost in some situations.

## Reporting (internal, client, executive, reporting status)

| # | Finding | Fix |
|---|---|---|
| 1 | **The Releases screen looped forever** for a planning section manager whose role is not planning or costing, such as a PM or an executive named for a region | A regional planning section manager sees Internal Reporting; the screen never loops |
| 2 | **A report prepared after its period took today's schedule**, not the one in force at the period end: planned and actual %, design and procurement, external progress, forecast dates. The approver then had to "validate" differences the system created itself | Every computed figure comes from the schedule in force at the period end. The data date is the period end when that is before today |
| 3 | **Activity rows were kept only for the two latest schedules.** Reports revised later lost their intermediate milestones, E&P and daily-report comparison, and froze the empty result | Rows are kept for the six latest schedules and always for the one just loaded (live loads the same). A save never replaces saved figures with empty ones when the rows are gone |
| 4 | A missing client actual was taken as 0, which forced a "reason" for a figure never computed | No client schedule means no actual |
| 5 | The project manager's remarks with "Mark reviewed" were lost | Kept with the review |
| 6 | The approver saw baseline comparisons recomputed live, not as submitted | Shown as saved once submitted |
| 7 | SPI showed 0.00 (red, "critical") when nothing was planned yet | SPI 1.00 (neutral) when planned progress is 0 |
| 8 | The cost totals upload could overwrite a cost report drafted by WBS head | Refused for that month |
| 9 | Reporting status took the latest revision's date (a report released on time and revised later showed "late"), and never showed "Returned" | First release decides on time; a returned draft shows Returned |
| 10 | No active project at all kept the executive report held forever; outstanding project names showed outside the viewer's access | Not held when nothing is required; names only within access |
| 11 | Carry-over figures (manpower, dates) could come from a later or draft report, or another period type | The last released report of the same period type, not later |
| 12 | A frozen report named a newer schedule in its schedule box | Names the schedule it was compared with |
| 13 | E&P "stale" was measured against today; its plan used the "Measure against" selector | Against the period end; the original baseline |
| 14 | Portfolio progress counted a project without a figure as 0 | Weighted only over projects with the figure |
| 15 | External amounts used the original contract value | Client-approved revised contract value |
| 16 | The same XER could not be loaded once with client and once with internal weightage | Allowed |
| 17 | An Excel month cell stored as a date was refused | Read as its month |

## BOQ Engine

| # | Finding | Fix |
|---|---|---|
| 1 | **A released estimate's Excel and line detail showed the live calculation inputs and working, not the ones it was released with** | Each revision keeps its own copy of every calculation (inputs, sources, dimensions, working); Excel and the line detail use it |
| 2 | **Approval did not check that the lines still matched the calculations**: a superseded drawing between generation and approval went through | Submit, review, approval and release all check again, including each line's status |
| 3 | Live mode: the previous released revision was never superseded on the server | Superseded in the app and on the server, in the same transaction as the release |
| 4 | Live mode: a dimension correction by a project engineer could be lost, because the recalculated calculations were sent first and refused | Changes are sent sources first. The server accepts recalculations from the people whose change caused them |
| 5 | Rejecting a dimension kept the quantity taken from it | Dependent calculations are recalculated and show the error |
| 6 | A withdrawn assumption still counted as approved | An error until replaced |
| 7 | Recalculating or removing a calculation did not reach the calculations using its output | They are recalculated |
| 8 | A reviewer could register an IFC drawing and have it count at once, confirmed by themselves | Confirmed only through Confirm, by someone who neither registered it nor set the status |
| 9 | A text input (concrete grade) could be sourced from a dimension and show "grade null" | Not allowed; an empty value is missing, never silent |
| 10 | "1,5" was read as 15; "1,500 mm" typed in Correct became 1.5 mm | One number reader: a comma only between thousands, otherwise refused |
| 11 | A percentage input in a super-admin template multiplied by 50 instead of 0.5 | Divided by 100 |
| 12 | A calculation taken from another carried its wastage into the next one | Uses the net quantity |
| 13 | Trench: the sand was measured with the ducts inside it, and the ducts were deducted again from the backfill | Sand = sand zone less ducts; backfill = excavation less the sand zone |
| 14 | An item code was kept when a line changed category (backfill material) | Kept only within the same category |
| 15 | Quantities could be verified on a revision that is not the estimation basis; re-linking took the first of two identical texts | Not verified until on the basis; re-linking needs a single match |
| 16 | "Read again" deleted proposals that calculations used, and any viewer could trigger it | Unused proposals are marked replaced, never deleted; only project engineers re-read |
| 17 | A reading interrupted by closing the page stayed "Processing" forever | Marked failed with a reason, so it can be retried |
| 18 | Renaming a dimension through Correct verified it | A rename is a rename |
| 19 | A category in a non-base unit (km, l) showed base-unit numbers | Converted to the category's unit |
| 20 | Wastage % and source list not refreshed on recalculation | Refreshed |
| 21 | The author of a calculation could verify it | Someone else verifies; the sample data now has the Head of PCC verify |
| 22 | Confirming a drawing status left lines "provisional" | Refreshed |
| 23 | Disposal after reuse ignored the compaction factor | Uses the reused volume with its factor |
| 24 | A calculation could use its own result through others | Refused |
| 25 | A person who generated an earlier draft could still approve the revision | Everyone who prepared any draft is excluded |

**Sample data changes:** the substation trench now shows sand 56.863 m³ and selected backfill 298.8 m³ (the ducts sit in the sand). The revision comparison shows the backfill change as +21.60 m³.

## Cost and commercial (cost report, logs, invoices, cash in and out, delays, materials, POs)

| # | Finding | Fix |
|---|---|---|
| 1 | **A cancelled or foreign-currency PO made a whole cost head count as covered**, silently dropping its remaining cost from the cash-out forecast | Only live SAR POs cover a head |
| 2 | **"Not approved" or "Pending approval" counted as client approved** in the change order log, so it entered the client revised value and the margin | Negated statuses are not approved or submitted |
| 3 | **"Invoiceable" was in raw price units on the invoice register, executive report and cost report**, but on the client contract on the cash pages | One figure everywhere: client contract, with the advance |
| 4 | A cost report's budget (D) was never checked against Rev-0 plus approved supplements | Shown as a warning on the cost report. The sample August reports trigger it, because their budgets leave out that month's supplements |
| 5 | Submitted invoices counted a blank row as 0 when another row had a submitted amount | Row by row |
| 6 | **Delay register upload could save half a file**, renumber events wrongly, and (live) send rows the user was told were refused | All or nothing; explicit numbers first; only accepted rows sent |
| 7 | Saving or approving payment terms hid a PO value change made without a revision | The warning stays until a revision is recorded |
| 8 | Correcting a material's PO number, or unticking Monitored, orphaned its payment terms (including paid milestones) | Terms move with a corrected number; monitoring no longer matters for cash-out |
| 9 | Removing a subcontract PO or rate had no rights check or guard; a first rate dated next month re-priced earlier reports | Rights and a guard for approved or paid milestones; no rate before the first rate |
| 10 | The cost report's billing pre-fill used today's figures, not the month end | At the month end |
| 11 | "Other cash-out lines" could repeat a cost report head | Confirmation now covers both POs and cost report heads |
| 12 | A delay upload with no status column re-opened closed events | An event keeps its status |
| 13 | The Finance import classified rows when read, not when committed | Classified again at commit |
| 14 | A new material PO value kept percentage milestones approved | Sent back for approval |
| 15 | "Next 12 months" summed 13 months | 12 |
| 16 | Overdue money was shown after money not yet due | In the current month |
| 17 | Exported cost report showed a negative margin when there was no contract value | Blank |
| 18 | A new WBS head lost its entered previous version | Kept |
| 19 | The change order log update and upload did not check project access; a log month could be in the future | Checked; future months refused |
| 20 | Head treatments only for the standard heads | Any head of the latest cost report |
| 21 | Stray closing tags in the change order log tab | Removed |

## Server updates v24–v33 (none has been run on a database yet; corrected in place)

| # | Finding | Fix |
|---|---|---|
| 1 | **v30 `pt_phase_tbl` would fail on every internal report save** (a variable named like a column) | Renamed |
| 2 | v27/v28: payment-term approval could be sent by the client; empty percentages passed | Approval only from the stored milestone; empty values refused |
| 3 | v32: author and preparer checks read the incoming row; a status could be set to IFC and confirmed in one save | Read from the stored row; confirmation only by someone else |
| 4 | v32: releasing left two released revisions; rate rules differed from the app | Supersede in the same transaction; rate rules as the app |
| 5 | v27/v28: approval totals had no 0.01 tolerance or cancelled-PO case; open milestones without a payment date passed | As the app |
| 6 | v24 rollback would break reading delay files kept by the v26 rollback | Kept the function they need |
| 7 | v27: every new Finance period was logged as "restated" | Logged only when restated |
| 8 | Missing-array, null-kind, scenario-number, inactive-recipient and inactive-admin checks | Fixed |
| 9 | v24: a new event's audit was empty; generated numbers could clash | Full audit; explicit numbers first |
| 10 | v33 "stale" differed from the app | As the app |

## Left as they are, with the reason

- **Executive report margin:** it uses the contract frozen with the planning release and the EAC of the cost release. The two match unless the change order log changes between the two approvals.
- **Cost report percentage of completion:** in an uploaded file, a value of exactly 1 is read as 100%. The file does not say whether the cell is formatted as a percentage.
- **Server number pattern for delay values:** it refuses forms such as ".5" or "1e3" that the app accepts. They are stored as text instead; this is harmless.
- **Server progress by phase for older schedules:** for schedules uploaded before v30, the server reads their stored seven-phase summary. The app recomputes eight phases from the rows. Only the empty Energization row differs.
- **Deleting a project with append-only history:** the server refuses it. The app never deletes projects.
- **Re-running v27 after v28:** re-running v27 replaces v28's wrapper. Run the updates in order once.
- **Sample cost reports:** the August reports leave out that month's approved supplements, so the new budget check flags them. This is the demo data, not the code.
- **Excel styling of the budget warning:** none.
