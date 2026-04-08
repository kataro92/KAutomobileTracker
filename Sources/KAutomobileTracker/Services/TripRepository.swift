import Combine
import Foundation

@MainActor
final class TripRepository: ObservableObject {
    @Published private(set) var trips: [TripRecord] = []

    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("KAutomobileTracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("trips.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            trips = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([TripRecord].self, from: data) {
            trips = decoded.sorted { $0.startedAt > $1.startedAt }
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(trips) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func add(_ trip: TripRecord) {
        trips.removeAll { $0.id == trip.id }
        trips.insert(trip, at: 0)
        save()
    }

    func update(_ trip: TripRecord) {
        guard let idx = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[idx] = trip
        save()
    }
}
