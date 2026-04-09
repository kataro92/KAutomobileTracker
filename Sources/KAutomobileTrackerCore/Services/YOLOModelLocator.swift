import Foundation

/// Resolves CoreML `.mlpackage` URLs for YOLO exports (app bundle + Application Support).
public enum YOLOModelLocator {
    public static let generalName = "YOLO26-General"
    public static let signsName = "YOLO26-Signs"

    public static func generalStem(family: YOLOModelFamily) -> String {
        switch family {
        case .yolo26: return "YOLO26-General"
        case .yoloV8: return "YOLOv8-General"
        case .yoloV11: return "YOLOv11-General"
        }
    }

    public static func signsStem(family: YOLOModelFamily) -> String {
        switch family {
        case .yolo26: return "YOLO26-Signs"
        case .yoloV8: return "YOLOv8-Signs"
        case .yoloV11: return "YOLOv11-Signs"
        }
    }

    /// Models copied or downloaded beside `trips.json`.
    public static func applicationSupportModelsDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("KAutomobileTracker/models", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// First existingURL: Application Support, then app bundle (`Bundle.main` when linked into the app).
    public static func resolvedModelURL(fileNameWithoutExtension: String) -> URL? {
        let ext = "mlpackage"
        if let dir = try? applicationSupportModelsDirectory() {
            let u = dir.appendingPathComponent("\(fileNameWithoutExtension).\(ext)")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        if let u = Bundle.main.url(forResource: fileNameWithoutExtension, withExtension: ext) {
            return u
        }
        return nil
    }

    public static func generalModelURL(family: YOLOModelFamily) -> URL? {
        resolvedModelURL(fileNameWithoutExtension: generalStem(family: family))
    }

    public static func signsModelURL(family: YOLOModelFamily) -> URL? {
        resolvedModelURL(fileNameWithoutExtension: signsStem(family: family))
    }

    /// Legacy stem `YOLO26-General` (for docs and tooling references).
    public static func generalModelURL() -> URL? {
        generalModelURL(family: .yolo26)
    }

    /// Legacy stem `YOLO26-Signs`.
    public static func signsModelURL() -> URL? {
        signsModelURL(family: .yolo26)
    }
}
