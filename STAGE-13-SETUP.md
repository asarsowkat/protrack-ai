# v3.7 setup: roles, rights and access, controlled by the super admin

This takes about 15 minutes. **Do not** upload a new `config.js`.

## Step 1: Update the database (2 minutes)

1. In Supabase, open **SQL Editor** → **New query** (use an empty tab).
2. Open `schema-update-v16.sql` from this package in Notepad.
3. Select all, copy, paste it into the query tab and press **Run**.
   - The result should be **"Success. No rows returned"**.
4. In a new empty tab, run this check. Copy only the line, without the ``` marks:

   ```sql
   select (select count(*) from pg_proc where proname in ('rights_save','pt_right','people_access','pt_rights')) + (select count(*) from information_schema.tables where table_schema='public' and table_name in ('app_roles','role_rights','user_rights','screen_rights')) as installed;
   ```

   Expect **8**: four functions and four tables.

**What the update does:**
- keeps the rights you set for each role and each person, and which screens each role sees
- keeps your custom roles
- lets any person be given All projects, whole regions or chosen projects
- makes every server check follow those rights
- keeps a history of every change, which cannot be edited

Until you change something, every person keeps exactly the rights they have today. Running it twice is safe.

## Step 2: Publish

Tell Claude "it showed 8". Claude merges the update, and **live.html** shows **v3.7** within about 2 minutes. Then press **Ctrl + F5**.

## Step 3: Look at the new tab (super admin)

**Settings → Roles and rights** has five parts:

| Part | What you do there |
|---|---|
| **Rights by role** | Tick or untick a right for a role. A dot ● marks a setting changed from the default; setting it back to the default removes the dot |
| **Screens by role** | Tick or untick which menu screens each role sees |
| **Custom roles** | Create a role from a built-in one, rename it, switch it off |
| **People with their own exceptions** | The people who have a right given or removed just for them |
| **History** | Every change: who, when, what |

## Step 4: Try it on live.html (10 minutes)

| Who | Does | Expect |
|---|---|---|
| Super admin | **Roles and rights → Custom roles**: name "Planning Section Manager", start from **Planning Engineer** → **Create role** | A new column for the role in both tables |
| Super admin | **Users and access** → open a planning section manager → **Role**: Planning Section Manager → **Save changes** | The users list shows the new role name |
| Super admin | Open a planning engineer → **Access: All projects** → **Save changes** | The users list says "All projects" |
| That planning engineer | Sign in | Every project is in the scope list |
| Super admin | Open a costing engineer → **Rights for this person only** → **Prepare monthly cost reports: Remove** | Listed under "People with their own exceptions" |
| That costing engineer | Sign in | Releases (monthly cost report) is no longer in his menu and nothing can be prepared; the server refuses too |
| Super admin | Set it back to **As the role** | The exception is gone |
| Super admin | **Screens by role**: untick **Cost dashboard** for **Project Manager** | Project managers no longer have it in the menu |
| Super admin | Tick it again | Back to the default (no dot) |

## Rules that never change

- **Super admins** always have every right and every screen. Settings is for super admins only.
- **Foremen** never see cost and billing figures. The server refuses it, whether set for the role or for one person.
- **Hiding a screen** only removes it from the menu. The data stays protected by project access and the rights.
- **Positions** keep their rights whatever the role setting: Head of Planning and Cost Control, costing coordinator and regional report approver. A person's exception can remove them.
- **Lifecycle stages 1 to 5** stay with the Head of Planning and Cost Control.

## If something goes wrong

| What you see | What to do |
|---|---|
| Amber box: "Roles and rights need the v16 database update" | Step 1 has not run. Run `schema-update-v16.sql` |
| "Foremen never see cost and billing figures" | This right cannot be given to foremen |
| "A super admin always has every right" | Super admins cannot be limited |
| "People still have this role. Give them another role first" | Change those people's role in Users and access, then switch the role off |
| "A role called … already exists" | Choose another name |
| "Give this person at least one region, one project or All projects" | Tick a region or project, or choose All projects |

**To undo:** run `schema-rollback-v16.sql`. It goes back to the v3.6 rules. Every role, right, screen setting and history entry is kept, but no longer used. Running `schema-update-v16.sql` again brings them back.
