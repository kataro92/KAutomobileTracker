import KAutomobileTrackerCore
import SwiftUI

struct TripDetailView: View {
    let trip: TripRecord
    @Binding var selectedTripID: UUID?

    @EnvironmentObject private var trips: TripRepository
    @EnvironmentObject private var analysis: VideoAnalysisEngine

    @State private var confirmDelete = false
    @State private var isReprocessing = false
    /// After the user cancels reprocessing, ignore the engine’s completion callback so the trip is not overwritten with partial results.
    @State private var ignoreAnalysisResult = false
    @State private var reprocessPipeline = AppUserSettings.detectionPipelineSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                DetectionPipelineControls(settings: $reprocessPipeline, persistToUserDefaults: false)
                if isReprocessing {
                    ProgressView("Reprocessing…")
                    Text("\(analysis.processedFrames) samples analyzed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TripDetailVideoSection(trip: trip)
                trafficObjectsSection
                metrics
                laneSection
                signsSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Trip detail")
        .toolbar {
            if isReprocessing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        ignoreAnalysisResult = true
                        analysis.cancel()
                    }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Cancel reprocessing")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    reprocessTrip()
                } label: {
                    Label("Reprocess", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!canReprocess || analysis.isRunning)
                .help("Run video analysis again using the detector and YOLO version selected above.")
                .accessibilityLabel("Reprocess trip")

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Remove this trip from the library.")
                .accessibilityLabel("Delete trip")
            }
        }
        .confirmationDialog(
            "Delete this trip?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if isReprocessing {
                    ignoreAnalysisResult = true
                    analysis.cancel()
                }
                isReprocessing = false
                ignoreAnalysisResult = false
                trips.remove(id: trip.id)
                selectedTripID = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. The source video file on disk is not deleted.")
        }
        .onChange(of: trip.id) { _, _ in
            reprocessPipeline = AppUserSettings.detectionPipelineSettings
        }
    }

    private var canReprocess: Bool {
        if trip.inputKind == .simulated { return true }
        guard let path = trip.filePath, !path.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    private func reprocessTrip() {
        let simulated = trip.inputKind == .simulated
        let url: URL
        if simulated {
            url = URL(fileURLWithPath: "/dev/null")
        } else {
            guard let path = trip.filePath, FileManager.default.fileExists(atPath: path) else { return }
            url = URL(fileURLWithPath: path)
        }
        ignoreAnalysisResult = false
        isReprocessing = true
        analysis.runAnalysis(
            fileURL: url,
            simulated: simulated,
            pipeline: reprocessPipeline,
            onProgress: { _ in },
            onComplete: { avg, laneMap, signs, traffic, frames in
                isReprocessing = false
                if ignoreAnalysisResult {
                    ignoreAnalysisResult = false
                    return
                }
                let histogram = Dictionary(uniqueKeysWithValues: laneMap.map { ($0.key.rawValue, $0.value) })
                let tracked = frames > 0
                let updated = TripRecord(
                    id: trip.id,
                    startedAt: trip.startedAt,
                    endedAt: Date(),
                    isTracked: tracked,
                    inputKind: trip.inputKind,
                    sourceLabel: trip.sourceLabel,
                    filePath: trip.filePath,
                    processedFilePath: trip.processedFilePath,
                    averageMotion: avg,
                    laneHistogram: histogram,
                    signs: signs,
                    trafficObjects: traffic.isEmpty ? nil : traffic,
                    frameSamples: frames
                )
                trips.update(updated)
            }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: trip.isTracked ? "checkmark.seal.fill" : "seal")
                    .foregroundStyle(trip.isTracked ? .green : .secondary)
                    .font(.title2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.isTracked ? "Tracked trip" : "Incomplete")
                        .font(.title2.weight(.semibold))
                    Text(trip.sourceLabel)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Text("Started \(trip.startedAt.formatted(date: .long, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let end = trip.endedAt {
                Text("Ended \(end.formatted(date: .long, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var metrics: some View {
        GroupBox("Movement & sampling") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Average motion score")
                    Text(String(format: "%.3f", trip.averageMotion))
                        .monospacedDigit()
                }
                GridRow {
                    Text("Analyzed frames")
                    Text("\(trip.frameSamples)")
                        .monospacedDigit()
                }
                GridRow {
                    Text("Input")
                    Text(trip.inputKind.rawValue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var laneSection: some View {
        GroupBox("Lane usage (estimated)") {
            if trip.laneHistogram.isEmpty {
                Text("No lane samples for this trip.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(LaneEstimate.allCases, id: \.self) { lane in
                        let key = lane.rawValue
                        let count = trip.laneHistogram[key] ?? 0
                        if count > 0 {
                            HStack {
                                Text(key.capitalized)
                                Spacer()
                                Text("\(count)")
                                    .monospacedDigit()
                                GeometryReader { geo in
                                    let maxV = trip.laneHistogram.values.max() ?? 1
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(.blue.opacity(0.35))
                                        .frame(width: geo.size.width * CGFloat(count) / CGFloat(maxV))
                                }
                                .frame(height: 8)
                                .frame(maxWidth: 120)
                            }
                            .accessibilityLabel("\(key) lane estimate count \(count)")
                        }
                    }
                }
            }
        }
    }

    private var trafficRows: [TrafficObjectObservation] {
        trip.trafficObjects ?? []
    }

    private var trafficObjectsSection: some View {
        GroupBox("Traffic objects (YOLO)") {
            VStack(alignment: .leading, spacing: 10) {
                if trafficRows.isEmpty {
                    Text("No traffic objects recorded for this trip.")
                        .foregroundStyle(.secondary)
                    Text(
                        "Requires YOLO CoreML (Object detection → YOLO, not Apple Vision). Cars, motorcycles, bicycles, buses, pedestrians, and traffic lights are saved per analyzed frame. Enable overlay in Settings to see boxes on the video."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Table(trafficRows) {
                        TableColumn("Time") { obs in
                            Text(obs.timestamp.formatted(date: .omitted, time: .standard))
                        }
                        TableColumn("Label") { obs in
                            Text(obs.label)
                        }
                        TableColumn("Category") { obs in
                            Text(obs.category.rawValue)
                        }
                        TableColumn("Track") { obs in
                            Text("\(obs.trackId)")
                                .monospacedDigit()
                        }
                        TableColumn("Frame") { obs in
                            Text("\(obs.frameIndex)")
                                .monospacedDigit()
                        }
                        TableColumn("Confidence") { obs in
                            Text(String(format: "%.0f%%", obs.confidence * 100))
                                .monospacedDigit()
                        }
                    }
                    .frame(minHeight: 200)
                    .accessibilityLabel("Traffic object observations table")
                    Text("Long trips keep the most recent 5,000 samples. Track ids are only meaningful within a single analysis run.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var signsSection: some View {
        GroupBox("Road signs (YOLO / catalog)") {
            if trip.signs.isEmpty {
                Text("No traffic signs detected. Add YOLO26 CoreML models and ensure lighting and angle suit detection.")
                    .foregroundStyle(.secondary)
            } else {
                Table(trip.signs) {
                    TableColumn("Time") { obs in
                        Text(obs.timestamp.formatted(date: .omitted, time: .standard))
                    }
                    TableColumn("Class / label") { obs in
                        Text(obs.text)
                    }
                    TableColumn("Region") { obs in
                        Text(obs.signRegion ?? "—")
                    }
                    TableColumn("Group") { obs in
                        Text(obs.signGroupId ?? "—")
                    }
                    TableColumn("Confidence") { obs in
                        Text(String(format: "%.0f%%", obs.confidence * 100))
                            .monospacedDigit()
                    }
                }
                .frame(minHeight: 160)
                .accessibilityLabel("Sign observations table")
            }
        }
    }
}
