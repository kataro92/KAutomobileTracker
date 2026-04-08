import AppKit
import KAutomobileTrackerCore
import SwiftUI

@main
struct KAutomobileTrackerApp: App {
    @StateObject private var tripRepository = TripRepository()
    @StateObject private var bluetooth = BluetoothDashcamService()
    @StateObject private var niceDVRWiFi = NiceDVRWiFiService()
    @StateObject private var analysis = VideoAnalysisEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tripRepository)
                .environmentObject(bluetooth)
                .environmentObject(niceDVRWiFi)
                .environmentObject(analysis)
        }
        .defaultSize(width: 980, height: 640)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("KAutomobile Tracker Help") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/kataro92/KAutomobileTracker/blob/main/README.md")!)
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(niceDVRWiFi)
        }
    }
}
