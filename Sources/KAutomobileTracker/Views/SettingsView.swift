import SwiftUI
import KAutomobileTrackerCore

struct SettingsView: View {
    @EnvironmentObject private var niceDVRWiFi: NiceDVRWiFiService

    @State private var defaultHost: String = ""
    @State private var minInterval: Double = 0.22

    var body: some View {
        Form {
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
            Section("Data") {
                Text("Trips are stored under Application Support as trips.json (with trips.backup.json on each save).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
        .onAppear {
            defaultHost = AppUserSettings.defaultCameraHost
            minInterval = AppUserSettings.analysisMinInterval
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
    }
}
