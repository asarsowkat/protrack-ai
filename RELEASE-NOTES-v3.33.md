# ProTrackAI v3.33: RASA comes alive on the approved badge (October 2026)

RASA is now the approved **RASA badge**: the helmet, the Alfanar Projects and ProTrack branding, the RASA logo and text, the colours and the circular badge, exactly as designed. The badge replaces the earlier pose pictures in the panel and on the round button. Only its size changes (640 × 640, 86 KB), and it is shown as the circle it is.

This is **Phase 1** of three. It works today with the one image there is and the browser's own voice.

## What moves (Phase 1)

| | What you see |
|---|---|
| **Blinking** | The eyelids close and open in about 0.2 s: 70 ms to close, a short hold, 110 ms to open. Blinks come about every 4 seconds, never on a fixed beat, and sometimes twice. RASA blinks less while thinking and a little more while speaking. |
| **Idle** | A slow, slight breathing movement of the badge. |
| **Attention** | With the panel open, the badge turns up to 4° toward the pointer. |
| **Listening** (typing or speaking to RASA) | The "AI" ear-cup ring lights and pulses, a ripple runs round the badge, and the badge leans in slightly. |
| **Thinking** | A light runs round the ring, and the ear-cup ring turns. |
| **Speaking** (🔊 on) | The mouth opens and closes with the words, and the ear-cup and ring glow with the voice. |
| **Insight, warning, done** | The ring glows gold, amber or green, as before. Pointing at a tile, the badge leans toward it. |

**How the mouth follows the voice:** the browser's voice gives no mouth shapes. So RASA times them from the text, about 60 ms a letter:
- closed on m, b and p and at each full stop;
- open on a and o, wide on e and i, round on o, u and w.

The voice's word boundaries keep the timing in step, word by word. Arabic answers move the mouth on every letter.

**Preserving the design:** every live layer is hidden at rest, so the badge shows exactly as approved. The layers are:
- the eyelids, coloured from the skin around the eyes;
- the mouth, on the badge's own smile line;
- the ear-cup light and the ring glow.

They are drawn on top of the image. The image itself is never changed.

**Performance:**
- a single frame loop runs only while something moves, and sleeps when RASA is at rest;
- breathing and glows are CSS;
- the whole avatar adds no library;
- with reduced motion set in the operating system, there is no breathing, turning or ripple, but blinking and the mouth still show.

## Ready for Phase 2: a rigged avatar

When a layered PSD of the badge is ready, rigged in Live2D Cubism, it takes the badge's place. Nothing else changes:
- RASA already computes, every frame, the blink, the mouth shape, the head turn toward the pointer, the eye direction and breathing;
- `rasaLive2DRenderer` passes them to the rig as the Cubism standard parameters (`ParamEyeLOpen`, `ParamMouthOpenY`, `ParamMouthForm`, `ParamAngleX`, `ParamEyeBallX`, `ParamBreath` and the others);
- [AVATAR-RIG-HANDOVER.md](AVATAR-RIG-HANDOVER.md) gives the PSD layers the rig needs, their names, and the acceptance tests.

## Ready for Phase 3: Azure Speech and an enterprise AI, off until approved

Both are written and **switched off**. They need IT and Cybersecurity approval, because spoken answers and questions carry project data. **Settings → System** says so.

- **Azure Speech:** a neural voice (English or Arabic). Its visemes (mouth shapes timed to the audio, IDs 0 to 21) drive the mouth.
  - The browser gets a short-lived token from ProTrack's own server; no key reaches the browser.
  - If the service fails, the browser's own voice reads the answer.
- **Enterprise AI (Claude or Azure OpenAI):** the question goes to ProTrack's own server.
  - The server reads the user's projects with the same rights as the screens.
  - It asks the model and returns the answer with the records it used.
  - RASA labels it *Enterprise AI answer* and lists those records.
- **To switch them on:** add `RASA_ENTERPRISE` to `config.js`, with `approved: true`, `enabled: true` and the server addresses. The handover gives the block and what each server endpoint must do.

## Checks

- **New suite:** `tests/rasa_avatar_demo.js`, 25 checks, all passing. It covers:
  - the badge and the rest pose;
  - blink timing, and the lids sitting on the badge's own eyes;
  - the mouth from the text and in step with the voice;
  - each state, the lean and the attention;
  - Phase 2 with a mock Live2D model;
  - Phase 3 with a mock speech service and a mock enterprise model, including the fall-back to the browser voice;
  - both services off by default.
- **Existing suites:** all 24 pass, 591 checks: the 23 with stored results, and the BOQ sample suite.
- **In the browser:** the browser's own voice spoke an answer; its word boundaries kept the mouth in step, and RASA returned to idle at the end.

No server change.
