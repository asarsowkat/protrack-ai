# ProTrackAI v3.8.5: a customisable executive report, and Material Tracking in the executive views (October 2026)

Built from your request: "i want the Executive Report (released) shall be customized, default option shall be defined by super admin but user can customize their dashboard based on their requirement. Material Tracking to be added in both working data and released executive dashboard".

## 1. Customising the Executive report (released)
**Home → Executive report (released) → Summary → Customise this report.**

| You choose | How |
|---|---|
| Tiles | Tick the ones you want. Two are new: **Materials delayed** and **Materials delivered**. |
| Sections, and their order | Tick a section to show it, untick it to hide it, and use ↑ ↓ to move it. The sections are: By region, By sector, Critical projects, Billing and collection, Change order and claim status, Progress by project, **Material tracking**, Cost by project, Change orders and claims by project, Budget supplements by category. |
| Report shown first | Monthly or Weekly. |

Changes show at once.
- **Save as my layout** keeps the layout for your account. It is saved on the server, so it appears on every device.
- **Reset to the default** takes you back to the default.
- **Other people** keep their own layouts.

### Defaults, set by the super admin
The super admin sees **Default for others** in the same panel. A layout can be saved as the default for:
- **Everyone** (the company default), or
- **one role**, built-in or custom. A role default wins over the company default for people in that role.

**Remove that default** deletes one.

Who sees what:
- **People without their own layout** see the default for their role, or else the company default, or else the standard layout.
- **Someone who has saved their own layout** keeps it until they reset it.
- **The page always says which layout is shown**, for example "Showing the default for Project Manager, set by the super admin".

### The live summary
The **live summary** (working data) works the same way. **Customise this view** changes your own layout, the super admin can save a default for everyone or for a role, and **Reset to default** goes back to it. Your live summary layout is now kept on the server too. Site engineers and site managers keep the layout set in Settings → Role access.

## 2. Material Tracking in both executive views
### Executive report (released)
- **Material tracking** section, one row per project, with a total. The columns are:
  - Monitored
  - Delivered
  - Delivery started
  - Not delivered
  - **Delayed**
  - The delayed materials, each with its current stage and days late
  - The schedule data date
- **Project view** shows the same figures for the chosen project.
- **The figures are those released with each progress report.** Live figures never appear in the released report. **Internal Reporting** has a new **Materials** tab:
  - The release takes a snapshot of Material Tracking when it is saved.
  - The snapshot freezes when the release is submitted.
  - What the approver sees on that tab is what management sees.
- **Releases from before this version** carry no materials and say so. The next release you save carries them.

### Live summary (working data)
- **Material tracking panel**: the live status of the monitored materials for each project in scope, from the latest updated schedule. It has a link to Material tracking and can be hidden in Customise this view.
- **Materials delayed** tile, shown by default.
- **Materials delayed** column for the breakdown table.

## Database
No database update. The layouts are kept in two tables already on the server, with the right access rules:
- **Super admin defaults:** in `role_config`. Everyone can read them; only a super admin can change them.
- **Each person's own layouts:** in `user_prefs`. Each person can read and change only their own.
- **The materials snapshot:** stored in the progress release's figures.

## Verified
| Check | Result |
|---|---|
| `xr_layout_demo.py` covers: <ul><li>your own layout (sections, order, tiles, weekly first)</li><li>the company and role defaults, and reset</li><li>only the super admin sets defaults</li><li>materials in the released report, the project view and the Materials tab</li><li>the snapshot saved with a release</li><li>the live summary panel, tile and default</li></ul> | 31 of 31, on the app and the sample-data page |
| All earlier demo suites (the release now has a Materials tab) | same results as v3.8.4 |
| `e2e_server.py`, the app against the database: <ul><li>defaults saved on the server and read by other people</li><li>own layouts kept per person</li><li>a non-admin refused by the server</li><li>the materials snapshot stored with a progress release</li></ul> | 249 of 249 |
