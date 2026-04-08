import Foundation
import KAutomobileTrackerCore
import Observation

@MainActor
@Observable
final class TrackingSessionViewModel {
    var pickedURL: URL?
    var useSimulation = false
    var lastDownloadWasWiFi = false
    var selectedRemoteFile: RemoteDashcamFile?
    var sessionStartedAt = Date()

    func markNewSession() {
        sessionStartedAt = Date()
    }
}
