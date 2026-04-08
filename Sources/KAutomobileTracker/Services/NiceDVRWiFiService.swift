import Foundation

/// Remote file entry discovered over HTTP (Nice DVR / Viidure / many Novatek-style Wi‑Fi dashcams).
struct RemoteDashcamFile: Identifiable, Hashable, Sendable {
    var id: String { path }
    /// Path relative to camera root, e.g. `/NORMAL/20240101_120000.MOV`
    let path: String
    var displayName: String {
        (path as NSString).lastPathComponent
    }
}

/// Mirrors how **Nice DVR** and similar apps talk to the camera: your Mac joins the camera’s Wi‑Fi, then
/// uses plain HTTP to the camera gateway (commonly `192.168.1.254`) — not Bluetooth for video.
///
/// References: Novatek-style `?custom=1&cmd=3015` file list; root URL often serves an HTML SD-card index;
/// live preview in other apps is frequently `rtsp://192.168.1.254/<name>.mov` (not implemented here — we download files for analysis).
@MainActor
final class NiceDVRWiFiService: ObservableObject {
    @Published var cameraHost: String = "192.168.1.254"
    @Published private(set) var remoteFiles: [RemoteDashcamFile] = []
    @Published var statusLine: String =
        "Join your dashcam Wi‑Fi in System Settings (same as Nice DVR), then tap Refresh list."
    @Published private(set) var isBusy = false

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 600
        config.httpShouldSetCookies = false
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// Normalized base URL, e.g. `http://192.168.1.254/`
    func baseURL() -> URL? {
        let trimmed = cameraHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)?.standardizedBase()
        }
        return URL(string: "http://\(trimmed)")?.standardizedBase()
    }

    func refreshFileList() async {
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
                await mergeVideoPaths(into: &paths, from: cmdURL, pageBase: base)
            }
        }

        await mergeVideoPaths(into: &paths, from: base, pageBase: base)

        remoteFiles = paths.map { RemoteDashcamFile(path: $0) }.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }

        if remoteFiles.isEmpty {
            statusLine =
                "No video links found. Check Wi‑Fi, try opening \(base.absoluteString) in a browser, or confirm your cam uses this API."
        } else {
            statusLine = "Found \(remoteFiles.count) file(s). Select one, download, then start tracking."
        }
    }

    func probeConnection() async -> Bool {
        guard let base = baseURL() else { return false }
        var req = URLRequest(url: base)
        req.timeoutInterval = 6
        do {
            let (_, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if (200 ..< 400).contains(code) {
                statusLine = "Camera responded (HTTP \(code))."
                return true
            }
            statusLine = "Camera returned HTTP \(code)."
            return false
        } catch {
            statusLine = "Cannot reach camera: \(error.localizedDescription)"
            return false
        }
    }

    /// Downloads a path (e.g. from file list) into a temp file for `AVAsset` analysis.
    func downloadToTemporaryFile(_ file: RemoteDashcamFile) async throws -> URL {
        guard let base = baseURL() else {
            throw URLError(.badURL)
        }
        let pathPart = file.path.hasPrefix("/") ? String(file.path.dropFirst()) : file.path
        let encoded = pathPart
            .split(separator: "/")
            .map { $0.description.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0.description }
            .joined(separator: "/")
        guard let target = URL(string: encoded, relativeTo: base)?.absoluteURL else {
            throw URLError(.badURL)
        }

        isBusy = true
        defer { isBusy = false }

        let (tempURL, response) = try await session.download(from: target)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(code) else {
            throw URLError(.badServerResponse)
        }

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("kauto-dashcam-\(UUID().uuidString)-\(file.displayName)")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tempURL, to: dest)
        statusLine = "Saved \(file.displayName) for analysis."
        return dest
    }

    private func mergeVideoPaths(into paths: inout Set<String>, from url: URL, pageBase: URL) async {
        var req = URLRequest(url: url)
        req.timeoutInterval = 25
        do {
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200 ..< 400).contains(http.statusCode) {
                return
            }
            guard let body = String(data: data, encoding: .utf8) else { return }
            paths.formUnion(Self.extractVideoPaths(from: body))
            paths.formUnion(Self.extractHrefs(from: body, baseURL: pageBase))
        } catch {
            return
        }
    }

    /// Paths that look like `.mov` / `.mp4` in CGI or XML replies.
    private static func extractVideoPaths(from text: String) -> Set<String> {
        let pattern = #"(?i)(/[A-Za-z0-9_\-./ ]+\.(mov|mp4))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var out = Set<String>()
        for m in regex.matches(in: text, range: range) {
            if let r = Range(m.range(at: 1), in: text) {
                let p = String(text[r]).replacingOccurrences(of: " ", with: "")
                if p.count > 4 { out.insert(p) }
            }
        }
        return out
    }

    private static func extractHrefs(from html: String, baseURL: URL) -> Set<String> {
        let pattern = #"href=\"([^\"]+)\""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let full = NSRange(html.startIndex..., in: html)
        var out = Set<String>()
        regex.enumerateMatches(in: html, range: full) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: html) else { return }
            var href = String(html[r])
            if let q = href.firstIndex(of: "?") { href = String(href[..<q]) }
            guard href.lowercased().hasSuffix(".mov") || href.lowercased().hasSuffix(".mp4") else { return }
            guard let resolved = URL(string: href, relativeTo: baseURL)?.absoluteURL else { return }
            guard resolved.host == baseURL.host || resolved.host == nil else { return }
            if resolved.path.isEmpty == false {
                out.insert(resolved.path)
            }
        }
        return out
    }
}

private extension URL {
    func standardizedBase() -> URL? {
        guard var c = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return nil }
        if c.scheme == nil { c.scheme = "http" }
        c.path = "/"
        c.fragment = nil
        return c.url
    }
}
