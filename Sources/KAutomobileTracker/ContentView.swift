import KAutomobileTrackerCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var trips: TripRepository
    @EnvironmentObject private var analysis: VideoAnalysisEngine

    @State private var selectedTrip: TripRecord?
    @State private var showSessionSheet = false

    var body: some View {
        NavigationSplitView {
            TripListView(
                selectedTrip: $selectedTrip,
                onNewSession: { showSessionSheet = true }
            )
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            if let trip = selectedTrip {
                TripDetailView(trip: trip)
            } else {
                ContentUnavailableView(
                    "Select a trip",
                    systemImage: "car.side",
                    description: Text("Choose a saved trip or start a new tracking session.")
                )
                .accessibilityLabel("No trip selected")
            }
        }
        .sheet(isPresented: $showSessionSheet) {
            TrackingSessionView(isPresented: $showSessionSheet)
                .frame(minWidth: 520, minHeight: 420)
        }
    }
}
