# KAutomobileTracker

macOS-only SwiftUI app that helps **record and review driving trips** using footage from a Wi‑Fi dashcam (e.g. [Nice DVR](https://apps.apple.com/app/nice-dvr/id6449487004)–style cameras) or local video files. It estimates **vehicle motion**, rough **lane position over time**, and **road-sign–like text** via Apple **Vision**, optimized for **Apple Silicon** (throttled analysis, Metal-backed image work).

**Repository:** [github.com/kataro92/KAutomobileTracker](https://github.com/kataro92/KAutomobileTracker)  
**License:** [Apache License 2.0](LICENSE) ([SPDX](https://spdx.org/licenses/Apache-2.0): `Apache-2.0`)

![CI](https://github.com/kataro92/KAutomobileTracker/actions/workflows/ci.yml/badge.svg?branch=main)

---

## Mission

**Why this project exists**

1. **Connect the *data* to *analysis*** — Pull clips from the same network path phone apps use (camera Wi‑Fi + HTTP), or analyze files you already have, then turn them into **structured trip records** (metrics + detections), not just raw video.
2. **Make trips first-class** — Persist trips, show **tracked** vs incomplete runs, and keep history in one place on the Mac.
3. **Stay efficient on real hardware** — Favor **reduced resolution**, **frame throttling**, and **Metal** `CIContext` so analysis is practical on machines like an **M1 with 16 GB RAM** (not a datacenter GPU).

**What this is *not*** — A full ADAS product, certified lane-keeping, or a replacement for your dashcam vendor app for every setting/live feature. Live RTSP preview is **out of scope** today; the pipeline is **file-based analysis** after download or import. See [docs/RTSP_RESEARCH.md](docs/RTSP_RESEARCH.md) for notes.

---

## Features (current)

| Area | Behavior |
|------|----------|
| **Trips** | List, detail view, **Tracked** badge when analysis produced at least one processed frame. |
| **Nice DVR–style Wi‑Fi** | Join camera AP, then HTTP to the camera (often `192.168.1.254`): probe, list clips, download to temp, analyze. |
| **Bluetooth** | Scan/link a BLE peripheral for **metadata association**; HD video does **not** go over BLE. |
| **Analysis** | Motion score, coarse lane bucket (left / center / right / unknown), text recognition filtered for sign-like strings. Configurable sample interval in **Settings** (⌘,). |
| **Storage** | Versioned JSON document (`schemaVersion`) under `~/Library/Application Support/KAutomobileTracker/trips.json`, with `trips.backup.json` on each save. |
| **Logging** | `Logger` (`OSLog`) categories: analysis, network, persistence, bluetooth. |

---

## Requirements

- **macOS 14** (Sonoma) or newer  
- **Swift 5.9+**  
- **Xcode** recommended for sandbox + entitlements; see [docs/XCODE_SIGNING.md](docs/XCODE_SIGNING.md).

---

## Run everything on macOS

Use this flow on any **Apple Silicon or Intel** Mac with **macOS 14+** and a working Swift toolchain (**Xcode** from the App Store, or **Xcode Command Line Tools**: `xcode-select --install`).

Short checklist and context: [docs/ONBOARDING.md](docs/ONBOARDING.md). **Contributing / PRs:** [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

### After changing code (mandatory)

When you finish a set of edits—or before you commit or open a PR—**always run a full compile** and **resolve every error** until it succeeds:

```bash
swift build
```

Then run tests (recommended):

```bash
swift test
```

Do not treat the work as done while `swift build` fails. Fix compiler diagnostics in the repo first; only then run the app or ship the change.

### 1. Clone, build, test, and run (terminal)

From a folder where you keep projects:

```bash
git clone https://github.com/kataro92/KAutomobileTracker.git
cd KAutomobileTracker
swift build
swift test
```

Run the debug app (pick the path that exists on your machine after `swift build`):

```bash
swift run KAutomobileTracker
```

```bash
# Typical paths if you prefer to launch the binary directly:
.build/arm64-apple-macosx/debug/KAutomobileTracker
# or, on some setups:
.build/debug/KAutomobileTracker
```

- **Camera / Wi‑Fi / Bluetooth:** the first time you use those features, approve **Camera** and **Bluetooth** when macOS prompts. Sandboxed builds need the entitlements in [Config/KAutomobileTracker.entitlements](Config/KAutomobileTracker.entitlements); see [docs/XCODE_SIGNING.md](docs/XCODE_SIGNING.md).
- **Trip data** is written under `~/Library/Application Support/KAutomobileTracker/` (see Settings for notes).

### 2. YOLO26 CoreML models (optional)

Object detection uses `.mlpackage` bundles if they are present. See [Sources/KAutomobileTracker/Resources/Models/README.md](Sources/KAutomobileTracker/Resources/Models/README.md) for expected names (`YOLO26-General.mlpackage`, optional `YOLO26-Signs.mlpackage`).

**Export on macOS** (Python 3, network for first-time weight download):

```bash
cd KAutomobileTracker/scripts
pip install -r requirements-export.txt
python3 export_yolo26_coreml.py --general
```

That writes `YOLO26-General.mlpackage` next to the script’s default output (under `Sources/KAutomobileTracker/Resources/Models/` if you use the stock paths). You can also copy models into `~/Library/Application Support/KAutomobileTracker/models/`, or use **Settings → YOLO CoreML** to download a zip if you host one.

Then rebuild / run again: `swift build` and `swift run KAutomobileTracker`.

### 3. Local `.app` bundle (unsigned)

A minimal release-style bundle (dev use; not a full notarized app):

```bash
chmod +x build_app.sh
./build_app.sh
open KAutomobileTracker.app
```

For **signed / notarized** distribution, see [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

### 4. Xcode (GUI + signing)

1. **File → Open…** and select the **repo folder** or [Package.swift](Package.swift).  
2. Scheme **KAutomobileTracker** → destination **My Mac**.  
3. Attach [Config/KAutomobileTracker.entitlements](Config/KAutomobileTracker.entitlements) per [docs/XCODE_SIGNING.md](docs/XCODE_SIGNING.md).  
4. Press **Run** (▶).

---

## Architecture

| Module | Role |
|--------|------|
| **KAutomobileTrackerCore** (library) | Models, trip persistence (`TripsDocument` + migration), `VideoAnalysisEngine`, Bluetooth, Nice DVR HTTP client, `DashcamHTMLParser`, `AppLog`, `KAutoError`, `AppUserSettings`, service protocols. |
| **KAutomobileTracker** (executable) | SwiftUI app, `TrackingSessionViewModel`, live/offline tracking views, Settings. |

Extend HTTP dashcams via `DashcamWiFiListing` / `DashcamWiFiConnector` — see [docs/DASHCAM_VENDOR_NOTES.md](docs/DASHCAM_VENDOR_NOTES.md).

---

## Project layout

```
KAutomobileTracker/
├── Package.swift
├── LICENSE                           # Apache-2.0
├── Config/KAutomobileTracker.entitlements
├── build_app.sh
├── .github/workflows/ci.yml
├── Sources/KAutomobileTrackerCore/    # Library & tests dependency
├── Sources/KAutomobileTracker/        # SwiftUI executable
├── Tests/KAutomobileTrackerTests/
└── docs/
```

---

## Design notes

- **Lane / signs** — Heuristics + `VNRecognizeTextRequest`; quality depends on video.  
- **Camera HTTP** — Community reference: [DashCamTalk — Novatek-style Wi‑Fi/API](https://dashcamtalk.com/forum/threads/reverse-engineering-web-api-live-feed-etc.21057/).

---

## License

This project is licensed under the **Apache License, Version 2.0**. See the [`LICENSE`](LICENSE) file for the full text.

- You may use, modify, and distribute this software under the terms of that license.
- **SPDX identifier:** `Apache-2.0`
- **Copyright:** see the notice in [`LICENSE`](LICENSE) (appendix). Contributors who submit changes agree their contributions are licensed under the same terms unless otherwise stated.
