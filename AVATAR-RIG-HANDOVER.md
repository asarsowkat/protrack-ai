# RASA avatar: the handover for Phase 2 (a rigged avatar) and Phase 3 (Azure Speech and an enterprise AI)

Phase 1, in v3.33, animates the approved RASA badge with live layers drawn over the single image. This note is for:
- the artist and rigger who make Phase 2;
- the IT, Cybersecurity and ProTrack server teams who approve and connect Phase 3.

## The rule for every phase

The approved design does not change:
- the face, the helmet, the Alfanar Projects logo, the ProTrack branding;
- the RASA logo and its text, the colours, the circular badge.

A rig only lets parts of it move. **Acceptance test:** at rest (eyes open, mouth closed, head straight), the rigged avatar is the approved image, pixel for pixel. Compare a capture with the approved badge at the same size; a difference outside anti-aliasing fails.

## Phase 2: the layered PSD

The rigger needs the same artwork, separated into layers. Repaint only what is hidden today: the eye whites under the lids, the inside of the mouth, the neck under the chin.

| Group | Layers (one per line) | Notes |
|---|---|---|
| Background | badge ring and rim; the sky, cranes and city; the left icon column (Planning, Cost Control, Progress Monitoring, Reporting & Analytics, Support); the R logo; RASA and its text; *Powered by Planning Department*; the arc text | Never move. One flattened layer is fine. |
| Body | vest (with RASA and its five lines), shirt, collar, the tablet and the hand holding it, the arm | Moves only with breathing. |
| Head | face (skin), nose, ears, neck | Turns ±10° left-right, ±6° up-down. |
| Helmet | shell, Alfanar Projects logo, ProTrack word, light strips | On the head. The logo moves with the helmet and is never redrawn. |
| Headset | left ear-cup with "AI", right ear-cup, band | The "AI" ring is its own layer, so it can glow. |
| Brows | left, right | Small raise for insight and listening. |
| Eyes (each) | white, iris, pupil, highlight, upper lid, upper lashes, lower lid, lower lashes | The iris moves inside the white (eye tracking); the lids close over it. |
| Mouth | upper lip, lower lip, inside (dark), upper teeth, tongue | Shapes: closed, A, E, I, O, U, F/V, M/B/P. |

**Parameters RASA drives every frame** (the Cubism standard IDs, in `RASA_LIVE2D_PARAMS`):

| RASA pose | Live2D parameter | Range |
|---|---|---|
| Blink | `ParamEyeLOpen`, `ParamEyeROpen` | 1 open, 0 closed |
| Mouth open | `ParamMouthOpenY` | 0 to 1 |
| Mouth wide minus round | `ParamMouthForm` | −1 round, +1 wide |
| Head toward the pointer | `ParamAngleX`, `ParamAngleY` | −30 to 30 |
| Body | `ParamBodyAngleX` | −10 to 10 |
| Eyes toward the pointer | `ParamEyeBallX`, `ParamEyeBallY` | −1 to 1 |
| Breathing | `ParamBreath` | 0 to 1 |

**What the rig team writes:** a thin wrapper over the Cubism SDK for Web model, with three calls:
- `mount(el)` puts the canvas in the avatar's place;
- `setParam(id, value)` sets one parameter;
- `update()` draws a frame.

Then one line switches RASA to the rig:

```js
RASA.adapters.avatar = rasaLive2DRenderer(myCubismWrapper);   // before the panel first opens
```

**After that:**
- RASA mounts the rig instead of the badge and keeps driving it;
- the states (listening, thinking, speaking, warning, success) also reach the wrapper's optional `motion(state)`, for authored motions such as a nod or a wave;
- the Cubism SDK for Web needs Live2D's licence for commercial use; the ProTrack team adds it as a library only with that licence in place.

## Phase 3: switched on in config.js, after approval

Both services are off until IT and Cybersecurity approve them. Spoken answers and questions carry project data.

```js
window.PROTRACK = {
  // … the existing values …
  RASA_ENTERPRISE: {
    speech: { approved: true, enabled: true,
              tokenUrl: 'https://<protrack-server>/api/speech/token',
              sdkUrl:   '<the approved copy of microsoft.cognitiveservices.speech.sdk.bundle-min.js>',
              voice: 'en-GB-RyanNeural', voiceAr: 'ar-SA-HamedNeural' },
    ai:     { approved: true, enabled: true, provider: 'Claude (enterprise)',
              endpoint: 'https://<protrack-server>/api/rasa/ask' }
  }
};
```

**Settings → System** shows each service's state:
- off until IT and Cybersecurity approve it;
- approved but not switched on;
- on.

### What the ProTrack server must do

**`GET /api/speech/token` (Azure Speech)**
- Checks the user's session (the same `Authorization: Bearer` the app sends to the server).
- Exchanges the Speech resource key for a token:
  - `POST https://<region>.api.cognitive.microsoft.com/sts/v1.0/issueToken`
  - header `Ocp-Apim-Subscription-Key`
  - the token lasts 10 minutes.
- Returns `{ "token": "…", "region": "…" }`.
- The key stays on the server, in its secret store.

**What the browser does with the token:**
- it speaks through `SpeechSynthesizer` with the token;
- it times the visemes (`visemeReceived`, `audioOffset`) to the audio start;
- it maps the 22 Azure viseme IDs to RASA's mouth shapes (`RASA_AZURE_VISEMES`).

**`POST /api/rasa/ask` (enterprise AI)**
- The request: `{ question, history, role, lang, projects }`.
- The server checks the session and the user's rights to each project.
- It reads the records the question needs: P6 progress, the ERP cost figures, cost control, cash flow, the invoice register.
- It calls the approved model (Claude, or Azure OpenAI) with only those records. It tells the model to answer from them only, and to say "No evidence in ProTrackAI" when they hold none.
- It returns `{ "answer": "markdown", "sources": [{ "title": "Daily reports, 21 Sep" }, …] }`.
- It logs the question, the user and the records sent.
- The model's key stays on the server.

### Approval checklist (IT and Cybersecurity)

- [ ] **Data residency** of the Azure Speech resource and the model endpoint.
- [ ] **What is sent:** speech gets the answer text; the model gets the question and the selected records only.
- [ ] **Retention:** the provider keeps no data (or the retention is agreed).
- [ ] **Keys:** in the server's secret store only; tokens are short-lived; the browser never holds a key.
- [ ] **The Speech SDK file:** an approved, pinned copy (`sdkUrl`).
- [ ] **Logging and audit** on `/api/rasa/ask`.
- [ ] **Rights:** a user's question reads only their projects, as the screens do.
