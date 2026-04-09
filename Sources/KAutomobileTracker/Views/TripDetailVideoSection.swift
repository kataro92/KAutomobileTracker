import AVFoundation
import AVKit
import AppKit
import KAutomobileTrackerCore
import SwiftUI

/// Native AppKit `AVPlayerView` — avoids SwiftUI `VideoPlayer` / `AVPlayerView` bridging crashes on some macOS builds.
private struct MacAVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

/// Plays the source clip for trips that store a `filePath` to an existing file.
struct TripDetailVideoSection: View {
    let trip: TripRecord

    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var overlaySourceURL: URL?
    @StateObject private var playbackOverlay = VideoAnalysisEngine()

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if resolvedVideoURL != nil {
                    Group {
                        if isProcessedPlayback {
                            Text("Showing processed video with ADAS overlays baked in.")
                        } else if AppUserSettings.enableADASVisualization {
                            Text("ADAS lane + detection overlay follows playback (enable or adjust in Settings).")
                        } else {
                            Text("Turn on “Show lane + detection overlay” in Settings to preview ADAS-style overlays during playback.")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if let url = resolvedVideoURL {
                    Group {
                        if let p = player {
                            ZStack {
                                MacAVPlayerView(player: p)
                                if AppUserSettings.enableADASVisualization {
                                    ADASOverlayView(overlay: playbackOverlay.lastADASOverlay)
                                        .allowsHitTesting(false)
                                }
                            }
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 240)
                        }
                    }
                    .frame(minHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Trip source video")
                    .onAppear {
                        if player == nil {
                            setupPlayer(url: url)
                        }
                    }
                } else {
                    Text(unavailableMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
            }
        } label: {
            Label("Source video", systemImage: "play.rectangle.fill")
        }
        .onChange(of: trip.id) { _, _ in
            replacePlayer()
        }
        .onDisappear {
            tearDownPlayer()
        }
    }

    private func replacePlayer() {
        tearDownPlayer()
        if let url = resolvedVideoURL {
            setupPlayer(url: url)
        }
    }

    private func setupPlayer(url: URL) {
        tearDownPlayer()
        overlaySourceURL = url
        playbackOverlay.reloadYOLOModels(for: AppUserSettings.detectionPipelineSettings)
        let p = AVPlayer(url: url)
        p.volume = 0.25
        p.isMuted = false
        player = p
        let interval = CMTime(seconds: 0.12, preferredTimescale: 600)
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { t in
            let secs = CMTimeGetSeconds(t)
            guard secs.isFinite, let u = overlaySourceURL else { return }
            Task { @MainActor in
                await playbackOverlay.updatePlaybackOverlay(fileURL: u, timeSeconds: secs)
            }
        }
    }

    private func tearDownPlayer() {
        if let p = player, let obs = timeObserver {
            p.removeTimeObserver(obs)
        }
        timeObserver = nil
        overlaySourceURL = nil
        player?.pause()
        player = nil
    }

    private var resolvedVideoURL: URL? {
        if let processed = trip.processedFilePath,
           !processed.isEmpty,
           FileManager.default.fileExists(atPath: processed) {
            return URL(fileURLWithPath: processed)
        }
        guard let path = trip.filePath, !path.isEmpty else { return nil }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private var isProcessedPlayback: Bool {
        guard let url = resolvedVideoURL, let processed = trip.processedFilePath else { return false }
        return url.path == processed
    }

    private var unavailableMessage: String {
        if trip.filePath == nil || trip.filePath?.isEmpty == true {
            switch trip.inputKind {
            case .liveCamera:
                return "No video file is stored for live camera trips—only metrics and detections are saved."
            case .simulated:
                return "Simulated trips have no source video file."
            case .bluetoothLinked:
                return "This trip is linked via Bluetooth metadata only; no video path was saved."
            case .importedFile, .wifiNiceDVR:
                return "No video path is stored for this trip."
            }
        }
        return "The saved file is no longer at that location (moved, deleted, or a temporary download that was cleared)."
    }
}
