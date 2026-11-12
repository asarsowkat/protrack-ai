# v3.60 setup: the weather on the daily report from a weather service

**On hold until alfanar IT and Cybersecurity approve the weather service.** Until then nothing needs doing: the site team types the weather as before, and Settings → System says the service is waiting for approval.

No database change. **Do not** upload a new `config.js` until Step 3.

## What IT and Cybersecurity check

- **What leaves ProTrack:** for each daily report started, the project's city name, its latitude and longitude (the city centre, not the site), and the report date. No project name, code, people or figures.
- **The service:** for example Azure Maps Weather (inside alfanar's Microsoft tenant) or a commercial weather API.
  - Its terms must allow commercial use.
  - Free plans such as Open-Meteo's are for non-commercial use only.
- **The key:** kept on the ProTrack server, in its secret store. It never reaches the browser.
- **Logging:** the server may log the city and date asked; there is nothing personal in them.

## Step 1: The server endpoint

ProTrack's server answers `GET /api/weather?date=YYYY-MM-DD&city=Riyadh&lat=24.71&lon=46.68`:

1. Check the user's session: the same `Authorization: Bearer` header the app sends to the server.
2. Ask the approved weather service for that place and date.
   - For a past date, use the day's observed (historical) weather.
   - For today, use the current day's forecast.
   - `lat` and `lon` may be missing for a city ProTrackAI does not know; use `city` then.
3. Answer with JSON:

   ```json
   { "condition": "Clear", "tmax": 41.2, "tmin": 29.0, "wind_kmh": 18 }
   ```

   - `condition`, one of these words if it fits: Clear, Hot, Windy, Dust / sandstorm, Cloudy, Rain, Humid.
   - `tmax`, the day's maximum in °C.
   - `wind_kmh`, optional. The field shows "wind N km/h" from 30 km/h.

   The field then reads, for example, "Dust / sandstorm, 43 °C, wind 38 km/h".
4. Answer a non-200 status when there is no weather. The field says so and is typed by hand.

## Step 2: Try it on a staging copy

Point a staging copy's `config.js` at the staging server's endpoint (Step 3). Start a daily report as a foreman: the Weather field fills in and the line under it names the service.

## Step 3: Switch it on

Add this to `config.js`, inside `window.PROTRACK = { … }`:

```js
  WEATHER: {
    provider: 'Azure Maps Weather',          // the name shown under the field and in Settings → System
    approved: true,                          // set only once IT and Cybersecurity have approved it
    enabled: true,
    endpoint: 'https://<your ProTrack server>/api/weather'
  }
```

Settings → System then says "From Azure Maps Weather, through the ProTrack server".

## Cities

ProTrackAI knows the coordinates of the main Saudi cities. For a city it does not know, it sends the name only.
