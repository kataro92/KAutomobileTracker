import Foundation

/// Pure helpers to discover `.mov` / `.mp4` paths in Novatek-style CGI and HTML listing responses. Covered by unit tests.
public enum DashcamHTMLParser {
    public static func videoPaths(in text: String) -> Set<String> {
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

    public static func videoHrefs(in html: String, baseURL: URL) -> Set<String> {
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

    public static func mergeListings(htmlOrCGI: String, pageBase: URL) -> Set<String> {
        var s = videoPaths(in: htmlOrCGI)
        s.formUnion(videoHrefs(in: htmlOrCGI, baseURL: pageBase))
        return s
    }
}

public extension URL {
    func dashcamStandardizedBase() -> URL? {
        guard var c = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return nil }
        if c.scheme == nil { c.scheme = "http" }
        c.path = "/"
        c.fragment = nil
        return c.url
    }
}
