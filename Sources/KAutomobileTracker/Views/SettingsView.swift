import SwiftUI
import KAutomobileTrackerCore

struct SettingsView: View {
    @EnvironmentObject private var niceDVRWiFi: NiceDVRWiFiService
    @EnvironmentObject private var analysis: VideoAnalysisEngine

    @State private var defaultHost: String = ""
    @State private var minInterval: Double = 0.22
    @State private var signRegion: SignRegion = .vietnam
    @State private var confidence: Double = 0.25
    @State private var enableADAS: Bool = true
    @State private var modelZipURL: String = ""
    @State private var downloadMessage: String?
    @State private var isDownloading = false
    @State private var detectionPipeline = AppUserSettings.detectionPipelineSettings
    @State private var useSoftNMS = true
    @State private var byteTrackLowAssoc = true
    @State private var byteTrackFloor: Double = 0.12
    @State private var contrastEnhance = false

    var body: some View {
        Form {
            Section("Object detection") {
                DetectionPipelineControls(settings: $detectionPipeline, persistToUserDefaults: true, useGroupBox: false)
            }
            Section("Dashcam") {
                TextField("Default camera host", text: $defaultHost)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Default camera host or IP address")
                Text("Used when the app starts. You can still change the address per session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Analysis") {
                Slider(value: $minInterval, in: 0.12 ... 0.6, step: 0.02) {
                    Text("Min seconds between samples")
                }
                Text(String(format: "%.2f seconds between analyzed frames (lower uses more CPU).", minInterval))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Road signs") {
                Picker("Sign region", selection: $signRegion) {
                    ForEach(SignRegion.allCases, id: \.self) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                Text("Fine-tuned YOLO sign classes use `VN_*` (Vietnam) or `US_*` (United States) prefixes. The picker filters which family is kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $confidence, in: 0.1 ... 0.75, step: 0.05) {
                    Text("YOLO confidence")
                }
                Text(String(format: "Detection threshold: %.2f — lower catches more vehicles (more false positives).", confidence))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("YOLO CoreML") {
                Toggle("Show lane + detection overlay", isOn: $enableADAS)
                Toggle("Soft-NMS (crowded lanes)", isOn: $useSoftNMS)
                Toggle("Low-confidence track association (ByteTrack-style)", isOn: $byteTrackLowAssoc)
                HStack {
                    Text("Low confidence floor")
                    Slider(value: $byteTrackFloor, in: 0.05 ... 0.35, step: 0.01)
                    Text(String(format: "%.2f", byteTrackFloor))
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
                Text("Weak boxes between “low floor” and the main YOLO threshold can extend existing tracks but never spawn new ones. Ignored if the floor is above the main threshold.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Enhance frame contrast before YOLO (night / glare)", isOn: $contrastEnhance)
                Text("Approximates CLAHE with Core Image filters; uses extra CPU on each analyzed frame.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Adds corridor heuristic and YOLO boxes on previews when models are present. Place `YOLO26-General.mlpackage` in Application Support or the app bundle (see Resources/Models/README.md).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("General COCO-style models classify road traffic: cars, motorcycles / motorbikes, buses, trucks, bicycles, traffic lights, stop signs, people, and similar classes. Use a lower confidence threshold if small or distant objects are missed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Optional: HTTPS URL to models .zip", text: $modelZipURL)
                    .textFieldStyle(.roundedBorder)
                Button("Download & unzip to Application Support") {
                    Task { await downloadModels() }
                }
                .disabled(modelZipURL.trimmingCharacters(in: .whitespaces).isEmpty || isDownloading)
                if isDownloading {
                    ProgressView().scaleEffect(0.8)
                }
                if let downloadMessage {
                    Text(downloadMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Reload models from disk") {
                    analysis.reloadYOLOModels(for: AppUserSettings.detectionPipelineSettings)
                    downloadMessage = "Reloaded models for current pipeline settings."
                }
            }
            Section("Data") {
                Text("Trips are stored under Application Support as trips.json (with trips.backup.json on each save).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding()
        .onAppear {
            defaultHost = AppUserSettings.defaultCameraHost
            minInterval = AppUserSettings.analysisMinInterval
            signRegion = AppUserSettings.selectedSignRegionEnum
            confidence = Double(AppUserSettings.detectionConfidenceThreshold)
            enableADAS = AppUserSettings.enableADASVisualization
            modelZipURL = AppUserSettings.yoloModelDownloadZipURL ?? ""
            detectionPipeline = AppUserSettings.detectionPipelineSettings
            useSoftNMS = AppUserSettings.useSoftNMS
            byteTrackLowAssoc = AppUserSettings.enableByteTrackLowConfidenceAssociation
            byteTrackFloor = Double(AppUserSettings.byteTrackLowConfidenceFloor)
            contrastEnhance = AppUserSettings.enableFrameContrastEnhancement
        }
        .onChange(of: defaultHost) { _, new in
            AppUserSettings.defaultCameraHost = new
            if niceDVRWiFi.cameraHost != new {
                niceDVRWiFi.cameraHost = new
            }
        }
        .onChange(of: minInterval) { _, new in
            AppUserSettings.analysisMinInterval = new
        }
        .onChange(of: signRegion) { _, new in
            AppUserSettings.selectedSignRegionEnum = new
        }
        .onChange(of: confidence) { _, new in
            AppUserSettings.detectionConfidenceThreshold = Float(new)
        }
        .onChange(of: enableADAS) { _, new in
            AppUserSettings.enableADASVisualization = new
        }
        .onChange(of: modelZipURL) { _, new in
            AppUserSettings.yoloModelDownloadZipURL = new.trimmingCharacters(in: .whitespaces).isEmpty ? nil : new
        }
        .onChange(of: useSoftNMS) { _, new in
            AppUserSettings.useSoftNMS = new
        }
        .onChange(of: byteTrackLowAssoc) { _, new in
            AppUserSettings.enableByteTrackLowConfidenceAssociation = new
        }
        .onChange(of: byteTrackFloor) { _, new in
            AppUserSettings.byteTrackLowConfidenceFloor = Float(new)
        }
        .onChange(of: contrastEnhance) { _, new in
            AppUserSettings.enableFrameContrastEnhancement = new
        }
    }

    private func downloadModels() async {
        let raw = modelZipURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: raw), url.scheme == "https" || url.scheme == "http" else {
            downloadMessage = "Enter a valid http(s) URL."
            return
        }
        isDownloading = true
        downloadMessage = "Downloading…"
        defer { isDownloading = false }
        do {
            try await YOLOModelDownloadService.shared.downloadAndUnzip(from: url)
            await MainActor.run {
                analysis.reloadYOLOModels(for: AppUserSettings.detectionPipelineSettings)
                downloadMessage = "Download complete. Models extracted to Application Support/models."
            }
        } catch {
            await MainActor.run {
                downloadMessage = error.localizedDescription
            }
        }
    }
}
