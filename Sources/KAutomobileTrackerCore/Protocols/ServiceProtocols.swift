import Combine
import Foundation

@MainActor
public protocol TripStoring: AnyObject, ObservableObject {
    var trips: [TripRecord] { get }
    func load()
    func save()
    func add(_ trip: TripRecord)
    func update(_ trip: TripRecord)
    func remove(id: UUID)
}

@MainActor
public protocol VideoAnalyzing: AnyObject, ObservableObject {
    var isRunning: Bool { get }
    var lastMotion: Double { get }
    var lastLane: LaneEstimate { get }
    var recentSigns: [SignObservation] { get }
    var processedFrames: Int { get }
    var status: String { get }

    func resetSessionCounters()
    func cancel()
    func runAnalysis(
        fileURL: URL,
        simulated: Bool,
        pipeline: DetectionPipelineSettings?,
        onProgress: @escaping @Sendable (Int) -> Void,
        onComplete: @escaping @MainActor (Double, [LaneEstimate: Int], [SignObservation], [TrafficObjectObservation], Int) -> Void
    )
}

/// Wi‑Fi dashcam file listing + download (Nice DVR / Novatek-style HTTP).
@MainActor
public protocol DashcamWiFiListing: AnyObject, ObservableObject {
    var cameraHost: String { get set }
    var remoteFiles: [RemoteDashcamFile] { get }
    var statusLine: String { get set }
    var isBusy: Bool { get }

    func baseURL() -> URL?
    func refreshFileList() async
    func probeConnection() async -> Bool
    func downloadToTemporaryFile(_ file: RemoteDashcamFile) async throws -> URL
}

/// Vendor implementations of HTTP Wi‑Fi dashcam listing (extend beyond `NiceDVRWiFiService` when needed).
@MainActor
public protocol DashcamWiFiConnector: DashcamWiFiListing {}
