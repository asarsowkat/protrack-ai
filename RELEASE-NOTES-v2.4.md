# ProTrackAI v2.4 — release notes (9 Oct 2026)

Phase 1 of the enhancement plan: protect what exists before adding features.

## Changed
- **Demo or live date (T3).** The app no longer always measures at 22 Sept 2026. Settings → System
  switches between demo mode (fixed 22 Sept 2026, for demonstrations) and live mode (today). Each mode
  keeps its own data in the browser (`protrack-demo-v1` / `protrack-live-v1`), so switching loses nothing.
  `DATE_MODE: 'live'` or `'demo'` in config.js locks the choice. Default: demo, so nothing changes
  until you choose.
- **0% payment cap fixed (T5).** A phase cap or retention cap of 0% was read as "no cap". Now 0 means 0,
  a blank phase cap means 100% and a blank retention cap means no cap. A retention percentage with a 0%
  cap is refused with an explanation. Terms saved before v2.4 keep their old meaning, so no historical
  figure moves.
- Settings has a **System** tab with the version and date basis; the sidebar shows both.

## Added
- **Formula reference for Finance (T4):** every formula as coded, proved on a reference project, with
  six decisions for Finance (which reports count, POC method, planned-value curve, fallbacks, ratios with
  no denominator, contract value basis).
- **Tests (T2):** 158 automated checks in `tests/` (regression 77, functional suites 58, formula
  reference 23), all passing; the suites lost earlier are rebuilt and now live with the code.

## Unchanged
Every calculation other than the 0% cap boundary; all screens, reports, roles and data formats.

## Configuration
Optional: add `DATE_MODE: 'live'` to config.js once real data is in use.

## Rollback
Re-upload the v2.3 `index.html`. Data is unaffected; terms saved in v2.4 (marked v:2) are read the
same way by v2.3 except a deliberate 0% cap, which v2.3 reads as no cap.
