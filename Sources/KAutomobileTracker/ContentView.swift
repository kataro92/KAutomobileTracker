import KAutomobileTrackerCore
import SwiftUI

private enum SessionSheetKind: String, Identifiable {
    case liveTracking
    case offlineTracking

    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var trips: TripRepository
    @EnvironmentObject private var analysis: VideoAnalysisEngine
    @Environment(\.openSettings) private var openSettings

    @State private var selectedTripID: UUID?
    @State private var activeSessionSheet: SessionSheetKind?

    private var selectedTrip: TripRecord? {
        guard let id = selectedTripID else { return nil }
        return trips.trips.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            TripListView(
                selectedTripID: $selectedTripID,
                onLiveTracking: { activeSessionSheet = .liveTracking },
                onOfflineTracking: { activeSessionSheet = .offlineTracking }
            )
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            if let trip = selectedTrip {
                TripDetailView(trip: trip, selectedTripID: $selectedTripID)
            } else {
                ContentUnavailableView(
                    "Select a trip",
                    systemImage: "car.side",
                    description: Text("Choose a saved trip or start live or offline tracking.")
                )
                .accessibilityLabel("No trip selected")
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Open settings")
                .accessibilityLabel("Settings")
            }
        }
        .sheet(item: $activeSessionSheet) { kind in
            Group {
                switch kind {
                case .liveTracking:
                    LiveTrackingView()
                case .offlineTracking:
                    OfflineTrackingView()
                }
            }
            .frame(minWidth: 520, minHeight: 420)
        }
    }
}
