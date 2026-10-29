import Foundation

/// Fetches timed lyrics: word-timed ones from AMLL first (`AMLLLyrics`), then line-timed ones
/// from LRCLIB (https://lrclib.net). Opt-in: nothing is requested unless the user turned Lyrics on.
/// Only the track's title, artist, album and duration are sent; failures are quiet.
struct LyricsProvider: Sendable {
  struct Query: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
  }

  static let maxResponseBytes = 600_000
  let fetch: @Sendable (URL) async throws -> Data
  /// Word-timed lyrics tried before LRCLIB; nil skips that step (tests, fixtures).
  let wordTimed: (@Sendable (Query) async -> String?)?

  init(wordTimed: (@Sendable (Query) async -> String?)? = nil, fetch: @escaping @Sendable (URL) async throws -> Data) {
    self.fetch = fetch
    self.wordTimed = wordTimed
  }

  static let live = LyricsProvider(wordTimed: { await AMLLLyrics.lookup($0, fetch: liveFetch) }, fetch: liveFetch)

  static let liveFetch: @Sendable (URL) async throws -> Data = { url in
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 6
    configuration.timeoutIntervalForResource = 10
    configuration.httpCookieStorage = nil
    var request = URLRequest(url: url)
    request.setValue("Brim (macOS menu bar app)", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession(configuration: configuration).data(for: request)
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    if http.statusCode == 404 { return Data() }
    guard (200..<300).contains(http.statusCode), data.count <= maxResponseBytes else {
      throw URLError(.badServerResponse)
    }
    return data
  }

  static func getURL(_ query: Query) -> URL? {
    url(path: "/api/get", items: [
      URLQueryItem(name: "artist_name", value: query.artist),
      URLQueryItem(name: "track_name", value: query.title),
      URLQueryItem(name: "album_name", value: query.album),
      URLQueryItem(name: "duration", value: String(Int(query.duration.rounded()))),
    ])
  }

  static func searchURL(_ query: Query) -> URL? {
    url(path: "/api/search", items: [
      URLQueryItem(name: "artist_name", value: query.artist),
      URLQueryItem(name: "track_name", value: query.title),
    ])
  }

  private static func url(path: String, items: [URLQueryItem]) -> URL? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "lrclib.net"
    components.path = path
    components.queryItems = items.filter { !($0.value ?? "").isEmpty }
    return components.url
  }

  /// Synced lyric text from a `/api/get` object or the best entry of a `/api/search` array.
  /// How far a search hit's length may be from the playing song's.
  static let maximumDurationGap: TimeInterval = 8

  static func syncedLyrics(from data: Data, near duration: TimeInterval) -> String? {
    struct Item: Decodable {
      let syncedLyrics: String?
      let duration: Double?
      let instrumental: Bool?
    }
    guard !data.isEmpty else { return nil }
    let decoder = JSONDecoder()
    if let item = try? decoder.decode(Item.self, from: data) {
      return item.instrumental == true ? nil : usable(item.syncedLyrics)
    }
    guard let items = try? decoder.decode([Item].self, from: data) else { return nil }
    // A search hit whose length is far from the song's is another recording (a remix, a live
    // take, a different song with the same name): its timings would be wrong all the way through.
    let candidates = items.filter { item in
      guard usable(item.syncedLyrics) != nil, item.instrumental != true else { return false }
      guard duration > 0, let length = item.duration else { return true }
      return abs(length - duration) <= maximumDurationGap
    }
    let best = candidates.min {
      abs(($0.duration ?? .infinity) - duration) < abs(($1.duration ?? .infinity) - duration)
    }
    return usable(best?.syncedLyrics)
  }

  private static func usable(_ text: String?) -> String? {
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return text
  }

  /// What a lookup learned: lyrics, a definite "LRCLIB has none", or nothing (offline, server busy),
  /// which must not be remembered as "none".
  enum Outcome: Equatable, Sendable {
    case found(String)
    case missing
    case failed
  }

  /// `get` first (exact match by duration), then `search`; then the same for the lead artist when
  /// the player joins several ("Metro Boomin și Future" — LRCLIB files it under "Metro Boomin").
  func lookup(_ query: Query) async -> Outcome {
    if let wordTimed, let text = await wordTimed(query) { return .found(text) }
    var queries = [query]
    if let lead = Self.leadArtist(query.artist) {
      queries.append(Query(title: query.title, artist: lead, album: query.album, duration: query.duration))
    }
    var failed = false
    for query in queries {
      let urls = [query.duration > 0 ? Self.getURL(query) : nil, Self.searchURL(query)].compactMap { $0 }
      for url in urls {
        do {
          if let text = Self.syncedLyrics(from: try await fetch(url), near: query.duration) { return .found(text) }
        } catch {
          failed = true
        }
      }
    }
    return failed ? .failed : .missing
  }

  func lyrics(for query: Query) async -> String? {
    if case .found(let text) = await lookup(query) { return text }
    return nil
  }

  /// The first name of a joined artist list, in any of the ways players join them; nil for one artist.
  static func leadArtist(_ artist: String) -> String? {
    let joiners = [" și ", " si ", " & ", ", ", " and ", " x ", " X ", " feat. ", " feat ", " ft. ", " · ", " • "]
    let cut = joiners.compactMap { artist.range(of: $0)?.lowerBound }.min()
    guard let cut else { return nil }
    let lead = artist[..<cut].trimmingCharacters(in: .whitespaces)
    return lead.isEmpty ? nil : lead
  }
}
