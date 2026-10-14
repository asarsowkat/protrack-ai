# ProTrackAI v3.8.3: the full menu on a phone (October 2026)

Built from your request: "In mobile version, full options not available similar to laptop version as it showing older versions without planning, cost control option not available."

## What was wrong
On a laptop, the side menu lists every domain. On a phone (any screen narrower than 900 px), the side menu was hidden and only a bar at the bottom was shown. That bar carried a fixed handful of screens and ran off the edge. So the phone looked like an older version: Planning & Scheduling, Cost Control, Materials & Procurement, Administration and the other newer screens could not be reached. The site itself was up to date.

## What changed
- **Menu button** at the bottom left of the bar. It opens the **same full menu as on a laptop**, over the whole screen: Home, Projects & Handover, Planning & Scheduling, Cost Control, Daily Reports, Materials & Procurement, Claims, Invoices, Reports, RASA, Imports and Administration, with every screen in each.
- **Closing:** picking a screen opens it and closes the menu. ✕ at the top (or Esc) closes it without moving.
- **The bottom bar** now keeps Menu and four shortcuts, so nothing is cut off.
- **Version:** the menu shows the version at the bottom (ProTrackAI v3.8.3), so an old copy in the phone's browser is easy to spot.
- **Rights:** the menu follows Roles and rights exactly as on a laptop. Each person sees only the screens they are allowed.
- **Laptops** are unchanged.

## On your phone
Reload the page once to get v3.8.3:
- **iPhone (Safari):** pull the page down to refresh, or close the tab and open the link again.
- **Android (Chrome):** ⋮ → reload.

Then tap **Menu** at the bottom left.

## Database
No database update.

## Verified
| Check | Result |
|---|---|
| `mobile_menu_demo.py`: on a phone (light and dark) and a tablet, Menu opens every domain, Planning & Scheduling and Material tracking open from it, the menu closes, nothing scrolls sideways; laptop unchanged | 34 of 34, app and sample-data page |
| All earlier demo suites (regression, suites, rights, Material tracking, full screen and the rest), app and sample-data page | same results as v3.8.2 |
