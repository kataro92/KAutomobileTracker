import AppKit
import AVFoundation
import KAutomobileTrackerCore
import SwiftUI

private final class CameraPreviewNSView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let pl = previewLayer {
                pl.frame = bounds
                pl.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
                layer?.addSublayer(pl)
            }
        }
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }
}

private struct CameraPreviewRepresentable: NSViewRepresentable {
    var session: AVCaptureSession?
    /// Match analysis buffer coordinates when overlay is enabled (reduces misalignment vs. aspect fill).
    var videoGravity: AVLayerVideoGravity

    func makeNSView(context: Context) -> CameraPreviewNSView {
        CameraPreviewNSView()
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        guard let session else {
            nsView.previewLayer = nil
            return
        }
        if nsView.previewLayer?.session !== session {
            let pl = AVCaptureVideoPreviewLayer(session: session)
            pl.videoGravity = videoGravity
            nsView.previewLayer = pl
        }
        nsView.previewLayer?.videoGravity = videoGravity
    }
}

struct LiveAnalysisView: View {
    @EnvironmentObject private var trips: TripRepository
    @EnvironmentObject private var analysis: VideoAnalysisEngine

    @Binding var isPresented: Bool

    @State private var alertMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Live camera")
                .font(.title2.weight(.semibold))

            Text("Analyzes the default FaceTime or USB camera with throttled YOLO26 CoreML detection (when models are installed), motion, and lane heuristics. Choose sign region in Settings. Not a certified ADAS stack.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary.opacity(0.35))
                CameraPreviewRepresentable(
                    session: analysis.livePreviewSession,
                    videoGravity: AppUserSettings.enableADASVisualization ? .resizeAspect : .resizeAspectFill
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                if AppUserSettings.enableADASVisualization, analysis.livePreviewSession != nil {
                    ADASOverlayView(overlay: analysis.lastADASOverlay)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(minHeight: 220)
            .aspectRatio(16 / 9, contentMode: .fit)
            .accessibilityLabel("Camera preview")

            GroupBox("Live metrics") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Status") {
                        Text(analysis.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Samples") {
                        Text("\(analysis.liveSampleCount)")
                    }
                    LabeledContent("Motion (last)") {
                        Text(String(format: "%.4f", analysis.lastMotion))
                    }
                    LabeledContent("Lane (heuristic)") {
                        Text(analysis.lastLane.rawValue)
                    }
                    if !analysis.recentSigns.isEmpty {
                        Text("Recent signs: \(analysis.recentSigns.map(\.text).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Button("Close") {
                    if analysis.livePreviewSession != nil {
                        analysis.stopLiveCameraAnalysis()
                    }
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if analysis.livePreviewSession == nil {
                    Button("Start camera") {
                        Task {
                            do {
                                try await analysis.startLiveCameraAnalysis()
                            } catch {
                                alertMessage = (error as? LocalizedError)?.errorDescription
                                    ?? error.localizedDescription
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Stop (discard)") {
                        analysis.stopLiveCameraAnalysis()
                    }
                    Button("Stop & save trip") {
                        let ended = Date()
                        analysis.stopLiveCameraAnalysis()
                        if let trip = analysis.consumeLiveTripForRecord(endedAt: ended) {
                            trips.add(trip)
                        }
                        isPresented = false
                    }
                    .keyboardShortcut(.init("s", modifiers: [.command]))
                    .disabled(analysis.liveSampleCount == 0)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 520)
        .alert("Camera", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }
}
