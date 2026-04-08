# Distributing KAutomobileTracker for macOS

This app is built as a **Swift Package** executable. For distribution outside your own machine you should **code sign**, enable **Hardened Runtime**, and **notarize** with Apple.

## Prerequisites

- Paid **Apple Developer Program** membership (for Developer ID signing and notarization).
- **Xcode** 15+ with command line tools.
- App identifier (e.g. `com.kautomobile.KAutomobileTracker`) matching [`Sources/KAutomobileTracker/Resources/Info.plist`](../Sources/KAutomobileTracker/Resources/Info.plist).

## 1. Open the package in Xcode

1. **File → Open** → select [`Package.swift`](../Package.swift).
2. Select the **KAutomobileTracker** executable target.
3. **Signing & Capabilities**
   - Team: your developer team.
   - **Signing Certificate**: “Sign to Run Locally” for dev; **Developer ID Application** for distribution outside the App Store.
4. **Code Sign Entitlements** (Build Settings): set to  
   `Config/KAutomobileTracker.entitlements`  
   (see [KAutomobileTracker.entitlements](../Config/KAutomobileTracker.entitlements) — sandbox, network client, Bluetooth, user-selected read-only files).

5. **Hardened Runtime**: enable in target build settings (`ENABLE_HARDENED_RUNTIME` = YES).

## 2. Archive

1. **Product → Destination → Any Mac (Apple Silicon, Intel)**.
2. **Product → Archive**.
3. In Organizer: **Distribute App** → **Direct Distribution** (or **Developer ID**) → export a `.app` or create a **ZIP** for `notarytool`.

## 3. Notarize

Use [`notarytool`](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) (recommended):

```bash
xcrun notarytool submit KAutomobileTracker.zip \
  --apple-id "you@example.com" \
  --team-id YOUR_TEAM_ID \
  --password "app-specific-password" \
  --wait
```

Then staple the ticket:

```bash
xcrun stapler staple KAutomobileTracker.app
```

Store Apple ID credentials in **Keychain** or CI secrets — never commit passwords.

## 4. CI vs local `swift build`

`swift build` from this repo produces an unsigned binary suitable for **development**. It does **not** apply entitlements or notarization. Release builds for others should come from **Xcode archive** (or a scripted `xcodebuild` pipeline you maintain).

## 5. References

- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [App Sandbox](https://developer.apple.com/documentation/security/app_sandbox)
- [Hardened Runtime](https://developer.apple.com/documentation/security/hardened_runtime)
