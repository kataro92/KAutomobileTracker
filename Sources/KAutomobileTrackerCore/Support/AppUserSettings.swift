import Foundation

/// User defaults backing optional Settings UI and analysis tuning.
public enum AppUserSettings {
    private static let defaults = UserDefaults.standard
    private static let keyCameraHost = "defaultCameraHost"
    private static let keyMinInterval = "analysisMinIntervalSeconds"
    private static let keySignRegion = "selectedSignRegion"
    private static let keyConfidence = "yoloDetectionConfidence"
    private static let keyYOLOVariant = "yoloModelVariant"
    private static let keyDetectionBackend = "detectionPipelineBackend"
    private static let keyYOLOFamily = "detectionPipelineYOLOFamily"
    private static let keyEnableADASViz = "enableADASVisualization"
    private static let keyModelDownloadURL = "yoloModelDownloadBaseURL"
    private static let keyUseSoftNMS = "yoloUseSoftNMS"
    private static let keyByteTrackLowAssoc = "yoloByteTrackLowConfidenceAssociation"
    private static let keyByteTrackLowFloor = "yoloByteTrackLowConfidenceFloor"
    private static let keyFrameContrastEnhance = "analysisFrameContrastEnhancement"

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

    /// Road-sign jurisdiction (filters fine-tuned `VN_` / `US_` YOLO classes).
    public static var selectedSignRegionEnum: SignRegion {
        get {
            let raw = defaults.string(forKey: keySignRegion) ?? SignRegion.vietnam.rawValue
            return SignRegion(rawValue: raw) ?? .vietnam
        }
        set {
            defaults.set(newValue.rawValue, forKey: keySignRegion)
        }
    }

    /// YOLO confidence threshold (applied to both general and sign heads). Lower values improve recall (more cars) at the cost of false positives.
    public static var detectionConfidenceThreshold: Float {
        get {
            if defaults.object(forKey: keyConfidence) == nil { return 0.25 }
            return Float(defaults.double(forKey: keyConfidence))
        }
        set {
            defaults.set(Double(newValue), forKey: keyConfidence)
        }
    }

    /// Reserved for future multi-variant switching (`n`, `s`, …).
    public static var yoloModelVariant: String {
        get { defaults.string(forKey: keyYOLOVariant) ?? "n" }
        set { defaults.set(newValue, forKey: keyYOLOVariant) }
    }

    /// Default detector for new sessions, reprocess (until changed), and playback overlay when not mid-analysis.
    public static var detectionPipelineSettings: DetectionPipelineSettings {
        get {
            let backendRaw = defaults.string(forKey: keyDetectionBackend) ?? ObjectDetectionBackend.yoloCoreML.rawValue
            let familyRaw = defaults.string(forKey: keyYOLOFamily) ?? YOLOModelFamily.yolo26.rawValue
            let backend = ObjectDetectionBackend(rawValue: backendRaw) ?? .yoloCoreML
            let family = YOLOModelFamily(rawValue: familyRaw) ?? .yolo26
            return DetectionPipelineSettings(backend: backend, yoloFamily: family)
        }
        set {
            defaults.set(newValue.backend.rawValue, forKey: keyDetectionBackend)
            defaults.set(newValue.yoloFamily.rawValue, forKey: keyYOLOFamily)
        }
    }

    /// Draw lane corridor + YOLO boxes over preview / last frame.
    public static var enableADASVisualization: Bool {
        get {
            if defaults.object(forKey: keyEnableADASViz) == nil { return true }
            return defaults.bool(forKey: keyEnableADASViz)
        }
        set { defaults.set(newValue, forKey: keyEnableADASViz) }
    }

    /// Optional HTTPS URL to a `.zip` that expands to `YOLO26-General.mlpackage` in Application Support models folder.
    public static var yoloModelDownloadZipURL: String? {
        get { defaults.string(forKey: keyModelDownloadURL) }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: keyModelDownloadURL)
            } else {
                defaults.removeObject(forKey: keyModelDownloadURL)
            }
        }
    }

    /// Linear Soft-NMS after decoding (helps crowded lanes).
    public static var useSoftNMS: Bool {
        get {
            if defaults.object(forKey: keyUseSoftNMS) == nil { return true }
            return defaults.bool(forKey: keyUseSoftNMS)
        }
        set { defaults.set(newValue, forKey: keyUseSoftNMS) }
    }

    /// Second association pass: low-score boxes can extend existing tracks only (ByteTrack-lite).
    public static var enableByteTrackLowConfidenceAssociation: Bool {
        get {
            if defaults.object(forKey: keyByteTrackLowAssoc) == nil { return true }
            return defaults.bool(forKey: keyByteTrackLowAssoc)
        }
        set { defaults.set(newValue, forKey: keyByteTrackLowAssoc) }
    }

    /// Minimum parse score when low-confidence association is on (must be ≤ `detectionConfidenceThreshold` to add weak boxes).
    public static var byteTrackLowConfidenceFloor: Float {
        get {
            if defaults.object(forKey: keyByteTrackLowFloor) == nil { return 0.12 }
            return Float(defaults.double(forKey: keyByteTrackLowFloor))
        }
        set { defaults.set(Double(newValue), forKey: keyByteTrackLowFloor) }
    }

    /// Core Image contrast / tone lift before YOLO (night / glare spike; extra CPU).
    public static var enableFrameContrastEnhancement: Bool {
        get {
            if defaults.object(forKey: keyFrameContrastEnhance) == nil { return false }
            return defaults.bool(forKey: keyFrameContrastEnhance)
        }
        set { defaults.set(newValue, forKey: keyFrameContrastEnhance) }
    }
}
