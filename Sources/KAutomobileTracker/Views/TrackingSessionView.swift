import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TrackingSessionView: View {
    @EnvironmentObject private var trips: TripRepository
    @EnvironmentObject private var bluetooth: BluetoothDashcamService
    @EnvironmentObject private var niceDVRWiFi: NiceDVRWiFiService
    @EnvironmentObject private var analysis: VideoAnalysisEngine

    @Binding var isPresented: Bool

    @State private var pickedURL: URL?
    @State private var useSimulation = false
    @State private var lastDownloadWasWiFi = false
    @State private var selectedRemoteFile: RemoteDashcamFile?
    @State private var sessionStartedAt = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tracking session")
                .font(.title2.weight(.semibold))

            niceDVRCard

            bluetoothCard

            Toggle("Simulate trip (no video file)", isOn: $useSimulation)
                .disabled(analysis.isRunning)

            if !useSimulation {
                filePickerRow
            }

            if analysis.isRunning {
                ProgressView("Processing…")
                Text("\(analysis.processedFrames) samples analyzed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            liveMetrics

            HStack {
                Button("Cancel") {
                    analysis.cancel()
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Start & track trip") {
                    startTracking()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(analysis.isRunning || (!useSimulation && pickedURL == nil))
            }
        }
        .padding(24)
    }

    private var niceDVRCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nice DVR uses the dashcam’s Wi‑Fi, not Bluetooth, for video. On your Mac: join the same Wi‑Fi network you use in Nice DVR (SSID/password are usually on the camera or in the manual). The camera’s web server is often at 192.168.1.254 — same address Nice DVR reaches after you connect.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text("Camera address")
                    TextField("192.168.1.254", text: $niceDVRWiFi.cameraHost)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                        .disabled(analysis.isRunning || niceDVRWiFi.isBusy)
                }
                Text(niceDVRWiFi.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Test connection") {
                        Task { await niceDVRWiFi.probeConnection() }
                    }
                    .disabled(analysis.isRunning || niceDVRWiFi.isBusy)
                    Button("Refresh file list") {
                        Task { await niceDVRWiFi.refreshFileList() }
                    }
                    .disabled(analysis.isRunning || niceDVRWiFi.isBusy)
                }
                if !niceDVRWiFi.remoteFiles.isEmpty {
                    List(niceDVRWiFi.remoteFiles, selection: $selectedRemoteFile) { file in
                        Text(file.path)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .frame(minHeight: 90, maxHeight: 140)
                    Button("Download selected clip") {
                        Task { await downloadFromCamera() }
                    }
                    .disabled(selectedRemoteFile == nil || analysis.isRunning || niceDVRWiFi.isBusy)
                }
                if let url = pickedURL, lastDownloadWasWiFi {
                    Text("Ready: \(url.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Nice DVR–style Wi‑Fi (Viidure / Novatek HTTP)", systemImage: "wifi")
        }
    }

    private var bluetoothCard: some View {
        GroupBox("Dashcam (Bluetooth)") {
            VStack(alignment: .leading, spacing: 8) {
                Text(bluetooth.statusMessage)
                    .font(.callout)
                HStack {
                    Button("Scan") { bluetooth.startScanning() }
                    Button("Stop scan") { bluetooth.stopScanning() }
                    if bluetooth.connectedPeripheralName != nil {
                        Button("Disconnect") { bluetooth.disconnect() }
                    }
                }
                .disabled(analysis.isRunning)

                if !bluetooth.discovered.isEmpty {
                    List(bluetooth.discovered) { p in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(p.name)
                                Text("RSSI \(p.rssi)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Link") {
                                bluetooth.connect(to: p.id)
                            }
                        }
                    }
                    .frame(minHeight: 100, maxHeight: 140)
                }
            }
        }
    }

    private var filePickerRow: some View {
        HStack {
            Button("Choose video…") {
                pickVideo()
            }
            .disabled(analysis.isRunning)

            if let url = pickedURL {
                Text(url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var liveMetrics: some View {
        GroupBox("Live analysis") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Motion: \(String(format: "%.3f", analysis.lastMotion))")
                Text("Lane estimate: \(analysis.lastLane.rawValue)")
                if !analysis.recentSigns.isEmpty {
                    Text("Recent text: \(analysis.recentSigns.map(\.text).joined(separator: ", "))")
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pickVideo() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        if panel.runModal() == .OK, let url = panel.url {
            pickedURL = url
            lastDownloadWasWiFi = false
        }
    }

    private func downloadFromCamera() async {
        guard let file = selectedRemoteFile else { return }
        do {
            let url = try await niceDVRWiFi.downloadToTemporaryFile(file)
            pickedURL = url
            lastDownloadWasWiFi = true
        } catch {
            niceDVRWiFi.statusLine = "Download failed: \(error.localizedDescription)"
        }
    }

    private func startTracking() {
        sessionStartedAt = Date()
        analysis.resetSessionCounters()

        let inputKind: VideoInputKind
        let sourceLabel: String
        if useSimulation {
            inputKind = .simulated
            sourceLabel = "Simulated dashcam"
        } else if lastDownloadWasWiFi {
            inputKind = .wifiNiceDVR
            let clip = pickedURL?.lastPathComponent ?? "clip"
            sourceLabel = "Nice DVR Wi‑Fi (\(niceDVRWiFi.cameraHost)): \(clip)"
        } else if let name = bluetooth.connectedPeripheralName {
            inputKind = .bluetoothLinked
            sourceLabel = "Bluetooth: \(name)"
        } else if let path = pickedURL?.path {
            inputKind = .importedFile
            sourceLabel = pickedURL?.lastPathComponent ?? path
        } else {
            inputKind = .importedFile
            sourceLabel = "Unknown"
        }

        let filePath = pickedURL?.path
        let url = pickedURL ?? URL(fileURLWithPath: "/dev/null")

        analysis.runAnalysis(
            fileURL: url,
            simulated: useSimulation,
            onProgress: { _ in },
            onComplete: { avg, laneMap, signs, frames in
                let histogram = Dictionary(uniqueKeysWithValues: laneMap.map { ($0.key.rawValue, $0.value) })
                let tracked = frames > 0
                let trip = TripRecord(
                    startedAt: sessionStartedAt,
                    endedAt: Date(),
                    isTracked: tracked,
                    inputKind: inputKind,
                    sourceLabel: sourceLabel,
                    filePath: useSimulation ? nil : filePath,
                    averageMotion: avg,
                    laneHistogram: histogram,
                    signs: signs,
                    frameSamples: frames
                )
                trips.add(trip)
                isPresented = false
            }
        )
    }
}
