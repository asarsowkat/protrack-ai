# ProTrackAI v3.61: the new ProTrack logo

The new ProTrack logo (navy "Pro", blue "Track", the globe "o", "PLAN | TRACK | ANALYZE | DELIVER" with orange separators) replaces the old one throughout the application. The artwork is used exactly as supplied, trimmed of its white margin: nothing is recoloured or redrawn.

The logo has no separate icon, so the small square mark is the globe "o" cut from the logo itself, on white. It is used where only a small square fits: the browser tab, the phone top bar and the PDF header.

## Changed

| Where | Before | Now |
|---|---|---|
| **Sign-in page** (the application's opening page), desktop and phone | Old logo in a dark box | New logo in a white box, beside the alfanar Projects logo |
| **Sign-in opening animation** | The compass needle spun in, then the tagline appeared | The globe "o" spins in, then the tagline appears. The globe underneath is hidden while it spins, so there is no double image. At rest it matches the logo exactly. |
| **Side menu** (every page after sign-in: Home, reports, settings…) | Old logo | New logo. In night mode it sits on its own white plate, so the navy "Pro" stays readable on the dark menu. |
| **Phone top bar** | Old "P" mark | The globe mark |
| **Browser tab icon** (favicon) | Old "P" mark | The globe mark |
| **Report documents** (Daily Productivity Report, weekly and monthly reports, previews and downloads) | Old logo in the header | New logo in the header, beside the alfanar Projects logo |
| **Report emails** (approval and report emails) | Lettered "ProTrack" on a dark badge, in the old colours | Lettered "ProTrack" in the new colours (navy "Pro", blue "Track") with "PLAN \| TRACK \| ANALYZE \| DELIVER" and orange separators. Emails carry no images. |
| **PDF exports** with the ProTrack header band | Old "P" mark | The globe mark |
| **User guide** (`guide.html`): header and cover | Old logo; a cover poster built around the old logo | New logo in the header; the new logo on a white card as the cover |
| **Step by step, by role** (`roles.html`) header | Old logo | New logo |
| `demo.html` and `live.html` | Old logo | Same as `index.html` (synced) |

## Not changed

| Where | Why |
|---|---|
| **The alfanar Projects logo** and the company and customer logos set in Settings → Logos and customers | They are not the ProTrack logo. |
| **The RASA badge** (the RASA avatar) | It is the approved RASA artwork, not the ProTrack logo. |
| **Excel and PowerPoint exports** | They never carried the ProTrack logo, only the company and customer logos where set. |
| **Training videos** (`training-videos/*.mp4`, all three voices) | They are recordings of the old screens. They show the new logo only once they are recorded again. |
| **Screenshots in the README** (`dpr_*.png`, `hist_*.png`, `proj_*.png`) | Pictures of the old screens. |
| `share/ProTrackAI-Demo-v3.54.html` in this folder | An old saved copy of the demo. The GitHub `share/` copy is replaced at the next push. |
| **DevPlanning** (`D:\ProTrack\DevPlanning`) | A separate project. Its logo files (`public/protrack-logo.jpg`, the favicon) change only when it is asked for. |

## Checks

- `tests/login_page_demo.js`: 29 of 29 at 1024 px and at 375 px (phone). Check 1 now expects the new logo's size, 1040 × 267.
- Checked in the browser:
  - the sign-in logo at rest, and halfway through its opening;
  - the side menu by day and by night;
  - the phone top bar;
  - both report headers (document and email);
  - a PDF header with the new mark;
  - the guide and the roles page.
- No console errors.
