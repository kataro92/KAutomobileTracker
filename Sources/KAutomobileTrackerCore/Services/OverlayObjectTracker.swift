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

    func update(with pending: [Pending]) -> [DetectedObjectOverlay] {
        var usedTrack = Set<Int>()
        var usedDet = Set<Int>()
        var matches: [(Int, Int)] = []

        for (di, p) in pending.enumerated() {
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
                matches.append((ti, di))
                usedTrack.insert(ti)
                usedDet.insert(di)
            }
        }

        for (ti, di) in matches {
            let p = pending[di]
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

        for (di, p) in pending.enumerated() where !usedDet.contains(di) {
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
