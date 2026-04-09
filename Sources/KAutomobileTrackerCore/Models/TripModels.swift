import Foundation

public enum VideoInputKind: String, Codable, Sendable {
    case importedFile
    case bluetoothLinked
    case wifiNiceDVR
    case simulated
    /// Built-in / USB camera live analysis (YOLO + heuristics).
    case liveCamera
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
    /// Selected sign jurisdiction when observed (e.g. \"Vietnam\", \"US\").
    public var signRegion: String?
    /// Catalog group id, e.g. `VN_prohibitive`, `US_regulatory`.
    public var signGroupId: String?
    /// Normalized Vision rect [minX, minY, width, height] in 0...1 (optional).
    public var boundingBox: [Double]?

    public init(
        id: UUID = UUID(),
        text: String,
        timestamp: Date,
        confidence: Float,
        signRegion: String? = nil,
        signGroupId: String? = nil,
        boundingBox: [Double]? = nil
    ) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.confidence = confidence
        self.signRegion = signRegion
        self.signGroupId = signGroupId
        self.boundingBox = boundingBox
    }
}

/// One persisted traffic / road-user detection sample (from YOLO + IoU tracking during analysis).
public struct TrafficObjectObservation: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    /// Display label (e.g. "Car", "Motorcycle").
    public var label: String
    public var category: DetectedObjectCategory
    /// Track id from `OverlayObjectTracker` for the session (not stable across trips).
    public var trackId: Int
    public var timestamp: Date
    public var confidence: Float
    /// Normalized Vision rect [minX, minY, width, height] in 0...1 (optional).
    public var boundingBox: [Double]?
    /// Analysis frame index when this sample was taken.
    public var frameIndex: Int

    public init(
        id: UUID = UUID(),
        label: String,
        category: DetectedObjectCategory,
        trackId: Int,
        timestamp: Date,
        confidence: Float,
        boundingBox: [Double]? = nil,
        frameIndex: Int
    ) {
        self.id = id
        self.label = label
        self.category = category
        self.trackId = trackId
        self.timestamp = timestamp
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.frameIndex = frameIndex
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
    /// Optional path to a re-encoded clip with ADAS overlays (if generated).
    public var processedFilePath: String?
    public var averageMotion: Double
    public var laneHistogram: [String: Int]
    public var signs: [SignObservation]
    /// YOLO vehicle / pedestrian / traffic-light samples over time; nil in older saved trips.
    public var trafficObjects: [TrafficObjectObservation]?
    public var frameSamples: Int

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        isTracked: Bool = false,
        inputKind: VideoInputKind,
        sourceLabel: String,
        filePath: String? = nil,
        processedFilePath: String? = nil,
        averageMotion: Double = 0,
        laneHistogram: [String: Int] = [:],
        signs: [SignObservation] = [],
        trafficObjects: [TrafficObjectObservation]? = nil,
        frameSamples: Int = 0
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.isTracked = isTracked
        self.inputKind = inputKind
        self.sourceLabel = sourceLabel
        self.filePath = filePath
        self.processedFilePath = processedFilePath
        self.averageMotion = averageMotion
        self.laneHistogram = laneHistogram
        self.signs = signs
        self.trafficObjects = trafficObjects
        self.frameSamples = frameSamples
    }
}

/// Wrapped trip list with schema version for forward-compatible persistence.
public struct TripsDocument: Codable, Sendable {
    public var schemaVersion: Int
    public var trips: [TripRecord]

    public init(schemaVersion: Int = TripsSchema.currentVersion, trips: [TripRecord]) {
        self.schemaVersion = schemaVersion
        self.trips = trips
    }
}

public enum TripsSchema {
    public static let currentVersion = 3
}
