import KAutomobileTrackerCore
import SwiftUI

struct TripListView: View {
    @EnvironmentObject private var trips: TripRepository
    @Binding var selectedTrip: TripRecord?
    var onNewSession: () -> Void

    var body: some View {
        List(selection: $selectedTrip) {
            Section {
                Button(action: onNewSession) {
                    Label("New tracking session", systemImage: "record.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("New tracking session")
            }
            Section("Trips") {
                ForEach(trips.trips) { trip in
                    TripRowView(trip: trip)
                        .tag(trip)
                        .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("KAutomobile Tracker")
    }
}

private struct TripRowView: View {
    let trip: TripRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(trip.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                Spacer()
                if trip.isTracked {
                    Text("Tracked")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.green.opacity(0.2)))
                        .accessibilityLabel("Tracked")
                }
            }
            Text(trip.sourceLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !trip.signs.isEmpty {
                Text("\(trip.signs.count) sign observations")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
