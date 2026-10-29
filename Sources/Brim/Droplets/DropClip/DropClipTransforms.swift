// DropClipTransforms.swift
// Brim
//
// Pure text helpers behind the DropClip actions.

import Foundation

enum DropClipTransforms {
  private static let minorWords: Set<String> = [
    "a", "an", "the", "and", "but", "or", "nor", "for", "so", "yet", "as", "at", "by", "in", "of", "on", "to", "up", "vs", "via",
  ]

  static func uppercased(_ text: String) -> String { text.uppercased() }
  static func lowercased(_ text: String) -> String { text.lowercased() }

  /// Title Case: minor words stay lowercase unless first or last; the rest of each word is lowercased.
  static func titleCased(_ text: String) -> String {
    let tokens = text.lowercased().split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    let wordIndexes = tokens.indices.filter { !tokens[$0].isEmpty }
    guard let first = wordIndexes.first, let last = wordIndexes.last else { return text }
    return tokens.enumerated().map { index, token in
      guard !token.isEmpty else { return token }
      let bare = token.trimmingCharacters(in: .punctuationCharacters)
      if index != first, index != last, minorWords.contains(bare) { return token }
      return capitalizingFirstLetter(token)
    }.joined(separator: " ")
  }

  private static func capitalizingFirstLetter(_ token: String) -> String {
    guard let index = token.firstIndex(where: \.isLetter) else { return token }
    return token[..<index] + token[index].uppercased() + token[token.index(after: index)...]
  }

  struct Counts: Equatable {
    var words: Int
    var characters: Int
    var lines: Int
    var readingSeconds: Int

    var summary: String {
      var text = "\(words) word\(words == 1 ? "" : "s") · \(characters) character\(characters == 1 ? "" : "s")"
      if lines > 1 { text += " · \(lines) lines" }
      if readingSeconds >= 10 { text += " · ~\(readingSeconds / 60 > 0 ? "\(readingSeconds / 60) min" : "\(readingSeconds) sec") read" }
      return text
    }
  }

  static func counts(_ text: String) -> Counts {
    let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    let lines = text.isEmpty ? 0 : text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
    let characters = text.filter { !$0.isNewline }.count
    return Counts(words: words, characters: characters, lines: lines, readingSeconds: Int((Double(words) / 238 * 60).rounded()))
  }

  // MARK: URL templates

  /// Characters left alone when percent-encoding a value for a URL: RFC 3986 unreserved only.
  private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
  static let maxQueryLength = 2000
  private static let blockedSchemes: Set<String> = ["file", "javascript", "data", "vbscript", "about", "blob"]

  static func escapeForURL(_ text: String, spaceAsPlus: Bool = false) -> String {
    let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxQueryLength))
    let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    return spaceAsPlus ? encoded.replacingOccurrences(of: "%20", with: "+") : encoded
  }

  /// Replaces `{text}` (percent-encoded) and `{text+}` (spaces as +). Returns nil unless the result
  /// is a URL with a real scheme that isn't file/javascript/data, and the template used the text.
  static func expand(template: String, text: String) -> URL? {
    guard template.contains("{text}") || template.contains("{text+}") else { return nil }
    let filled = template
      .replacingOccurrences(of: "{text+}", with: escapeForURL(text, spaceAsPlus: true))
      .replacingOccurrences(of: "{text}", with: escapeForURL(text))
    guard let url = URL(string: filled), let scheme = url.scheme?.lowercased(), !blockedSchemes.contains(scheme) else { return nil }
    if scheme == "http" || scheme == "https" { return url.host?.isEmpty == false ? url : nil }
    return url
  }

  static let defaultSearchTemplate = "https://duckduckgo.com/?q={text+}"

  // MARK: AppleScript

  /// Escapes text for use inside an AppleScript double-quoted string.
  static func appleScriptQuoted(_ text: String) -> String {
    let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    return "\"" + escaped.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\\n") + "\""
  }

  /// The HTML body Notes expects: escaped text with line breaks.
  static func notesHTML(_ text: String) -> String {
    let escaped = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
    let lines = escaped.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    return "<div>" + lines.joined(separator: "<br>") + "</div>"
  }

  static func notesScript(for text: String) -> String {
    "tell application \"Notes\" to make new note with properties {body:\(appleScriptQuoted(notesHTML(text)))}"
  }

  /// A short label for results and flashes.
  static func preview(_ text: String, limit: Int = 60) -> String {
    let flat = text.replacingOccurrences(of: "\n", with: " ")
    return flat.count > limit ? String(flat.prefix(limit - 1)) + "…" : flat
  }
}
