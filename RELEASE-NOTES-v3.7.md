# ProTrackAI v3.7: roles, rights and access, controlled by the super admin (October 2026)

Built from your request: "enhance the user and access to all users & roles by super admin. super admin should have the control to provide access to all users and all roles."

The super admin now controls four things:
- the screens each role sees
- the access of any person, whatever their role
- the rights of each role
- exceptions for one person

New roles can be made from an existing role. Every check is made on the server.

## What changed

### 1. Settings → Roles and rights (new tab, super admins only)

**Rights by role.** There are 17 rights in four groups. Each role column shows that role's rights today as ticks.

| Group | Rights |
|---|---|
| Daily reports | Prepare daily reports · Review and approve any daily report of the project (as a project manager) |
| Planning | Load baselines, weekly progress, updated schedules and the internal weightage · Prepare internal and client reports · Approve internal and client reports (of projects in access) |
| Cost | Load costing files and invoice registers · See cost and billing figures · Prepare monthly cost reports · Approve monthly cost reports · Upload change order, claim and budget supplement logs |
| Projects | Keep the issue register · Mark issues reviewed · Keep each of the three document rack rows · Register Tender L1 projects · Approve lifecycle stages 6 to 12 (as a project manager) |

- **Changing a right:** tick it to give it to everyone with that role, or untick it to take it away.
- **The dot ●:** marks a setting changed from the default. Setting it back to the default removes the setting.
- **Rights that come with a position** keep working whatever the role's setting. The positions are:
  - Head of Planning and Cost Control
  - costing coordinator
  - regional report approver, set in the Approval matrix

  The table shows the position under each right it applies to. To take a position's right away from one person, use that person's exception.

**Screens by role.** This table sets which of the 21 menu screens each role sees.
- Hiding a screen removes it from the menu. Anyone who opens it directly is sent to an allowed screen.
- Showing a screen gives no right to change anything on it.
- Settings stays with super admins only.

**Custom roles.**
- **Creating one:** give it a name and choose the built-in role to start from (any role except super admin). It starts with that role's current rights and screens and gets its own column in both tables.
- **What its people keep:** every built-in rule of that role, for example a planning engineer's approval route.
- **Changing it:** a custom role can be renamed. It can be switched off once nobody has it.
- **On the sample-data page:** the two planning section managers have a "Planning Section Manager" role made from Planning Engineer. It has no rights changed, so they work exactly as before.

**People with their own exceptions:** lists everyone who has a right given or removed just for them.

**History:** every change of a right, a screen or a role, with who made it and when. The history cannot be edited or deleted, even from the database console.

### 2. Settings → Users and access
- **Role:** the list now includes the custom roles.
- **Access for any role:** choose **Chosen regions and projects** or **All projects**.
  - **Who can be given regions:** every role except super admin and executive manager, who already see everything. Before, only regional managers, portfolio managers and read-only users could be given regions.
  - **New projects:** a region, or All projects, also covers projects added later.
- **Rights for this person only:** each right can be **As the role**, **Allow** or **Remove**.
  - "As the role" shows what the person gets without an exception.
  - The person's choice wins over the role's setting.
  - It is saved as soon as you choose.
- **The users list** shows each person's custom role name and "All projects".

### 3. One rule everywhere

**How a right is decided**, in this order:
1. A super admin always has every right.
2. A foreman never sees cost and billing figures.
3. The person's own exception, if they have one.
4. A position that comes with the right.
5. The role's setting, if the super admin changed it.
6. Otherwise, the role's default rule, which is the v3.6 rule.

**On the server**, every permission check reads the same rights, through `pt_right`. This covers:
- daily reports and their review
- planning and costing uploads
- cost and billing figures (invoices, logs, cost reports, the Contract and Cost rows of the document rack)
- internal, client and cost reports
- the change order and supplement logs
- the issue register
- the document rack
- the Tender register
- lifecycle approval

**In the app**, buttons and menus follow the same rights. Hiding a button is never the protection: the server refuses the action anyway.

> **Nothing changes until you change it.** With no rights changed, every person keeps exactly what they had in v3.6. This was checked person by person:
> - **In the app:** for all 48 people on the sample-data page, the menus, project access and every permission were compared with the v3.6 page, with no difference.
> - **On the server:** for 17 test people, all 89 answers of every permission check were compared before and after the update.

## Database: `schema-update-v16.sql`

**New tables:**

| Table | Holds |
|---|---|
| `app_roles` | custom roles and the role each was made from |
| `role_rights` | the rights changed for a role |
| `user_rights` | each person's exceptions |
| `screen_rights` | the screens changed for a role |
| `rights_audit` | the history (append-only) |

**New columns:** `profiles.custom_role` and `profiles.all_projects`.

**New functions:**

| Function | What it does |
|---|---|
| `pt_right(person, right, position)` | the one rule above |
| `rights_save` | the super admin's changes; refuses anyone else; logs every change |
| `people_access` | each person's custom role and All projects, for the users list |
| `pt_rights`, `pt_screens` | the lists of known rights and screens |

**Updated:**
- **Access:** `user_sees` and `can_see` honour All projects.
- **The permission helpers now read the rights:**
  - `can_plan`, `can_cost`, `can_edit_dpr`, `can_approve`
  - `pt_money_ok`, `pt_issue_editor`, `pt_doc_can`, `pt_can_register`
  - `pt_lc_approver`, `pt_release_preparer`, `pt_release_staff`, `pt_rel_approver`, `pt_sched_keeper`
- **So do these actions:**
  - `dpr_save`, `dpr_act`, `log_import`, `issue_act` (review) and `issue_import`
  - `doc_act` (new boxes)
  - `release_act` (cost report approval)
- **`admin_save_person`:** also saves the custom role and All projects. The custom role must exist, be switched on and be made from the person's role.

Nothing existing is removed, and the update is safe to run twice.

**Rollback:** `schema-rollback-v16.sql` brings back the v3.6 rules. Every table, setting and history entry is kept.

## Validation rules (app and server)

| Rule | Message |
|---|---|
| Only a super admin changes rights, screens and roles | "Only a super admin changes roles, rights and screens" |
| Super admins cannot be limited, by role or by person | "A super admin always has every right" |
| Foremen cannot be given cost and billing figures, by role or by person (even a row written in the database console is ignored) | "Foremen never see cost and billing figures" |
| Unknown rights, roles and screens are refused; Settings cannot be given to other roles | "Unknown right / role / screen" |
| Custom role names are 2 to 60 characters and unique, whatever the capitals | "A role called … already exists" |
| A custom role is made from a built-in role other than super admin | "Choose the role to start from" |
| A role still given to someone cannot be switched off | "People still have this role. Give them another role first" |
| A person's custom role must be switched on and made from their role | "Choose a custom role that is switched on and made from the chosen role" |
| Site engineers, site managers and foremen need at least one region, one project or All projects | "Give this person at least one region, one project or All projects" |

## Verified
| Check | Result |
|---|---|
| `test_v16.py`: the server rules of v16, on PostgreSQL 16 | 114 of 114 |
| Before and after the update: all 89 answers of every permission check, for 17 test people | identical |
| Earlier server suites (v4 to v15), each run with the later updates up to v15 and then up to v16 | no check fails only with v16 |
| Rollback, then the update again | the v3.6 answers come back, then the kept settings apply again |
| `rights_parity.py`: every demo person's menu, project access and app permissions, v3.6 page against v3.7 page | 48 people, 0 differences |
| `rights_demo.py`: the new tab and forms in demo mode (app and sample-data page) | 59 of 59 on each |
| `e2e_server.py`: the app against the database, v16 applied mid-run (rights by role and person, custom role, All projects, hidden screen, server refusals) | 228 of 228 |
| All earlier demo suites (regression, suites, reference, backup, Tender, RASA, releases, issues, quantities, cost, documents, dashboard, schedule, imports, lifecycle) | same results as v3.6 |
| Phone width (390 px): Roles and rights, and the person form | no sideways scrolling of the page |

Not verified: the real Supabase project. The first change you make in Roles and rights on live.html is the real test.

## Known limits
- **Screens are a menu setting.** The data behind a screen stays protected by project access and the rights.
- **Site roles given cost figures:** if a site role is given "See cost and billing figures", cost shows wherever the app checks that right. The executive summary keeps the layout set in **Role access**.
- **Lifecycle stages 1 to 5** stay with the Head of Planning and Cost Control.
- **Project managers and super admins** can always write daily reports on the server, as before. This is why they are not shown as ticks for "Prepare daily reports".
- **Project manager review step:** when it is switched on, it stays with the project managers of the project.
