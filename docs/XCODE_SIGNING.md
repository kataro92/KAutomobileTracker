# Attaching entitlements to the SwiftPM app target in Xcode

Because this project is primarily a **Swift Package**, the macOS app target appears when you open [`Package.swift`](../Package.swift) in Xcode.

1. Open **Package.swift** in Xcode.
2. Select the project navigator entry for **KAutomobileTracker** (executable).
3. **Build Settings** → search for **Code Signing Entitlements**.
4. Set the value to:  
   `$(SRCROOT)/Config/KAutomobileTracker.entitlements`  
   or a path relative to the package root that resolves to [Config/KAutomobileTracker.entitlements](../Config/KAutomobileTracker.entitlements).

`Info.plist` keys (Bluetooth, local networking) remain in [Sources/KAutomobileTracker/Resources/Info.plist](../Sources/KAutomobileTracker/Resources/Info.plist); [`build_app.sh`](../build_app.sh) copies that plist into the ad-hoc `.app` bundle for script-based builds.

For **sandboxed** behavior matching the entitlements file, prefer running from **Xcode** or a signed **Archive**, not only `swift run`.
