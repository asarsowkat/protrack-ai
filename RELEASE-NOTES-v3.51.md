# ProTrackAI v3.51: the new sign-in page

The sign-in page follows the two approved designs, one for desktop and laptop and one for phones. It shows what ProTrack does: automated project processes, RASA the AI project assistant, and project controls from initiation to executive reporting. Signing in works exactly as before.

## What the page shows

- **Brand row:** the original ProTrack logo (PLAN | TRACK | ANALYZE | DELIVER) and, beside it, the alfanar Projects logo slot.
- **Headline:**
  - desktop: "From Initiation to Delivery in One Platform", with "A unified Project Controls solution for Planning, Cost, Cash Flow and Reporting.";
  - phones: "Integrated Project Controls Platform", with "Plan, Track, Control and Deliver Projects with Automation and AI."
- **Four capabilities:** Initiation & Setup, Scheduling & Progress, Costing & EAC, Cash Flow (Cash Flow & Reports on phones). They describe the product and are not links.
- **RASA:** the approved RASA badge, shown whole and round, never cropped, with the speech bubble "RASA, Your AI Project Assistant". The bubble always sits clear of RASA's face and helmet. A light skyline (power plant, crane, transmission tower) is drawn behind in SVG.
- **Sign-in card:** "Sign in to ProTrack", username or email, password with the eye, remember me for 30 days, forgot password, and the Sign in button. The demo page keeps its sample-data note, the demo accounts and the link to the team sign-in. The server page keeps its link to the demo page.
- **Project Controls Workflow:** Initiation & Setup → Baseline (Plan) → Progress Updates (P6 / Excel) → Costing & EAC → Cash Flow (Forecast & Actual) → Reports & Executive Dashboard. There is no tendering stage, because tendering is handled by another platform.

No project figures appear on the page.

## Layouts

| Width | Layout |
|---|---|
| 1280 px and wider | Headline and the four cards on the left, RASA in the middle, the sign-in card on the right, the workflow along the bottom. The content is at most 1440 px wide and centred. |
| 1024 to 1279 px | The same, with RASA beside the headline and the four cards under both. |
| 768 to 1023 px | Headline and RASA on the left, the sign-in card on the right, then the four cards in a row and the workflow. |
| 320 to 767 px | In reading order: logos, headline, RASA, four tiles in a row (two by two below 360 px), the sign-in card, the workflow. |

On phones the workflow scrolls sideways inside its own strip; the page itself never scrolls sideways. On short laptop screens the page scrolls; the card is never cut off and its text is not shrunk.

## Motion

The page opens with a short sequence of about 3 seconds:
1. **the ProTrack logo:**
   - it appears;
   - the compass needle spins one and a quarter turns and settles back to its place with a small swing, like a real compass (0.35 to 2.15 s);
   - then the tagline PLAN | TRACK | ANALYZE | DELIVER fades in (1.75 to 2.65 s), followed by one light sweep;
   - the logo is one flat image, so the needle and the tagline are copies of the same image cut to the compass and to the tagline strip. At rest they match the original exactly, and the logo itself is never redrawn.

   The alfanar Projects logo fades in beside it.
2. the headline rises, with its orange bar;
3. RASA rises with a blue halo, then the bubble appears;
4. the cards appear one after the other;
5. the sign-in card appears;
6. the workflow stages and their arrows appear left to right.

Other behaviour:
- The form can be used at once. Nothing waits for the sequence, and there is no splash to skip.
- The sequence is pure CSS, so the page is complete even if a script fails.
- It plays once per page load, never again after a failed sign-in.
- After that, RASA floats very slowly by 5 px.
- The cards lift slightly on mouse hover. Nothing depends on hover.
- With **reduce motion** set on the device, every animation on the page is switched off and the page appears in its final state.

The Sign in button shows "Signing in…" with a small spinner while it checks. It cannot be pressed twice. After a failed attempt it returns to normal.

## Accessibility

- Visible labels for both fields.
- Error messages linked to their fields and announced by screen readers.
- A visible focus ring.
- The eye button says "Show password" or "Hide password".
- Fields and buttons at least 44 px high.
- Alternative text for the ProTrack logo and RASA.
- The workflow is an ordered list under its own heading.

## Not on the page, on purpose

- **Microsoft 365 sign-in:** ProTrack has no Microsoft 365 integration, so the button is left out rather than shown as if it worked.
- **Language switch:** the sign-in text is English only (the Arabic switch translates the app after sign-in), so no switch is shown.
- **4D BIM and digital twin:** not featured.

## Assets

- **ProTrack logo:** the original image already in the app (`LOGO`, 520 × 131), shown at its own proportions.
- **RASA:** the approved RASA badge already in the app (`RASA_BADGE`, 640 × 640). Its background is part of the image, so it is shown whole inside its round frame.
- **alfanar Projects logo:** the official logo supplied by Planning (PNG, 174 × 79, emblem with the Arabic and English name and PROJECTS), kept in `ALFANAR_LOGO` and shown at its own proportions beside the ProTrack logo. The file has a white background; the page blends that white into its light background (`mix-blend-mode: multiply`), so no white box shows. The image itself is unchanged. To replace it, paste a new data URI into `ALFANAR_LOGO`. If it is ever emptied, a plain labelled slot holds its place.

## Unchanged

- Accounts, passwords and lockouts.
- Remember me.
- Sessions and the 20-minute idle sign-out.
- Password reset.
- Demo accounts.
- Server sign-in through Supabase, with its messages.
- The IDs the tests use (`#authCard`, `#lgId`, `#lgPw`, `#lgBtn`, `#lgIdErr`, `#lgErr`).

No server change, no SQL.

## Checks

`tests/login_page_demo.js` (29 checks): paste it into the console of the signed-out demo page, at each window size. It passed 27/27 at 320, 360, 375, 390, 430, 768, 1024, 1280, 1366, 1440 and 1920 px, and 29/29 at 1440, 1024, 375 and 320 px after the logo opening was added. It covers:
- the logo, the alfanar slot and RASA;
- the four capabilities and the six workflow stages;
- no tendering stage, BIM or Microsoft 365;
- no sideways scrolling, and nothing over the sign-in card;
- the bubble clear of the face and helmet;
- the order on phones and the tap sizes;
- empty-field and wrong-password messages, the busy state, the eye, forgot password, and the demo note and links;
- reduced motion;
- the opening playing once;
- the logo opening: the needle and tagline layers cut from the logo, identical to it at rest.

Also checked by hand in the browser:
- a demo account signs in and the app opens;
- signing out returns to the new page;
- `live.html` shows the server status, no demo accounts and the link to the demo page.
