# ProTrackAI v3.9: a customisable executive report, material tracking for management, and their own pages for invoices and purchase orders (October 2026)

Built from your request: "the Executive Report (released) shall be customized, default option shall be defined by super admin but user can customize their dashboard based on their requirement. Material Tracking to be added in both working data and released executive dashboard. I don't want Subcontract purchase order details & Invoice Register inside baseline window instead I like to have separate window for each."

## Executive report (released): customise it
**Home → Executive report (released) → Summary → Customise this report.**

- Each person can show, hide and reorder the **sections** and the **headline tiles** for themselves. The choice is saved for that person and the report keeps it.
- **Reset to the default** goes back to the layout set by the super admin.
- A super admin has two layouts to choose from in the same panel:
  - **My view**: their own layout, as for anyone else.
  - **Default for everyone**: what everyone sees until they customise their own. People who already customised keep their layout until they reset. **Back to the standard layout** undoes the default. Each change is in the Change log.
- Cost sections and tiles (billing and collection, change order and claim status, cost by project, change orders and claims by project, budget supplements, EAC / VAC, invoiced / collected) still show only in monthly reports and only to people who see cost figures, whatever the layout says.

Sections: Headline tiles, By region, By sector, Critical projects, Billing and collection, Change order and claim status, Progress by project, **Material tracking** (new), Cost by project, Change orders and claims by project, Budget supplements by category.
Headline tiles: Projects released, Progress, SPI, EAC / VAC, Invoiced / collected, Projects needing attention, **Materials delivered** (new).

## Material tracking on both executive pages
| Page | Where the figures come from |
|---|---|
| **Live summary (working data)** | the latest updated schedule, as on the Material tracking page |
| **Executive report (released)** | the material status **saved with each internal report when it is approved**, like the open issues; the report never shows unreleased data |

Both show, for monitored materials only:
- materials tracked, delivered, delivery started, not delivered, delayed, manufacturing in progress, pending FAT and pending shipment
- the same figures by project, with the next delivery date and the schedule's data date
- the delayed materials with their procurement stage, delivery status and supplier

There is also a **Materials delivered** tile ("2 of 10", with how many are delayed and not delivered). The Live summary has it by default. **Customise this view** has a new **Material tracking panel** setting to show or hide the panel. The Project view of both pages shows the project's own materials. Projects without Material tracking say so.

Demo data: the released internal reports of Riyadh-Qassim OHTL and Jubail 380kV carry their material status.

## Their own pages for the invoice register and the purchase orders
| Was | Now |
|---|---|
| Baselines → Invoice register | **Invoices & Cash Flow → Invoice register**: choose the project, see the totals and every invoice in the register, download the template, upload |
| Baselines → Subcontractor purchase orders | **Materials & Procurement → Subcontract purchase orders**: choose the project, add a purchase order, add dated rates |

- The Baselines page keeps the baselines, the internal weightage, the updated schedule and the Master Manpower Costing Sheet.
- Who can open the new pages has not changed. The invoice register is for costing, planning, project managers and super admins. Purchase orders are for costing, project managers and super admins.
- Both pages are new screens in **Settings → Roles and rights → Screens by role**.
- The Import centre's **Invoice register** button opens the new page.

## On the ProTrack server (live.html)
The layouts are kept with the data in each browser, as the Live summary layout already is. On the server, a released report gets its material status only once `release_act` saves it. Until then the Executive report shows "Not in the released report" for those projects. Both need a database update before go-live; neither changes a server figure.
