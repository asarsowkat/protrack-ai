# ProTrackAI v3.62: the logo across the menu, the sign-in page with the ProTrack logo alone

## The menu logo across the full width

The ProTrack logo at the top of the side menu (every page after sign-in) now runs across the menu's full width:
- **Desktop:** 239 px wide in the 252 px menu, about 6 px from each edge. It was 186 px.
- **Phone menu:** it keeps its 186 px, so the close button beside it stays clear.

## The sign-in page: no alfanar Projects logo

The sign-in page's header shows the ProTrack logo alone. The alfanar Projects logo and the divider beside it are removed.

The alfanar Projects logo stays in the report documents' header (Daily Productivity Report, weekly and monthly reports), which this change does not touch.

## Checks

- `tests/login_page_demo.js`: 29 of 29 at 1280 px and at 375 px (phone). Check 2 now expects the ProTrack logo alone, with no alfanar Projects logo or divider.
- Menu logo measured in the browser on desktop and phone.
