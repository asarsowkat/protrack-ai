# ProTrackAI v3.60: the weather on the daily report, filled in automatically

Site teams no longer type the weather on the daily report. ProTrackAI fills it in from the project's location.

## How it works

When a foreman or site engineer starts a daily report, the **Weather** field is filled with the weather of the project's city on the report date, for example "Clear, 41 °C". A line under the field says where it came from:

> Filled in for Riyadh on 22 Sept 2026. Change it if the site saw otherwise.

- **The project's city** is the one chosen when the project was created. A project registered from the Tender register uses its location, for example "Dammam".
- **Another date or project** gets its own weather.
- **Typed weather is kept**, also when the date changes. The line says "Entered by hand".
- **A cleared field** is filled in again.
- **A report being edited** keeps the weather it was saved with.
- **When no weather is known** for the city, the line says so and the field is typed as before.

## Where the weather comes from

| Where | Weather |
|---|---|
| Demo page and demo mode | **SAMPLE** weather, built from the city's usual climate for the month. No outside service is called. The line under the field says it is sample weather. |
| Signed in to the ProTrack server | ProTrack's own server, which asks the approved weather service. The browser never calls an outside service and holds no key. |

**On the server it is switched off until IT and Cybersecurity approve the weather service.** Each request carries the project's city and the report date. Until then the site team types the weather as before, and Settings → System says the service is waiting for approval.

`STAGE-51-SETUP.md` covers:
- what the server endpoint must do;
- the points for IT to check;
- how to switch it on in `config.js`.

## Server

No database change. When approved, ProTrack's server needs one endpoint, `GET /api/weather` (STAGE-51-SETUP).

## Checks

- New: `tests/weather_auto_demo.js`, 13 checks.
- Also run and passing: `report_preview_demo.js` (17), which covers the same form and its Weather field.
- Not run: `report_photos_demo.js`. The browser pane was hidden, so the page drew no frames and the suite's photos could not be decoded. That suite does not touch the weather.
