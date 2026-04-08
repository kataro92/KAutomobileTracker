import Foundation

public enum VideoInputKind: String, Codable, Sendable {
    case importedFile
    case bluetoothLinked
    case wifiNiceDVR
    case simulated
}

public enum LaneEstimate: String, Codable, CaseIterable, Sendable {
    case left
    case center
    case right
    case unknown
}

public struct SignObservation: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    public var timestamp: Date
    public var confidence: Float

    public init(id: UUID = UUID(), text: String, timestamp: Date, confidence: Float) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.confidence = confidence
    }
}

public struct TripRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var isTracked: Bool
    public var inputKind: VideoInputKind
    public var sourceLabel: String
    public var filePath: String?
    public var averageMotion: Double
    public var laneHistogram: [String: Int]
    public var signs: [SignObservation]
    public var frameSamples: Int

    public init(
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

/// Wrapped trip list with schema version for forward-compatible persistence.
public struct TripsDocument: Codable, Sendable {
    public var schemaVersion: Int
    public var trips: [TripRecord]

    public init(schemaVersion: Int = 1, trips: [TripRecord]) {
        self.schemaVersion = schemaVersion
        self.trips = trips
    }
}

public enum TripsSchema {
    public static let currentVersion = 1
}
