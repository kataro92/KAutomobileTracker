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

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if resolvedVideoURL != nil {
                    Text(isProcessedPlayback ? "Showing processed video with ADAS overlays baked in." : "Showing original file. Use Re-process to generate a processed overlay video.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let url = resolvedVideoURL {
                    Group {
                        if let p = player {
                            MacAVPlayerView(player: p)
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
                            player = configuredPlayer(url: url)
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
            player?.pause()
            player = nil
        }
    }

    private func replacePlayer() {
        player?.pause()
        player = nil
        if let url = resolvedVideoURL {
            player = configuredPlayer(url: url)
        }
    }

    private func configuredPlayer(url: URL) -> AVPlayer {
        let p = AVPlayer(url: url)
        p.volume = 0.25
        p.isMuted = false
        return p
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
