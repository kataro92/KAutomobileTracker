import CoreGraphics
import Foundation

// MARK: - Frame overlay (normalized Vision space: origin bottom-left, 0...1)

/// Single polyline in normalized image coordinates (Vision: y up).
public struct NormalizedPolyline: Sendable, Hashable {
    public var points: [CGPoint]

    public init(points: [CGPoint]) {
        self.points = points
    }
}

/// Driveable corridor between two heuristic lane boundaries (not ground-truth lane semantics).
public struct LaneCorridorOverlay: Sendable, Hashable {
    public var leftEdge: NormalizedPolyline
    public var rightEdge: NormalizedPolyline
    /// Quadrilateral for semi-transparent fill (normalized, Vision coords).
    public var corridorQuad: [CGPoint]

    public init(leftEdge: NormalizedPolyline, rightEdge: NormalizedPolyline, corridorQuad: [CGPoint]) {
        self.leftEdge = leftEdge
        self.rightEdge = rightEdge
        self.corridorQuad = corridorQuad
    }
}

public enum DetectedObjectCategory: String, Sendable, Codable, Hashable {
    case pedestrian
    case vehicle
    case trafficSign
    /// Deprecated alias decoded from older overlays if ever persisted.
    case signCandidate
    case trafficLight
    case text
    case genericRectangle
    case unknown
}

/// One detected / tracked region for ADAS-style drawing.
public struct DetectedObjectOverlay: Identifiable, Sendable, Hashable {
    /// Stable id across frames when tracking succeeds (used as `Identifiable.id`).
    public var trackId: Int
    public var category: DetectedObjectCategory
    public var label: String
    /// Normalized Vision bounding box.
    public var boundingBox: CGRect
    public var confidence: Float

    public var id: Int { trackId }

    public init(
        trackId: Int,
        category: DetectedObjectCategory,
        label: String,
        boundingBox: CGRect,
        confidence: Float
    ) {
        self.trackId = trackId
        self.category = category
        self.label = label
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}

/// Everything drawable for one analyzed frame.
public struct ADASFrameOverlay: Sendable, Hashable {
    public var laneCorridor: LaneCorridorOverlay?
    public var objects: [DetectedObjectOverlay]
    public var frameIndex: Int
    public var timestamp: Date

    public init(laneCorridor: LaneCorridorOverlay?, objects: [DetectedObjectOverlay], frameIndex: Int, timestamp: Date) {
        self.laneCorridor = laneCorridor
        self.objects = objects
        self.frameIndex = frameIndex
        self.timestamp = timestamp
    }

    public static let empty = ADASFrameOverlay(laneCorridor: nil, objects: [], frameIndex: 0, timestamp: Date())
}
