// UpdateModels.swift
// Brim
//
// Pure update logic: semantic-version comparison, feed URL validation and feed parsing (a small
// JSON shape, the GitHub releases shape, or a Sparkle-style appcast). No networking here.

import Foundation

struct SemanticVersion: Comparable, Equatable, Sendable {
    let numbers: [Int]
    let prerelease: String?

    /// Accepts "1.2.3", "v1.2", "1.2.3-beta.1", "1.2.3+45". Returns nil when no leading number is found.
    init?(_ text: String) {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("v") || raw.hasPrefix("V") { raw.removeFirst() }
        if let plus = raw.firstIndex(of: "+") { raw = String(raw[..<plus]) }
        var core = raw
        var pre: String?
        if let dash = raw.firstIndex(of: "-") {
            core = String(raw[..<dash])
            pre = String(raw[raw.index(after: dash)...])
        }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        numbers = parts.compactMap { $0 }
        prerelease = (pre?.isEmpty ?? true) ? nil : pre
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.numbers.count, rhs.numbers.count)
        for index in 0..<count {
            let a = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let b = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if a != b { return a < b }
        }
        switch (lhs.prerelease, rhs.prerelease) {  // 1.0.0-beta < 1.0.0
        case (nil, nil): return false
        case (.some, nil): return true
        case (nil, .some): return false
        case let (.some(a), .some(b)): return a.compare(b, options: .numeric) == .orderedAscending
        }
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

struct UpdateRelease: Equatable, Sendable {
    var version: String
    var notes: String
    var downloadURL: URL?
}

enum UpdateFeed {
    /// Only HTTPS feeds with a host are accepted.
    static func validatedURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// A download link is only ever opened when it is HTTPS.
    static func safeDownload(_ text: String?) -> URL? {
        text.flatMap { validatedURL($0) }
    }

    static func parse(_ data: Data) -> UpdateRelease? {
        if let json = try? JSONSerialization.jsonObject(with: data) { return parseJSON(json) }
        return AppcastParser.parse(data)
    }

    private static func parseJSON(_ json: Any) -> UpdateRelease? {
        guard let object = (json as? [String: Any]) ?? (json as? [[String: Any]])?.first else { return nil }
        let version = (object["version"] as? String) ?? (object["tag_name"] as? String)
        guard let version, SemanticVersion(version) != nil else { return nil }
        let notes = (object["notes"] as? String) ?? (object["body"] as? String) ?? ""
        var link = (object["url"] as? String) ?? (object["download_url"] as? String)
        if link == nil, let assets = object["assets"] as? [[String: Any]] {
            link = assets.compactMap { $0["browser_download_url"] as? String }.first
        }
        if link == nil { link = object["html_url"] as? String }
        return UpdateRelease(version: version, notes: String(notes.prefix(4000)), downloadURL: safeDownload(link))
    }
}

/// Reads the newest `<item>` of a Sparkle-style appcast (first item wins).
private final class AppcastParser: NSObject, XMLParserDelegate {
    private var release = UpdateRelease(version: "", notes: "", downloadURL: nil)
    private var inItem = false
    private var done = false
    private var text = ""

    static func parse(_ data: Data) -> UpdateRelease? {
        let delegate = AppcastParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        guard SemanticVersion(delegate.release.version) != nil else { return nil }
        return delegate.release
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        text = ""
        if name == "item" { inItem = !done }
        guard inItem, name == "enclosure" else { return }
        if let short = attributes["sparkle:shortVersionString"] ?? attributes["sparkle:version"] {
            release.version = short
        }
        release.downloadURL = UpdateFeed.safeDownload(attributes["url"])
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { text += String(decoding: CDATABlock, as: UTF8.self) }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard inItem else { return }
        switch name {
        case "sparkle:shortVersionString": release.version = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "description": release.notes = String(Self.stripTags(text).prefix(4000))
        case "item":
            inItem = false
            done = true
            parser.abortParsing()
        default: break
        }
    }

    private static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum UpdateOutcome: Equatable, Sendable {
    case notConfigured
    case invalidFeed
    case upToDate(current: String)
    case available(UpdateRelease)
    case failed(String)
}

enum UpdateDecision {
    static func decide(current: String, release: UpdateRelease) -> UpdateOutcome {
        guard let latest = SemanticVersion(release.version), let mine = SemanticVersion(current) else {
            return .failed("The update feed's version number isn't readable.")
        }
        return latest > mine ? .available(release) : .upToDate(current: current)
    }
}
