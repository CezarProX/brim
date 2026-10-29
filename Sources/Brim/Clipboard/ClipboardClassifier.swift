// ClipboardClassifier.swift
// Brim
//
// Pure heuristics behind the smart pinboards: email and code detection and the
// pinboard membership rules. No UI, no I/O.

import Foundation

/// A smart pinboard: an automatic tab that gathers every matching clip.
enum ClipboardPinboard: String, CaseIterable, Identifiable, Sendable {
    case colors, links, images, files, code, emails
    var id: String { rawValue }

    var title: String {
        switch self {
        case .colors: return "Colors"
        case .links: return "Links"
        case .images: return "Images"
        case .files: return "Files"
        case .code: return "Code"
        case .emails: return "Emails"
        }
    }

    var symbol: String {
        switch self {
        case .colors: return "paintpalette.fill"
        case .links: return "link"
        case .images: return "photo.fill"
        case .files: return "doc.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .emails: return "envelope.fill"
        }
    }

    func matches(_ entry: ClipboardEntry) -> Bool {
        switch self {
        case .colors: return entry.kind == .color
        case .links: return entry.kind == .link
        case .images: return entry.kind == .image
        case .files: return entry.kind == .file
        case .code: return entry.kind == .text && ClipboardClassifier.isCode(entry.text ?? "")
        case .emails: return entry.kind != .image && entry.kind != .file
            && ClipboardClassifier.isEmail(entry.text ?? "")
        }
    }

    /// The pinboards enabled in settings, in canonical order.
    static func enabled(in settings: AppSettings = .shared) -> [ClipboardPinboard] {
        let chosen = Set(settings.clipboardPinboards)
        return allCases.filter { chosen.contains($0.rawValue) }
    }
}

enum ClipboardClassifier {
    private static let emailPattern = #"^(mailto:)?[A-Z0-9._%+\-]+@[A-Z0-9](?:[A-Z0-9\-]*[A-Z0-9])?(?:\.[A-Z0-9](?:[A-Z0-9\-]*[A-Z0-9])?)*\.[A-Z]{2,}$"#
    private static let emailRegex = try? NSRegularExpression(pattern: emailPattern, options: [.caseInsensitive])

    /// True for one address, a `mailto:` address, or a short list of addresses separated by commas,
    /// semicolons or whitespace.
    static func isEmail(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 400, let regex = emailRegex else { return false }
        let parts = value.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isWhitespace }).map(String.init)
        guard !parts.isEmpty, parts.count <= 12 else { return false }
        return parts.allSatisfy { part in
            part.count <= 254 && regex.firstMatch(in: part, range: NSRange(part.startIndex..., in: part)) != nil
        }
    }

    private static let keywordRegex = try? NSRegularExpression(pattern: [
        #"\b(func|function|def|class|struct|enum|protocol|interface|impl|fn|import|from|package|namespace|using)\b"#,
        #"\b(return|const|let|var|val|if|else|elif|for|while|switch|case|try|catch|throw|async|await|yield)\b"#,
        #"\b(public|private|protected|static|final|override|extends|implements|typedef|template)\b"#,
        #"^\s*#\s*(include|define|import|pragma|ifdef)\b"#,
        #"\bSELECT\b[\s\S]+\bFROM\b|\bINSERT\s+INTO\b|\bCREATE\s+TABLE\b"#,
        #"</?[a-z][a-z0-9]*(\s[^>]*)?/?>"#,
    ].joined(separator: "|"), options: [.caseInsensitive, .anchorsMatchLines])

    /// Heuristic: shebang, or enough structural signals (braces, semicolons, indentation, keywords,
    /// call/assignment syntax). Plain prose, links and emails never count.
    static func isCode(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .newlines)
        guard value.count >= 6, value.utf8.count <= 100_000 else { return false }
        if value.hasPrefix("#!") && value.contains("/") { return true }
        guard ClipboardEntry.webURL(value) == nil, !isEmail(value),
              ClipboardEntry.color(from: value) == nil else { return false }
        let lines = value.split(separator: "\n", omittingEmptySubsequences: true)
        guard !lines.isEmpty else { return false }
        let sample = lines.prefix(60)
        var score = 0
        let semicolonLines = sample.filter { $0.trimmingCharacters(in: .whitespaces).hasSuffix(";") }.count
        let braceLines = sample.filter {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return t.hasSuffix("{") || t.hasSuffix("}") || t == "}" || t.hasSuffix("};") || t.hasSuffix("},")
        }.count
        let indented = sample.filter { $0.hasPrefix("\t") || $0.hasPrefix("    ") || $0.hasPrefix("  ") }.count
        if semicolonLines > 0 { score += lines.count > 1 && semicolonLines * 3 >= sample.count ? 2 : 1 }
        if braceLines > 0 { score += 2 }
        if lines.count > 1, indented * 2 >= sample.count { score += 1 }
        if value.range(of: Self.structuredPattern, options: [.regularExpression, .caseInsensitive]) != nil { score += 2 }
        if keywordHits(in: value) > 0 { score += 1 }
        if keywordHits(in: value) > 2 { score += 1 }
        if value.range(of: #"\w\s*\([^)\n]*\)"#, options: .regularExpression) != nil { score += 1 }
        if value.range(of: #"=>|->|::|\+\+|&&|\|\||[!=]==?|\w+\s*=\s*[\w"'\[{(]"#, options: .regularExpression) != nil { score += 1 }
        if value.range(of: #"[.\w]+\.\w+\("#, options: .regularExpression) != nil { score += 1 }
        // Prose: sentences end in periods and are mostly letters and spaces.
        let letters = value.filter { $0.isLetter || $0 == " " }.count
        if Double(letters) / Double(value.count) > 0.93 && braceLines == 0 && semicolonLines == 0 { score -= 2 }
        return score >= (lines.count > 1 ? 3 : 4)
    }

    /// SQL statements and balanced HTML/XML tags: code even on a single line.
    private static let structuredPattern =
        #"\b(SELECT\b[\s\S]+\bFROM\b|INSERT\s+INTO\b|CREATE\s+TABLE\b|UPDATE\s+\w+\s+SET\b|DELETE\s+FROM\b)|<([a-z][a-z0-9]*)(\s[^>]*)?>[\s\S]*</\2>"#

    private static func keywordHits(in text: String) -> Int {
        guard let regex = keywordRegex else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}
