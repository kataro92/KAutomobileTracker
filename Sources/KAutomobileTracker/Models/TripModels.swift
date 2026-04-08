import Foundation

enum VideoInputKind: String, Codable, Sendable {
    case importedFile
    case bluetoothLinked
    /// Video pulled over HTTP after joining the cam Wi‑Fi (Nice DVR / Viidure-style).
    case wifiNiceDVR
    case simulated
}

enum LaneEstimate: String, Codable, CaseIterable, Sendable {
    case left
    case center
    case right
    case unknown
}

struct SignObservation: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var text: String
    var timestamp: Date
    var confidence: Float

    init(id: UUID = UUID(), text: String, timestamp: Date, confidence: Float) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.confidence = confidence
    }
}

struct TripRecord: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    /// True when analysis finished and trip was committed as tracked.
    var isTracked: Bool
    var inputKind: VideoInputKind
    var sourceLabel: String
    var filePath: String?
    var averageMotion: Double
    var laneHistogram: [String: Int]
    var signs: [SignObservation]
    var frameSamples: Int

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        isTracked: Bool = false,
        inputKind: VideoInputKind,
        sourceLabel: String,
        filePath: String? = nil,
        averageMotion: Double = 0,
        laneHistogram: [String: Int] = [:],
        signs: [SignObservation] = [],
        frameSamples: Int = 0
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.isTracked = isTracked
        self.inputKind = inputKind
        self.sourceLabel = sourceLabel
        self.filePath = filePath
        self.averageMotion = averageMotion
        self.laneHistogram = laneHistogram
        self.signs = signs
        self.frameSamples = frameSamples
    }
}
