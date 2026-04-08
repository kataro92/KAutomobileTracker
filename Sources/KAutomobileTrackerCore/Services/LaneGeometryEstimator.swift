import CoreGraphics
import Foundation

/// Derives a simple “lane corridor” from a single horizontal luma row (same signal as `laneEstimate`).
enum LaneGeometryEstimator {
    /// Returns lane corridor overlay or `nil` if edges are not confident.
    static func corridor(fromLumaRow row: [UInt8]) -> LaneCorridorOverlay? {
        let w = row.count
        guard w > 16 else { return nil }

        var grad = [Int](repeating: 0, count: w - 1)
        for i in 0..<(w - 1) {
            grad[i] = abs(Int(row[i + 1]) - Int(row[i]))
        }
        let third = max(w / 3, 1)
        let leftRegion = 0..<min(third, max(1, w - 2))
        let rightStart = min(2 * third, max(1, w - 2))
        let rightRegion = rightStart..<(w - 1)

        guard let li = argMax(grad, in: leftRegion),
              let ri = argMax(grad, in: rightRegion),
              ri > li + w / 10
        else { return nil }

        let strength = (grad[safe: li] ?? 0) + (grad[safe: ri] ?? 0)
        if strength < w / 2 { return nil }

        let wf = CGFloat(w)
        let lx = CGFloat(li) / wf
        let rx = CGFloat(ri) / wf

        // Converging lines toward a synthetic vanishing band (heuristic, not calibrated).
        let bottomY: CGFloat = 0.02
        let vanishLeft = CGPoint(x: 0.42, y: 0.40)
        let vanishRight = CGPoint(x: 0.58, y: 0.40)

        let leftBottom = CGPoint(x: lx, y: bottomY)
        let rightBottom = CGPoint(x: rx, y: bottomY)

        let leftEdge = NormalizedPolyline(points: [leftBottom, vanishLeft])
        let rightEdge = NormalizedPolyline(points: [rightBottom, vanishRight])

        let quad: [CGPoint] = [leftBottom, vanishLeft, vanishRight, rightBottom]

        return LaneCorridorOverlay(leftEdge: leftEdge, rightEdge: rightEdge, corridorQuad: quad)
    }

    private static func argMax(_ grad: [Int], in range: Range<Int>) -> Int? {
        var best = -1
        var idx: Int?
        for i in range {
            guard i < grad.count else { continue }
            let g = grad[i]
            if g > best {
                best = g
                idx = i
            }
        }
        return idx
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
