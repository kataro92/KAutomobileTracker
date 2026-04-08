import Combine
import Foundation

/// Nice DVR / Viidure-style HTTP dashcam listing. See `docs/DASHCAM_VENDOR_NOTES.md` for capture guidance.
@MainActor
public final class NiceDVRWiFiService: ObservableObject, DashcamWiFiListing {
    @Published public var cameraHost: String = "192.168.1.254"
    @Published public private(set) var remoteFiles: [RemoteDashcamFile] = []
    @Published public var statusLine: String =
        "Join your dashcam Wi‑Fi in System Settings (same as Nice DVR), then tap Refresh list."
    @Published public private(set) var isBusy = false

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 600
        config.httpShouldSetCookies = false
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    public init() {
        cameraHost = AppUserSettings.defaultCameraHost
    }

    public func baseURL() -> URL? {
        let trimmed = cameraHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)?.dashcamStandardizedBase()
        }
        return URL(string: "http://\(trimmed)")?.dashcamStandardizedBase()
    }

    public func refreshFileList() async {
        guard let base = baseURL() else {
            statusLine = "Enter the camera address (usually 192.168.1.254)."
            return
        }
        isBusy = true
        defer { isBusy = false }

        var paths = Set<String>()

        if var cmd = URLComponents(url: base, resolvingAgainstBaseURL: true) {
            cmd.path = "/"
            cmd.queryItems = [
                URLQueryItem(name: "custom", value: "1"),
                URLQueryItem(name: "cmd", value: "3015"),
            ]
            if let cmdURL = cmd.url {
                await mergeVideoPaths(into: &paths, from: cmdURL, hrefBase: base)
            }
        }

        await mergeVideoPaths(into: &paths, from: base, hrefBase: base)

        remoteFiles = paths.map { RemoteDashcamFile(path: $0) }.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }

        let listedCount = remoteFiles.count
        if remoteFiles.isEmpty {
            statusLine =
                "No video links found. Check Wi‑Fi, try opening \(base.absoluteString) in a browser, or confirm your cam uses this API."
            AppLog.network.notice("File list empty for base \(base.host ?? "?")")
        } else {
            statusLine = "Found \(listedCount) file(s). Select one, download, then start tracking."
            AppLog.network.debug("Listed \(listedCount) remote files")
        }
    }

    public func probeConnection() async -> Bool {
        guard let base = baseURL() else { return false }
        var req = URLRequest(url: base)
        req.timeoutInterval = 6
        do {
            let (_, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if (200 ..< 400).contains(code) {
                statusLine = "Camera responded (HTTP \(code))."
                AppLog.network.debug("Probe OK HTTP \(code)")
                return true
            }
            statusLine = "Camera returned HTTP \(code)."
            return false
        } catch {
            statusLine = "Cannot reach camera: \(error.localizedDescription)"
            AppLog.network.error("Probe failed: \(error.localizedDescription)")
            return false
        }
    }

    public func downloadToTemporaryFile(_ file: RemoteDashcamFile) async throws -> URL {
        guard let base = baseURL() else {
            throw KAutoError.cameraBadURL
        }
        let pathPart = file.path.hasPrefix("/") ? String(file.path.dropFirst()) : file.path
        let encoded = pathPart
            .split(separator: "/")
            .map { $0.description.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0.description }
            .joined(separator: "/")
        guard let target = URL(string: encoded, relativeTo: base)?.absoluteURL else {
            throw KAutoError.cameraBadURL
        }

        isBusy = true
        defer { isBusy = false }

        let (tempURL, response) = try await session.download(from: target)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(code) else {
            AppLog.network.error("Download HTTP \(code) for \(file.displayName)")
            throw KAutoError.cameraDownloadFailed(statusCode: code)
        }

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("kauto-dashcam-\(UUID().uuidString)-\(file.displayName)")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tempURL, to: dest)
        statusLine = "Saved \(file.displayName) for analysis."
        AppLog.network.debug("Downloaded \(file.displayName)")
        return dest
    }

    private func mergeVideoPaths(into paths: inout Set<String>, from url: URL, hrefBase: URL) async {
        var req = URLRequest(url: url)
        req.timeoutInterval = 25
        do {
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200 ..< 400).contains(http.statusCode) {
                return
            }
            guard let body = String(data: data, encoding: .utf8) else { return }
            paths.formUnion(DashcamHTMLParser.mergeListings(htmlOrCGI: body, pageBase: hrefBase))
        } catch {
            AppLog.network.debug("mergeVideoPaths skip \(url.path): \(error.localizedDescription)")
        }
    }
}

extension NiceDVRWiFiService: DashcamWiFiConnector {}
