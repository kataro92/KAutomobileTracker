import SwiftUI

struct TripDetailView: View {
    let trip: TripRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                metrics
                laneSection
                signsSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Trip detail")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: trip.isTracked ? "checkmark.seal.fill" : "seal")
                    .foregroundStyle(trip.isTracked ? .green : .secondary)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.isTracked ? "Tracked trip" : "Incomplete")
                        .font(.title2.weight(.semibold))
                    Text(trip.sourceLabel)
                        .foregroundStyle(.secondary)
                }
            }
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
                        }
                    }
                }
            }
        }
    }

    private var signsSection: some View {
        GroupBox("Road signs (text recognition)") {
            if trip.signs.isEmpty {
                Text("No sign-like text detected. Lighting, angle, and resolution affect results.")
                    .foregroundStyle(.secondary)
            } else {
                Table(trip.signs) {
                    TableColumn("Time") { obs in
                        Text(obs.timestamp.formatted(date: .omitted, time: .standard))
                    }
                    TableColumn("Text") { obs in
                        Text(obs.text)
                    }
                    TableColumn("Confidence") { obs in
                        Text(String(format: "%.0f%%", obs.confidence * 100))
                            .monospacedDigit()
                    }
                }
                .frame(minHeight: 160)
            }
        }
    }
}
