import CoreGraphics
import Foundation

/// Simple IoU-based association for stable track ids (not a Kalman / deep tracker).
final class OverlayObjectTracker {
    struct Pending: Sendable {
        var box: CGRect
        var category: DetectedObjectCategory
        var label: String
        var confidence: Float
    }

    private struct Track {
        var id: Int
        var box: CGRect
        var category: DetectedObjectCategory
        var label: String
        var confidence: Float
        var missed: Int
    }

    private var tracks: [Track] = []
    private var nextId = 1
    private let iouThreshold: CGFloat = 0.25
    private let maxMissed = 4

    func reset() {
        tracks.removeAll()
        nextId = 1
    }

    /// Single-stage IoU matching (all `pending` treated as high-confidence).
    func update(with pending: [Pending]) -> [DetectedObjectOverlay] {
        update(high: pending, low: [])
    }

    /// ByteTrack-style lite: match `high` first, then allow `low` to re-anchor **existing** unmatched tracks only (no new tracks from `low`).
    func update(high pendingHigh: [Pending], low pendingLow: [Pending]) -> [DetectedObjectOverlay] {
        var usedTrack = Set<Int>()
        var usedDetHigh = Set<Int>()
        var matchesHigh: [(Int, Int)] = []

        for (di, p) in pendingHigh.enumerated() {
            var bestT: Int?
            var bestIoU: CGFloat = 0
            for (ti, t) in tracks.enumerated() where !usedTrack.contains(ti) {
                if t.category != p.category { continue }
                let iou = intersectionOverUnion(p.box, t.box)
                if iou >= iouThreshold, iou > bestIoU {
                    bestIoU = iou
                    bestT = ti
                }
            }
            if let ti = bestT {
                matchesHigh.append((ti, di))
                usedTrack.insert(ti)
                usedDetHigh.insert(di)
            }
        }

        var matchesLow: [(Int, Int)] = []
        if !pendingLow.isEmpty {
            let lowOrder = pendingLow.indices.sorted { pendingLow[$0].confidence > pendingLow[$1].confidence }
            for di in lowOrder {
                let p = pendingLow[di]
                var bestT: Int?
                var bestIoU: CGFloat = 0
                for (ti, t) in tracks.enumerated() where !usedTrack.contains(ti) {
                    if t.category != p.category { continue }
                    let iou = intersectionOverUnion(p.box, t.box)
                    if iou >= iouThreshold, iou > bestIoU {
                        bestIoU = iou
                        bestT = ti
                    }
                }
                if let ti = bestT {
                    matchesLow.append((ti, di))
                    usedTrack.insert(ti)
                }
            }
        }

        for (ti, di) in matchesHigh {
            let p = pendingHigh[di]
            tracks[ti].box = p.box
            tracks[ti].label = p.label
            tracks[ti].confidence = p.confidence
            tracks[ti].missed = 0
        }
        for (ti, di) in matchesLow {
            let p = pendingLow[di]
            tracks[ti].box = p.box
            tracks[ti].label = p.label
            tracks[ti].confidence = p.confidence
            tracks[ti].missed = 0
        }

        for (ti, _) in tracks.enumerated() {
            if usedTrack.contains(ti) { continue }
            tracks[ti].missed += 1
        }
        tracks.removeAll { $0.missed > maxMissed }

        for (di, p) in pendingHigh.enumerated() where !usedDetHigh.contains(di) {
            tracks.append(
                Track(
                    id: nextId,
                    box: p.box,
                    category: p.category,
                    label: p.label,
                    confidence: p.confidence,
                    missed: 0
                )
            )
            nextId += 1
        }

        return tracks.map {
            DetectedObjectOverlay(
                trackId: $0.id,
                category: $0.category,
                label: $0.label,
                boundingBox: $0.box,
                confidence: $0.confidence
            )
        }
    }
}

private func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> CGFloat {
    let inter = a.intersection(b)
    if inter.isNull || inter.isEmpty { return 0 }
    let interArea = inter.width * inter.height
    let union = a.width * a.height + b.width * b.height - interArea
    guard union > 0 else { return 0 }
    return interArea / union
}
