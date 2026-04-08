# Onboarding: what to do on a fresh machine

Use this checklist when you open **KAutomobileTracker** source on another Mac.

## 1. Understand the goal in one sentence

> Ingest dashcam video (Wi‑Fi download or local file), run lightweight Vision-based analysis on Apple Silicon, and save **trips** marked **tracked** when analysis succeeds.

Read the **Mission** section in the root [README.md](../README.md) for scope and non-goals.

## 2. Install tooling

- Install **Xcode** from the Mac App Store (or Xcode command line tools: `xcode-select --install`).
- Confirm Swift: `swift --version` (5.9+).

## 3. Get the code

```bash
git clone https://github.com/kataro92/KAutomobileTracker.git
cd KAutomobileTracker
```

## 4. Verify it builds and tests pass

```bash
swift build
swift test
```

CI runs the same on `macos-14` (see [.github/workflows/ci.yml](../.github/workflows/ci.yml)).

## 5. Run the app

**Option A — Xcode:** open `Package.swift`, run scheme **KAutomobileTracker**, set entitlements per [XCODE_SIGNING.md](XCODE_SIGNING.md).

**Option B — Script:** `./build_app.sh` then open `KAutomobileTracker.app` (unsigned dev bundle).

## 6. Permissions

- **Bluetooth** — `Info.plist` usage strings; full sandbox + BLE requires the entitlements file in Xcode.
- **Local HTTP** — `NSAllowsLocalNetworking` for `http://192.168.1.254` style cameras.
- **Signing** — [DISTRIBUTION.md](DISTRIBUTION.md) for Developer ID + notarization.

## 7. Where data goes

- `~/Library/Application Support/KAutomobileTracker/trips.json` — versioned `TripsDocument`.
- `trips.backup.json` — previous file snapshot on each successful save.

## 8. Where to change behavior

| Concern | Start here |
|--------|------------|
| Analysis / sampling | [VideoAnalysisEngine.swift](../Sources/KAutomobileTrackerCore/Services/VideoAnalysisEngine.swift), **Settings** (UserDefaults via `AppUserSettings`) |
| Wi‑Fi discovery | [NiceDVRWiFiService.swift](../Sources/KAutomobileTrackerCore/Services/NiceDVRWiFiService.swift), [DashcamHTMLParser.swift](../Sources/KAutomobileTrackerCore/Dashcam/DashcamHTMLParser.swift) |
| BLE | [BluetoothDashcamService.swift](../Sources/KAutomobileTrackerCore/Services/BluetoothDashcamService.swift) |
| Trip schema / persistence | [TripModels.swift](../Sources/KAutomobileTrackerCore/Models/TripModels.swift), [TripRepository.swift](../Sources/KAutomobileTrackerCore/Services/TripRepository.swift) |
| UI | [Views/](../Sources/KAutomobileTracker/Views/), [ContentView.swift](../Sources/KAutomobileTracker/ContentView.swift) |

## 9. Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and the GitHub PR / issue templates.
