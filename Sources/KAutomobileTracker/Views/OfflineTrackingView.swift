import AppKit
import KAutomobileTrackerCore
import SwiftUI
import UniformTypeIdentifiers

/// Local file import or simulated trip (no dashcam connection).
struct OfflineTrackingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var trips: TripRepository
    @EnvironmentObject private var analysis: VideoAnalysisEngine

    @State private var sessionVM = TrackingSessionViewModel()
    @State private var pipelineSettings = AppUserSettings.detectionPipelineSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Offline tracking")
                .font(.title2.weight(.semibold))

            DetectionPipelineControls(settings: $pipelineSettings, persistToUserDefaults: true)

            Text("Import a video from disk or run a simulated trip. No Wi‑Fi or Bluetooth dashcam connection is required.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Simulate trip (no video file)", isOn: Bindable(sessionVM).useSimulation)
                .disabled(analysis.isRunning)
                .accessibilityLabel("Simulate trip without video file")

            if !sessionVM.useSimulation {
                filePickerRow
            }

            if analysis.isRunning {
                ProgressView("Processing…")
                Text("\(analysis.processedFrames) samples analyzed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(analysis.processedFrames) samples analyzed")
            }

            HStack {
                Button("Cancel") {
                    analysis.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel offline tracking")
                Spacer()
                Button("Start & track trip") {
                    startTracking()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(analysis.isRunning || (!sessionVM.useSimulation && sessionVM.pickedURL == nil))
                .accessibilityHint("Runs analysis and saves the trip when complete")
            }
        }
        .padding(24)
    }

    private var filePickerRow: some View {
        HStack {
            Button("Choose video…") {
                pickVideo()
            }
            .disabled(analysis.isRunning)
            .accessibilityLabel("Choose video file")

            if let url = sessionVM.pickedURL {
                Text(url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pickVideo() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        if panel.runModal() == .OK, let url = panel.url {
            sessionVM.pickedURL = url
            sessionVM.lastDownloadWasWiFi = false
        }
    }

    private func startTracking() {
        sessionVM.markNewSession()

        let inputKind: VideoInputKind
        let sourceLabel: String
        if sessionVM.useSimulation {
            inputKind = .simulated
            sourceLabel = "Simulated dashcam (offline)"
        } else if let path = sessionVM.pickedURL?.path {
            inputKind = .importedFile
            sourceLabel = sessionVM.pickedURL?.lastPathComponent ?? path
        } else {
            inputKind = .importedFile
            sourceLabel = "Unknown"
        }

        let filePath = sessionVM.pickedURL?.path
        let url = sessionVM.pickedURL ?? URL(fileURLWithPath: "/dev/null")

        analysis.runAnalysis(
            fileURL: url,
            simulated: sessionVM.useSimulation,
            pipeline: pipelineSettings,
            onProgress: { _ in },
            onComplete: { avg, laneMap, signs, traffic, frames in
                let histogram = Dictionary(uniqueKeysWithValues: laneMap.map { ($0.key.rawValue, $0.value) })
                let tracked = frames > 0
                let trip = TripRecord(
                    startedAt: sessionVM.sessionStartedAt,
                    endedAt: Date(),
                    isTracked: tracked,
                    inputKind: inputKind,
                    sourceLabel: sourceLabel,
                    filePath: sessionVM.useSimulation ? nil : filePath,
                    averageMotion: avg,
                    laneHistogram: histogram,
                    signs: signs,
                    trafficObjects: traffic.isEmpty ? nil : traffic,
                    frameSamples: frames
                )
                trips.add(trip)
                dismiss()
            }
        )
    }
}
