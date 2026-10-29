import Foundation

/// Word-timed lyrics from the AMLL TTML database (https://api.amll.dev), the community library of
/// Apple-Music-style lyrics. Each word carries the moment it is really sung, so
/// the sweep follows the voice instead of an estimate. Only the song title is sent; a song it does
/// not know falls back to LRCLIB's line timing.
enum AMLLLyrics {
  struct Item: Decodable, Equatable, Sendable {
    let id: Int
    let musicNames: [String]
    let artistNames: [String]
  }

  /// How many matching entries are fetched before giving up on a song.
  static let maxCandidates = 3
  /// Lyrics that run past the track's end by more than this belong to another version of it.
  static let durationSlack: TimeInterval = 3

  static func searchURL(title: String) -> URL? {
    url(path: "/v1/lyrics/search", items: [URLQueryItem(name: "q", value: title)])
  }

  static func getURL(id: Int) -> URL? {
    url(path: "/v1/lyrics/get", items: [URLQueryItem(name: "id", value: String(id))])
  }

  private static func url(path: String, items: [URLQueryItem]) -> URL? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.amll.dev"
    components.path = path
    components.queryItems = items
    return components.url
  }

  /// Lowercased letters and digits only, without "(feat. …)", "[…]" or a " - Single" style suffix.
  static func normalized(_ text: String) -> String {
    var value = text.lowercased()
    value = value.replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]"#, with: " ", options: .regularExpression)
    if let dash = value.range(of: " - ") { value = String(value[..<dash.lowerBound]) }
    let kept = value.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
    return String(kept).split(separator: " ").joined(separator: " ")
  }

  /// Entries whose title is the song's and whose artist appears in the player's artist line.
  static func candidates(_ items: [Item], title: String, artist: String) -> [Item] {
    let wantedTitle = normalized(title)
    let wantedArtist = normalized(artist)
    guard !wantedTitle.isEmpty else { return [] }
    return items.filter { item in
      item.musicNames.contains { normalized($0) == wantedTitle }
        && item.artistNames.contains { name in
          let candidate = normalized(name)
          return !candidate.isEmpty && (wantedArtist.contains(candidate) || candidate.contains(wantedArtist))
        }
    }
  }

  /// Enhanced LRC for the song, or nil when the database has no matching version (or is unreachable).
  static func lookup(_ query: LyricsProvider.Query, fetch: @Sendable (URL) async throws -> Data) async -> String? {
    struct Search: Decodable { struct Page: Decodable { let items: [Item] }; let data: Page? }
    struct Get: Decodable { struct Entry: Decodable { let lyrics: String? }; let data: Entry? }
    guard let search = searchURL(title: query.title),
          let data = try? await fetch(search),
          let items = (try? JSONDecoder().decode(Search.self, from: data))?.data?.items else { return nil }
    for item in candidates(items, title: query.title, artist: query.artist).prefix(maxCandidates) {
      guard let url = getURL(id: item.id), let body = try? await fetch(url),
            let ttml = (try? JSONDecoder().decode(Get.self, from: body))?.data?.lyrics else { continue }
      if query.duration > 0, let length = TTMLLyrics.duration(of: ttml), length > query.duration + durationSlack { continue }
      if let lrc = TTMLLyrics.enhancedLRC(from: ttml) { return lrc }
    }
    return nil
  }
}

/// Apple's word-timed TTML (`<p begin end><span begin end>word</span>…`) as enhanced LRC, the format
/// the cache and `LRCParser` already speak: `[start]<t>word <t>word<end>` per line. Translations,
/// romanizations and background vocals are left out.
enum TTMLLyrics {
  static func enhancedLRC(from ttml: String) -> String? {
    guard let collector = collect(ttml), !collector.lines.isEmpty else { return nil }
    return collector.lines.map { line in
      "[\(stamp(line.begin))]" + line.syllables.map { "<\(stamp($0.begin))>\($0.text)" }.joined() + "<\(stamp(line.end))>"
    }.joined(separator: "\n")
  }

  /// The `dur` of `<body>`: where the lyrics end.
  static func duration(of ttml: String) -> TimeInterval? { collect(ttml)?.bodyDuration }

  /// `12.5`, `4.2s`, `1:02.25` or `1:00:01`.
  static func seconds(_ text: String) -> TimeInterval? {
    var value = text.trimmingCharacters(in: .whitespaces)
    if value.hasSuffix("s") { value.removeLast() }
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard (1...3).contains(parts.count) else { return nil }
    var total = 0.0
    for part in parts {
      guard let number = Double(part), number >= 0, number.isFinite else { return nil }
      total = total * 60 + number
    }
    return total
  }

  private static func stamp(_ time: TimeInterval) -> String {
    let millis = Int((max(0, time) * 1000).rounded())
    return String(format: "%02d:%02d.%03d", millis / 60_000, millis / 1000 % 60, millis % 1000)
  }

  private static func collect(_ ttml: String) -> TTMLCollector? {
    guard !ttml.isEmpty, let data = ttml.data(using: .utf8) else { return nil }
    let parser = XMLParser(data: data)
    let collector = TTMLCollector()
    parser.delegate = collector
    return parser.parse() ? collector : nil
  }
}

private final class TTMLCollector: NSObject, XMLParserDelegate {
  struct Syllable { var begin: TimeInterval; var text: String }
  struct Line { var begin: TimeInterval; var end: TimeInterval; var syllables: [Syllable] }
  private enum Node { case line, word(TimeInterval), skipped, other }

  private(set) var lines: [Line] = []
  private(set) var bodyDuration: TimeInterval?
  private var current: Line?
  private var stack: [Node] = []
  private var text = ""

  private var skipping: Bool { stack.contains { if case .skipped = $0 { return true } else { return false } } }

  func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
              attributes: [String: String] = [:]) {
    let begin = attributes["begin"].flatMap(TTMLLyrics.seconds)
    switch name {
    case "body":
      bodyDuration = attributes["dur"].flatMap(TTMLLyrics.seconds)
      stack.append(.other)
    case "p" where begin != nil:
      current = Line(begin: begin!, end: attributes["end"].flatMap(TTMLLyrics.seconds) ?? begin!, syllables: [])
      stack.append(.line)
    case "span":
      let role = attributes["ttm:role"] ?? attributes["role"] ?? ""
      if skipping || role.hasPrefix("x-") { stack.append(.skipped) }
      else if let begin, current != nil { text = ""; stack.append(.word(begin)) }
      else { stack.append(.other) }
    default:
      stack.append(.other)
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    guard !skipping, let top = stack.last else { return }
    switch top {
    case .word: text += string
    case .line:
      // Whitespace between spans separates words; spans that touch are syllables of one word.
      if string.contains(where: \.isWhitespace), let last = current?.syllables.indices.last,
         current?.syllables[last].text.hasSuffix(" ") == false {
        current?.syllables[last].text += " "
      }
    default: break
    }
  }

  func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
    guard let node = stack.popLast() else { return }
    switch node {
    case .word(let begin):
      let clean = text.replacingOccurrences(of: "\n", with: " ")
      if !clean.trimmingCharacters(in: .whitespaces).isEmpty { current?.syllables.append(Syllable(begin: begin, text: clean)) }
      text = ""
    case .line:
      if var line = current, !line.syllables.isEmpty {
        line.syllables[line.syllables.count - 1].text = line.syllables[line.syllables.count - 1].text
          .trimmingCharacters(in: .whitespaces)
        line.end = max(line.end, line.syllables.last?.begin ?? line.end)
        lines.append(line)
      }
      current = nil
    default: break
    }
  }
}
