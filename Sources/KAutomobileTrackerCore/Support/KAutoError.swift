import Foundation

public enum KAutoError: LocalizedError, Equatable {
    case tripSaveFailed(reason: String)
    case tripLoadCorrupt
    case cameraBadURL
    case cameraDownloadFailed(statusCode: Int)
    case videoNoTrack
    case videoReaderFailed(reason: String)
    case analysisCancelled
    case cameraUnavailable(reason: String)

    public var errorDescription: String? {
        switch self {
        case .tripSaveFailed(let r):
            return "Could not save trips: \(r)"
        case .tripLoadCorrupt:
            return "Trip data file could not be read. A backup may be available next to trips.json."
        case .cameraBadURL:
            return "Invalid camera address."
        case .cameraDownloadFailed(let c):
            return "Download failed (HTTP \(c))."
        case .videoNoTrack:
            return "The file has no video track."
        case .videoReaderFailed(let r):
            return "Could not read video: \(r)"
        case .analysisCancelled:
            return "Analysis was cancelled."
        case .cameraUnavailable(let r):
            return "Camera unavailable: \(r)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .tripLoadCorrupt:
            return "Try restoring trips.backup.json from Application Support, or delete trips.json to start fresh."
        case .cameraBadURL, .cameraDownloadFailed:
            return "Check that you are on the dashcam Wi‑Fi and the gateway IP matches your camera (often 192.168.1.254)."
        case .videoNoTrack, .videoReaderFailed:
            return "Try another clip or re-export the file from the dashcam."
        default:
            return nil
        }
    }
}
