# KAutomobileTracker

macOS-only SwiftUI app that helps **record and review driving trips** using footage from a Wi‑Fi dashcam (e.g. [Nice DVR](https://apps.apple.com/app/nice-dvr/id6449487004)–style cameras) or local video files. It estimates **vehicle motion**, rough **lane position over time**, and **road-sign–like text** via Apple **Vision**, optimized for **Apple Silicon** (throttled analysis, Metal-backed image work).

**Repository:** [github.com/kataro92/KAutomobileTracker](https://github.com/kataro92/KAutomobileTracker)

---

## Mission

**Why this project exists**

1. **Connect the *data* to *analysis*** — Pull clips from the same network path phone apps use (camera Wi‑Fi + HTTP), or analyze files you already have, then turn them into **structured trip records** (metrics + detections), not just raw video.
2. **Make trips first-class** — Persist trips, show **tracked** vs incomplete runs, and keep history in one place on the Mac.
3. **Stay efficient on real hardware** — Favor **reduced resolution**, **frame throttling**, and **Metal** `CIContext` so analysis is practical on machines like an **M1 with 16 GB RAM** (not a datacenter GPU).

**What this is *not*** — A full ADAS product, certified lane-keeping, or a replacement for your dashcam vendor app for every setting/live feature. Live RTSP preview is **out of scope** today; the pipeline is **file-based analysis** after download or import.

---

## Features (current)

| Area | Behavior |
|------|----------|
| **Trips** | List, detail view, **Tracked** badge when analysis produced at least one processed frame. |
| **Nice DVR–style Wi‑Fi** | Join camera AP, then HTTP to the camera (often `192.168.1.254`): probe, list clips, download to temp, analyze. |
| **Bluetooth** | Scan/link a BLE peripheral for **metadata association**; HD video does **not** go over BLE. |
| **Analysis** | Motion score, coarse lane bucket (left / center / right / unknown), text recognition filtered for sign-like strings. |
| **Storage** | Trips saved as JSON under `~/Library/Application Support/KAutomobileTracker/trips.json`. |

---

## Requirements

- **macOS 14** (Sonoma) or newer  
- **Swift 5.9+** (ships with recent Xcode or standalone toolchain)  
- **Xcode** recommended to run the SwiftUI app with correct sandbox/Bluetooth behavior, or use `swift build` + `build_app.sh` as below.

---

## Getting started on a new computer

Step-by-step checklist for a second machine: [docs/ONBOARDING.md](docs/ONBOARDING.md).

### 1. Clone

```bash
git clone https://github.com/kataro92/KAutomobileTracker.git
cd KAutomobileTracker
```

### 2. Build (debug, command line)

```bash
swift build
```

Run the binary (path may vary slightly by architecture):

```bash
.build/arm64-apple-macosx/debug/KAutomobileTracker
# or
.build/debug/KAutomobileTracker
```

### 3. Build a `.app` bundle (release)

```bash
chmod +x build_app.sh
./build_app.sh
open KAutomobileTracker.app
```

The script copies `Sources/KAutomobileTracker/Resources/Info.plist` (Bluetooth + local HTTP allowances) into the bundle.

### 4. Open in Xcode (recommended)

1. **File → Open** → select `Package.swift` in the repo root.  
2. Scheme: **KAutomobileTracker**, destination: **My Mac**.  
3. **Run** (⌘R).

---

## Using the app (operator notes)

1. **Wi‑Fi dashcam (like Nice DVR)** — On the Mac, join the **camera’s Wi‑Fi** (same idea as the phone app). In **New tracking session**, use **Test connection** / **Refresh file list**, pick a clip, **Download selected clip**, then **Start & track trip**.  
2. **File on disk** — **Choose video…** and run tracking without Wi‑Fi download.  
3. **Simulation** — Toggle **Simulate trip** to generate a fake trip for UI/testing without hardware.

---

## Project layout

```
KAutomobileTracker/
├── Package.swift                 # SwiftPM manifest
├── build_app.sh                  # Release build + .app packaging
├── Sources/KAutomobileTracker/
│   ├── KAutomobileTrackerApp.swift
│   ├── ContentView.swift
│   ├── Models/TripModels.swift   # Trip, lanes, signs, input kinds
│   ├── Services/
│   │   ├── TripRepository.swift
│   │   ├── VideoAnalysisEngine.swift
│   │   ├── BluetoothDashcamService.swift
│   │   └── NiceDVRWiFiService.swift
│   ├── Views/
│   └── Resources/Info.plist
└── README.md
```

---

## Design notes

- **Lane / signs** — Heuristics + `VNRecognizeTextRequest`; results depend on resolution, exposure, and angle.  
- **Camera APIs** — Novatek-style devices are commonly documented in community threads (e.g. [DashCamTalk Wi‑Fi/API discussion](https://dashcamtalk.com/forum/threads/reverse-engineering-web-api-live-feed-etc.21057/)); real firmware varies—extend `NiceDVRWiFiService` if your camera returns different HTML/CGI.

---

## License

Specify a license in the repository if you intend open-source distribution (this README does not choose one for you).
