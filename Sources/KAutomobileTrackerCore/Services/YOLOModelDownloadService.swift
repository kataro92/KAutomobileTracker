import Foundation

/// Optional: download a `.zip` that contains `YOLO26-General.mlpackage` (and optional signs) into Application Support.
public actor YOLOModelDownloadService {
    public static let shared = YOLOModelDownloadService()

    public enum DownloadError: Error, LocalizedError {
        case badResponse
        case unzipFailed

        public var errorDescription: String? {
            switch self {
            case .badResponse: return "Invalid download response."
            case .unzipFailed: return "Could not unzip model archive."
            }
        }
    }

    /// Download a zip from `remote` and unzip into Application Support models directory.
    public func downloadAndUnzip(from remote: URL) async throws {
        let (data, response) = try await URLSession.shared.data(from: remote)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw DownloadError.badResponse
        }
        let destDir = try YOLOModelLocator.applicationSupportModelsDirectory()
        let zipURL = destDir.appendingPathComponent("yolo_models_download.zip")
        try data.write(to: zipURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: zipURL) }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-o", "-q", zipURL.path, "-d", destDir.path]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { throw DownloadError.unzipFailed }
    }
}
