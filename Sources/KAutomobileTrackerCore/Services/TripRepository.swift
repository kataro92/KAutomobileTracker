import Combine
import Foundation

@MainActor
public final class TripRepository: ObservableObject, TripStoring {
    @Published public private(set) var trips: [TripRecord] = []

    private let fileURL: URL
    private let backupURL: URL

    public init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("KAutomobileTracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("trips.json")
        backupURL = dir.appendingPathComponent("trips.backup.json")
        load()
    }

    public func load() {
        let data: Data?
        if let d = try? Data(contentsOf: fileURL) {
            data = d
        } else if let d = try? Data(contentsOf: backupURL) {
            data = d
            AppLog.persistence.notice("Primary trips file missing; loaded from backup")
        } else {
            data = nil
        }
        guard let data else {
            trips = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let doc = try? decoder.decode(TripsDocument.self, from: data) {
            trips = doc.trips.sorted { $0.startedAt > $1.startedAt }
            AppLog.persistence.debug("Loaded trips document v\(doc.schemaVersion), count=\(doc.trips.count)")
            return
        }
        if let legacy = try? decoder.decode([TripRecord].self, from: data) {
            AppLog.persistence.notice("Migrating legacy trips array to schema v\(TripsSchema.currentVersion)")
            trips = legacy.sorted { $0.startedAt > $1.startedAt }
            save()
            return
        }
        AppLog.persistence.error("Corrupt trips.json; could not decode")
        trips = []
    }

    public func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let doc = TripsDocument(schemaVersion: TripsSchema.currentVersion, trips: trips)
        do {
            let data = try encoder.encode(doc)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.copyItem(at: fileURL, to: backupURL)
            }
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLog.persistence.error("Save failed: \(error.localizedDescription)")
        }
    }

    public func add(_ trip: TripRecord) {
        trips.removeAll { $0.id == trip.id }
        trips.insert(trip, at: 0)
        save()
    }

    public func update(_ trip: TripRecord) {
        guard let idx = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[idx] = trip
        save()
    }
}
