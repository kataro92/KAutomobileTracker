import Foundation

/// User-selectable road-sign jurisdiction for filtering / naming.
public enum SignRegion: String, Codable, CaseIterable, Sendable {
    case vietnam = "Vietnam"
    case us = "US"
}

/// One regulatory group within a region (MUTCD / QCVN style).
public struct SignGroup: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var region: SignRegion
    public var localizedName: String
    public var labelPrefix: String

    public init(id: String, region: SignRegion, localizedName: String, labelPrefix: String) {
        self.id = id
        self.region = region
        self.localizedName = localizedName
        self.labelPrefix = labelPrefix
    }
}

private struct RoadSignRegionDocument: Codable, Sendable {
    var regionId: String
    var description: String?
    var groups: [RoadSignGroupSpec]
}

private struct RoadSignGroupSpec: Codable, Sendable {
    var id: String
    var localizedName: String
    var labelPrefix: String
}

/// Loaded sign-group reference data (bundled JSON) + helpers for YOLO label → group.
public enum SignCatalog {
    private static var cached: [SignRegion: [SignGroup]] = [:]
    private static let lock = NSLock()

    public static func groups(for region: SignRegion) -> [SignGroup] {
        lock.lock()
        defer { lock.unlock() }
        if let c = cached[region] { return c }
        let loaded = loadGroups(for: region)
        cached[region] = loaded
        return loaded
    }

    private static func loadGroups(for region: SignRegion) -> [SignGroup] {
        let name = region == .vietnam ? "vietnam" : "us"
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "sign_catalog"),
              let data = try? Data(contentsOf: url),
              let doc = try? JSONDecoder().decode(RoadSignRegionDocument.self, from: data)
        else {
            return fallbackGroups(for: region)
        }
        let sr = SignRegion(rawValue: doc.regionId) ?? region
        return doc.groups.map { g in
            SignGroup(id: g.id, region: sr, localizedName: g.localizedName, labelPrefix: g.labelPrefix)
        }
    }

    private static func fallbackGroups(for region: SignRegion) -> [SignGroup] {
        switch region {
        case .vietnam:
            return [
                SignGroup(id: "VN_prohibitive", region: .vietnam, localizedName: "Prohibitive", labelPrefix: "VN_prohibitive"),
                SignGroup(id: "VN_warning", region: .vietnam, localizedName: "Warning", labelPrefix: "VN_warning"),
                SignGroup(id: "VN_mandatory", region: .vietnam, localizedName: "Mandatory", labelPrefix: "VN_mandatory"),
                SignGroup(id: "VN_direction", region: .vietnam, localizedName: "Direction", labelPrefix: "VN_direction"),
                SignGroup(id: "VN_additional", region: .vietnam, localizedName: "Additional", labelPrefix: "VN_additional"),
            ]
        case .us:
            return [
                SignGroup(id: "US_regulatory", region: .us, localizedName: "Regulatory", labelPrefix: "US_regulatory"),
                SignGroup(id: "US_warning", region: .us, localizedName: "Warning", labelPrefix: "US_warning"),
                SignGroup(id: "US_guide", region: .us, localizedName: "Guide", labelPrefix: "US_guide"),
                SignGroup(id: "US_temporary", region: .us, localizedName: "Temporary", labelPrefix: "US_temporary"),
                SignGroup(id: "US_school", region: .us, localizedName: "School", labelPrefix: "US_school"),
            ]
        }
    }

    /// Maps a YOLO class label to a known group id for the selected region, if any.
    public static func signGroupId(forLabel label: String, region: SignRegion) -> String? {
        let lower = label.lowercased()
        for g in groups(for: region) where lower.hasPrefix(g.labelPrefix.lowercased()) {
            return g.id
        }
        return nil
    }

    /// COCO \"stop sign\" → regional coarse group for trip summaries.
    public static func cocoStopSignGroupId(region: SignRegion) -> String {
        switch region {
        case .vietnam: return "VN_prohibitive"
        case .us: return "US_regulatory"
        }
    }
}
