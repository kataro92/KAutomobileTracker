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

## 4. Verify it builds

```bash
swift build
```

## 5. Run the app

**Option A — Xcode:** open `Package.swift`, run scheme **KAutomobileTracker**.

**Option B — Script:** `./build_app.sh` then open `KAutomobileTracker.app`.

## 6. Permissions

- **Bluetooth** — macOS may prompt when using scan/link; `Info.plist` includes usage strings.
- **Local HTTP** — `NSAllowsLocalNetworking` is set for camera addresses like `http://192.168.1.254`.

## 7. Where data goes

Trip JSON: `~/Library/Application Support/KAutomobileTracker/trips.json`

## 8. Where to change behavior

| Concern | Start here |
|--------|------------|
| Analysis thresholds / throttling | `VideoAnalysisEngine.swift` |
| Wi‑Fi file discovery / download | `NiceDVRWiFiService.swift` |
| BLE discovery | `BluetoothDashcamService.swift` |
| Trip schema | `TripModels.swift` |
| UI flows | `Views/`, `ContentView.swift` |
