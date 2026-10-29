import AppKit

/// "Recently Played": the last song survives quitting the player. Play goes through the system like the
/// Mac's play key (`NowPlayingIdlePlay`); nothing here launches a player or opens its page.
enum NowPlayingResume {
  struct LastPlayed: Codable, Equatable {
    let source: NowPlayingSource
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let position: TimeInterval
    /// Sanitized music.youtube.com watch page (song and playlist only).
    let pageURL: String?
    var artworkURL: String?
    let savedAt: Date
  }

  private static let host = "music.youtube.com"

  /// Keeps only the validated song and playlist of a YouTube Music watch page.
  static func sanitizedPage(_ raw: String) -> String? {
    guard let parts = pageParts(raw) else { return nil }
    return page(video: parts.video, list: parts.list)?.absoluteString
  }

  /// The watch page at `position`, rebuilt from validated parts. A song within 5 s of its end starts over.
  static func resumeURL(page raw: String, position: TimeInterval, duration: TimeInterval) -> URL? {
    guard let parts = pageParts(raw) else { return nil }
    // Unknown (0), infinite or NaN durations keep the saved second; a day caps absurd positions.
    let known = duration.isFinite && duration > 0
    let limit = known ? duration : 86_400
    let seconds = position.isFinite ? Int(min(max(0, position), limit)) : 0
    let finished = known && position >= duration - 5
    return page(video: parts.video, list: parts.list, time: finished ? nil : seconds)
  }

  private static func pageParts(_ raw: String) -> (video: String, list: String?)? {
    guard let components = URLComponents(string: raw), components.scheme == "https", components.host == host,
      components.path == "/watch",
      let video = YouTubeThumbnail.videoID(from: raw)
    else { return nil }
    let list = components.queryItems?.first { $0.name == "list" }?.value
      .flatMap { $0.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil ? $0 : nil }
    return (video, list)
  }

  private static func page(video: String, list: String?, time: Int? = nil) -> URL? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = host
    components.path = "/watch"
    components.queryItems = [URLQueryItem(name: "v", value: video)]
      + (list.map { [URLQueryItem(name: "list", value: $0)] } ?? [])
      + (time.flatMap { $0 > 0 ? [URLQueryItem(name: "t", value: String($0))] : nil } ?? [])
    return components.url
  }

  /// `last-played.json` plus an optional artwork file for players that hand over image data (Apple Music).
  final class Store: @unchecked Sendable {
    /// nil keeps everything in memory: models built by tests or previews never touch the user's file.
    private let directory: URL?
    private var file: URL? { directory?.appendingPathComponent("last-played.json") }
    private var artworkFile: URL? { directory?.appendingPathComponent("last-played-artwork") }

    /// The app's own store in Application Support.
    static let standard = Store(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Brim", isDirectory: true))
    static var ephemeral: Store { Store(directory: nil) }

    init(directory: URL?) {
      self.directory = directory
    }

    func load() -> LastPlayed? {
      guard let file, let data = try? Data(contentsOf: file), data.count < 65_536,
        var last = try? JSONDecoder().decode(LastPlayed.self, from: data)
      else { return nil }
      last.artworkURL = last.artworkURL.flatMap { NowPlayingSnapshot.safeArtworkURL($0)?.absoluteString }
      return last
    }

    func artwork() -> Data? {
      guard let artworkFile, let data = try? Data(contentsOf: artworkFile), data.count <= 5_000_000 else { return nil }
      return data
    }

    func save(_ last: LastPlayed, artwork: Data? = nil) {
      guard let directory, let file, let artworkFile else { return }
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(last).write(to: file, options: .atomic)
        if let artwork { try artwork.write(to: artworkFile, options: .atomic) }
      } catch {
        NSLog("Brim: couldn't remember the last song: \(error.localizedDescription)")
      }
    }

    /// Writes the current song's cover, or removes the file so a coverless song never shows an older one.
    func replaceArtwork(_ artwork: Data?) {
      guard let directory, let artworkFile else { return }
      do {
        if let artwork {
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          try artwork.write(to: artworkFile, options: .atomic)
        } else if FileManager.default.fileExists(atPath: artworkFile.path) {
          try FileManager.default.removeItem(at: artworkFile)
        }
      } catch {
        NSLog("Brim: couldn't remember the last cover: \(error.localizedDescription)")
      }
    }
  }
}
