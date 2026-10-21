# ProTrackAI v3.30.1: the budget supplement grid is easy to find (October 2026)

After v3.30 went live, the grid could not be found: **Edit in the grid** showed only once one project was chosen, and the screen opens on *All projects in scope*. No server change.

- With all projects in scope, **Edit in the grid** is now shown too. It says to choose one project and puts the cursor in the **Project** box; once a project is chosen, the button opens that project's grid.
- On an earlier version of a project's log, the screen says that only the latest version is edited.
- The menu item **Cost Control → Budget supplements** now titles the page *Budget supplements* (it said *Change orders and claims* until another click).

## Checks

`tests/supplements_demo.js` has 53 checks; new: the button in the view of every project asks for one project, and the page title.
