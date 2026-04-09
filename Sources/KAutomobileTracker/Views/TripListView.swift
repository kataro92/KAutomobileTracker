import KAutomobileTrackerCore
import SwiftUI

struct TripListView: View {
    @EnvironmentObject private var trips: TripRepository
    @Binding var selectedTripID: UUID?
    var onLiveTracking: () -> Void
    var onOfflineTracking: () -> Void

    var body: some View {
        List(selection: $selectedTripID) {
            Section {
                Button(action: onLiveTracking) {
                    Label("Live Tracking", systemImage: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Live Tracking")
                Button(action: onOfflineTracking) {
                    Label("Offline Tracking", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Offline Tracking")
            }
            Section("Trips") {
                ForEach(trips.trips) { trip in
                    TripRowView(trip: trip)
                        .tag(trip.id)
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
            if let t = trip.trafficObjects, !t.isEmpty {
                Text("\(t.count) traffic observations")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
