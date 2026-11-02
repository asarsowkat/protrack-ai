# ProTrackAI v3.52: the app in day and night mode

After v3.51's new sign-in page, the app itself now speaks the same visual language. Day mode is light and airy, like the sign-in card. Night mode is deep navy, taken from the ProTrack logo plate. The moon button in the top bar switches between them, as before. With no choice made, the app follows the device's own setting.

No screen, menu, figure, right or behaviour changes: only colours, surfaces and a few details.

## Day mode

- **Menu:** white, with a thin border. The open screen is marked with a pale-blue tint and blue text; hovering tints a row lightly. The ProTrack logo keeps its dark plate.
- **Page:** pale blue (#F4F8FD), with white cards and tables, fine borders and soft shadows.
- **Top bar:** white, with a small orange mark beside the page title, the one place orange appears, as on the sign-in page.
- **Text:** deep navy (#17284B), and slate blue for secondary text.
- **Actions and selection:** ProTrack blue (#0866D9) for primary buttons, selected chips (such as Summary or Project view), focus rings, links and highlighted table rows.
- **Status colours:** green, amber and red, tuned so each reads clearly on white and on its own pale tag.

## Night mode

- **Menu:** blue-black (#040C1C). The open screen is marked in navy with bright blue text.
- **Page:** blue-black (#071226), with navy cards (#0E1C33).
- **Text:** soft white (#E6EDF7), and grey-blue for secondary text.
- **Actions and selection:** bright ProTrack blue (#4BA3FF). The orange mark is #FFA640.
- **Status colours:** green, amber and red, brightened for the dark ground.

## Details in both modes

- Rounder cards (12 px) with soft, offset shadows. Fields and buttons have 8 px corners.
- Fields show a blue ring when focused, and their border tints on hover.
- Text selection, scrollbars, checkboxes and radio buttons take the theme's colours.
- Drawers dim the page with a navy veil.
- Switching mode is instant: there are no colour fades.

## Contrast

Every text and state colour reaches at least 4.5:1 on its background in both modes:
- body text: 13.7:1 by day, 15.9:1 by night;
- secondary text: 5.2 to 5.8:1 by day, 6.6 to 7.9:1 by night;
- the selected menu row: 5.8:1 by day, 6.6:1 by night.

The day amber was darkened to #8F5300 so its tags pass.

## Not changed

- The sign-in page, which keeps its own always-light design (v3.51).
- The RASA panel and badge.
- Charts, exports, reports and printed layouts.

## Checks

`tests/app_theme_demo.js` (13 checks): paste it into the console of the signed-in demo page. It passed 13/13. It covers:
- the contrast of 16 text and background pairs in each mode;
- the menu and page colours in each mode;
- every one of the 95 screens in the menu, opened in both modes: no light patches by night, no unreadable menu text by day;
- the open screen marked in the menu;
- the orange title mark;
- blue selected chips.

`tests/login_page_demo.js` still passes 29/29.

Also checked in the browser:
- the executive report and the project list at 1600 px, by day and by night;
- the phone layout at 390 px with the menu open and closed, by day and by night;
- no console errors.
