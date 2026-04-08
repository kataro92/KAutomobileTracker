import Foundation

public struct RemoteDashcamFile: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String

    public init(path: String) {
        self.path = path
    }

    public var displayName: String {
        (path as NSString).lastPathComponent
    }
}
