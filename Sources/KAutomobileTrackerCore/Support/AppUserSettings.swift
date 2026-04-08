import Foundation

/// User defaults backing optional Settings UI and analysis tuning.
public enum AppUserSettings {
    private static let defaults = UserDefaults.standard
    private static let keyCameraHost = "defaultCameraHost"
    private static let keyMinInterval = "analysisMinIntervalSeconds"

    public static var defaultCameraHost: String {
        get {
            defaults.string(forKey: keyCameraHost) ?? "192.168.1.254"
        }
        set {
            defaults.set(newValue, forKey: keyCameraHost)
        }
    }

    /// Minimum time between analyzed frames (lower = more CPU/GPU).
    public static var analysisMinInterval: TimeInterval {
        get {
            let v = defaults.double(forKey: keyMinInterval)
            return v > 0.05 ? v : 0.22
        }
        set {
            defaults.set(newValue, forKey: keyMinInterval)
        }
    }
}
