import AppKit
import KAutomobileTrackerCore
import SwiftUI

/// SwiftUI top-left space; Vision uses bottom-left normalized coordinates.
enum ADASCoordinateConversion {
    static func visionPointToView(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height)
    }

    static func visionRectToView(_ rect: CGRect, in size: CGSize) -> CGRect {
        let x = rect.origin.x * size.width
        let y = (1 - rect.origin.y - rect.height) * size.height
        return CGRect(x: x, y: y, width: rect.width * size.width, height: rect.height * size.height)
    }
}

struct ADASOverlayView: View {
    let overlay: ADASFrameOverlay?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                if let lane = overlay?.laneCorridor {
                    laneFill(lane.corridorQuad, in: size)
                    laneStroke(lane.leftEdge.points, in: size)
                    laneStroke(lane.rightEdge.points, in: size)
                }

                ForEach(overlay?.objects ?? []) { obj in
                    let r = ADASCoordinateConversion.visionRectToView(obj.boundingBox, in: size)
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(color(for: obj), lineWidth: 2)
                        Text(obj.label)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 3))
                            .offset(x: 2, y: 2)
                    }
                    .frame(width: max(r.width, 1), height: max(r.height, 1))
                    .position(x: r.midX, y: r.midY)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func laneFill(_ quad: [CGPoint], in size: CGSize) -> some View {
        Path { path in
            guard quad.count >= 3 else { return }
            let first = ADASCoordinateConversion.visionPointToView(quad[0], in: size)
            path.move(to: first)
            for i in 1..<quad.count {
                path.addLine(to: ADASCoordinateConversion.visionPointToView(quad[i], in: size))
            }
            path.closeSubpath()
        }
        .fill(Color.green.opacity(0.14))
    }

    private func laneStroke(_ points: [CGPoint], in size: CGSize) -> some View {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: ADASCoordinateConversion.visionPointToView(first, in: size))
            for p in points.dropFirst() {
                path.addLine(to: ADASCoordinateConversion.visionPointToView(p, in: size))
            }
        }
        .stroke(Color.green.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    private func color(for obj: DetectedObjectOverlay) -> Color {
        switch obj.category {
        case .pedestrian: return .orange
        case .vehicle: return .blue
        case .trafficSign, .signCandidate: return .yellow
        case .trafficLight: return .red
        case .text: return .cyan
        case .genericRectangle: return .purple
        case .unknown: return .gray
        }
    }
}

/// Frozen snapshot for trip detail (not tied to `VideoAnalysisEngine` state).
struct StaticADASFramePreview: View {
    let cgImage: CGImage
    let overlay: ADASFrameOverlay

    var body: some View {
        ZStack {
            Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
                .resizable()
                .aspectRatio(contentMode: .fit)
            ADASOverlayView(overlay: overlay)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Last analyzed frame thumbnail + ADAS vectors (file analysis and live ingest).
struct AnalysisVisualizationFrame: View {
    @ObservedObject var analysis: VideoAnalysisEngine

    var body: some View {
        ZStack {
            if let cg = analysis.lastVisualizationCGImage {
                Image(nsImage: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.35))
                if analysis.lastADASOverlay == nil {
                    Text("Waiting for frame…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ADASOverlayView(overlay: analysis.lastADASOverlay)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
