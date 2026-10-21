# ProTrackAI v3.24: BOQ Engine, the module (October 2026)

**BOQ Engine** is ProTrackAI's AI-powered quantity take-off, drawing measurement, engineering estimation and estimated BOQ module. This release puts the module in place, as in section 1 of its specification (module name and navigation).

## In the menu

BOQ Engine is a module of its own, right after **Invoices & Cash Flow**, with its own icon: a measuring rule over a drawing sheet. Its menu lists twelve sections:
- **BOQ Engine Dashboard** (live)
- Project & WBS Setup
- Drawing Register
- Drawing Upload & Classification
- Drawing Review & Measurement
- Quantity Calculation Register
- Estimated BOQ
- Specifications & Assumptions
- Revision Comparison
- Review & Approval Workflow
- Reports & Excel Export
- Settings & Audit History

The eleven sections other than the dashboard show as *Planned*, as other planned items in the menu do. They are built as their specifications are confirmed.

## The landing page

The page shows:
- the header: **BOQ Engine**, *AI-Powered Quantity Take-Off, Engineering Estimation & BOQ Generation*;
- the projects in your access, from the ProTrackAI project master;
- a card for each of the twelve sections with its purpose;
- the ProTrackAI modules BOQ Engine will work with: project master data, the WBS of the P6 baseline, Cost Control with its budget protection rules, Materials & Procurement, and Invoices & Cash Flow.

Nothing is estimated or stored in BOQ Engine yet.

## Who sees it

By default, BOQ Engine is open to:
- the super admin, executives, regional and portfolio managers;
- planning and costing engineers;
- project managers.

Site engineers, site managers, foremen and read-only users do not see it. A person whose role cannot see it gets a message if they open its address.

The super admin can show or hide it for any role in **Settings → Role access** (the screen *BOQ Engine*).

## Server

`schema-update-v31.sql`, after v16, adds the screen `boq` to the screens the server accepts, so a role's choice in Role access is kept. Undo: `schema-rollback-v31.sql`.

## Checks

These were checked in the demo page:
- the menu and the default access of each of the eleven roles;
- the refusal message for a foreman who opens the page directly;
- the BOQ Engine row in Settings → Role access;
- the landing page, with no console errors.
