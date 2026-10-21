# ProTrackAI v3.22.2: which projects the executive report lists (October 2026)

**Executive report (released)** now lists projects by their status (Settings → Projects):

| Project status | Listed in the executive report | Holds the report until released (Reporting status) |
|---|---|---|
| Active | Always: its release for the period, or *Not released for …* | Yes |
| **On hold** | Always, marked **On hold**, with its **last released figures**, labelled *figures of <period>* when they come from an earlier period | **No** |
| **Completed** | **Only in the periods it released**; it drops out afterwards | No |
| **Pre-award** | **Not listed** | No |
| Cancelled | Not listed | No |

**Where the rule applies:**
- the summary: tiles, regions and sectors, critical projects, billing, progress by project
- the project view and its project list

An on-hold project's last released figures count in the summary like any other release.

**On the reporting status:**
- an on-hold project no longer needs to release every period or be exempted; it is left out, like completed and pre-award projects
- a project going back to *Active* is required again from that period

**Checks:** `tests/xr_status_demo.js` (11 checks) changes project statuses and checks:
- the lists for completed, on-hold and pre-award projects
- the last released figures of an on-hold project and their label
- the report opening when the outstanding projects are on hold, and held again when they are active

The reporting status checks (28) still pass.

No server change.
