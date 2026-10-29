import AppKit
import SwiftUI

/// Made-up content for the filmed demo (`--demo`): songs, clipboard items, coding sessions and
/// calendar events, so the launch video never shows the user's own data or real (copyrighted) music.
enum DemoSamples {
  struct Song {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let coverSeed: Int
  }

  static let songs = [
    Song(title: "Night Drive", artist: "Lumen Static", album: "Low Light", duration: 214, coverSeed: 1),
    Song(title: "Glass Garden", artist: "Oma Vale", album: "Glass Garden", duration: 187, coverSeed: 4),
    Song(title: "Slow Signals", artist: "Kite & Key", album: "Signals", duration: 205, coverSeed: 3),
  ]

  /// A pretend player: the position keeps moving while it plays, and play/pause, skip and seek work.
  actor Player: NowPlayingProviding {
    private var index = 0
    private var isPlaying = true
    private var base: TimeInterval = 71
    private var since = Date()
    private var covers: [Int: Data] = [:]

    private var position: TimeInterval {
      let song = DemoSamples.songs[index]
      let moved = isPlaying ? Date().timeIntervalSince(since) : 0
      return (base + moved).truncatingRemainder(dividingBy: song.duration)
    }

    func connect(_ source: NowPlayingSource) async throws {}

    func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? {
      let song = DemoSamples.songs[index]
      let cover = covers[song.coverSeed] ?? OnboardingSamples.coverData(seed: song.coverSeed, size: 512)
      covers[song.coverSeed] = cover
      return NowPlayingSnapshot(
        source: .music, title: song.title, artist: song.artist, album: song.album, duration: song.duration,
        position: position, isPlaying: isPlaying, artworkData: cover, isFavorite: false)
    }

    func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {
      switch command {
      case .playPause:
        base = position
        since = Date()
        isPlaying.toggle()
      case .next: jump(to: index + 1)
      case .previous: jump(to: index - 1)
      case .seek(let seconds):
        base = seconds
        since = Date()
      case .setFavorite, .setShuffle, .setRepeat: break
      }
    }

    private func jump(to next: Int) {
      index = (next % DemoSamples.songs.count + DemoSamples.songs.count) % DemoSamples.songs.count
      base = 0
      since = Date()
    }
  }

  /// Where demo replies go: nowhere. It waits like a real send, then reports success.
  @MainActor
  final class SilentReplies: ReplyTransport {
    func send(_ text: String, to item: NotificationContent) async -> Result<Void, ReplyError> {
      try? await Task.sleep(for: .milliseconds(700))
      return .success(())
    }
  }

  /// "Playing Next" rows in the format Apple Music's script returns.
  static func queueBackend() -> QueueBackend {
    let rows: [(String, String, Int)] = [
      ("Glass Garden", "Oma Vale", 187), ("Slow Signals", "Kite & Key", 205), ("Low Tide", "Harbor Lights", 198),
      ("Paper Planes", "The Quiet Hours", 231),
    ]
    let separator = String(QueueParsing.fieldSeparator)
    let output = rows.enumerated().map { offset, row in
      ["\(offset + 2)", "demo-\(offset)", row.0, row.1, "\(row.2)"].joined(separator: separator)
    }.joined(separator: "\n")
    return .script(
      read: { _ in output }, perform: { _ in "" },
      fetchArtwork: { index in OnboardingSamples.coverData(seed: index + 1, size: 96) })
  }

  /// A clipboard history in a temp folder, on a private pasteboard: clicking an item never touches
  /// the user's real clipboard or saved history.
  @MainActor
  static func clipboardStore(now: Date = .now) -> ClipboardStore {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BrimDemoClipboard", isDirectory: true)
    try? FileManager.default.removeItem(at: directory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    func text(_ kind: ClipboardEntry.Kind, _ value: String, minutesAgo: Double, copies: Int = 1, app: String? = nil) -> ClipboardEntry {
      ClipboardEntry(
        id: UUID(), date: now.addingTimeInterval(-minutesAgo * 60), kind: kind, text: value, fingerprint: "demo-\(value)",
        byteCount: value.utf8.count, pixelSize: nil, sourceApp: app, copies: copies)
    }
    var entries = [
      // The launch video selects and copies this line just before it opens the Clipboard page.
      text(.text, "A better clipboard?", minutesAgo: 0, app: "com.apple.Safari"),
      text(.text, "Ship the launch video on Friday. Keep the notch calm.", minutesAgo: 2, app: "com.apple.Notes"),
      text(.link, "https://brim.app", minutesAgo: 9, copies: 2, app: "com.apple.Safari"),
      text(.color, "#18A6FC", minutesAgo: 16),
      text(.text, "Night Drive — Lumen Static", minutesAgo: 41),
    ]
    let imageID = UUID()
    if let png = OnboardingSamples.coverData(seed: 1, size: 900), let thumb = OnboardingSamples.coverData(seed: 1, size: 240) {
      try? png.write(to: directory.appendingPathComponent("\(imageID.uuidString).png"))
      try? thumb.write(to: directory.appendingPathComponent("\(imageID.uuidString)-thumb.png"))
      entries.insert(
        ClipboardEntry(
          id: imageID, date: now.addingTimeInterval(-5 * 60), kind: .image, text: nil, fingerprint: "demo-image",
          byteCount: png.count, pixelSize: "900 × 900", sourceApp: "com.apple.Preview"),
        at: 1)
    }
    if let data = try? JSONEncoder().encode(entries) {
      try? data.write(to: directory.appendingPathComponent("entries.json"))
    }
    return ClipboardStore(directory: directory, pasteboard: NSPasteboard(name: NSPasteboard.Name("io.github.cezarprox.brim.demo")))
  }

  /// An empty screenshot shelf, so the Clipboard page doesn't mix in the user's real captures.
  @MainActor
  static func emptyShelf() -> ShelfStore {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BrimDemoShelf", isDirectory: true)
    try? FileManager.default.removeItem(at: directory)
    return ShelfStore(directory: directory)
  }

  /// Two coding sessions that read as live for the whole recording.
  static func agentSessions(now: Date = .now) -> [CodingAgentSession] {
    let liveUntil = now.addingTimeInterval(3600)
    return [
      CodingAgentSession(
        tool: .claude, model: "Opus", state: .running("Editing PlayerCard.swift"),
        steps: ["Editing PlayerCard.swift", "Read IslandLayout.swift", "Ran swift test"],
        lastMessage: "Moving the waveform under the artwork.", outputTokens: 18_400, contextTokens: 64_000, turns: 12,
        started: now.addingTimeInterval(-14 * 60), updated: liveUntil, id: "demo-claude", project: "weather-app",
        title: "Polish the player card", linesAdded: 86, linesRemoved: 21, currentFile: "PlayerCard.swift",
        contextFraction: 0.32),
      CodingAgentSession(
        tool: .codex, model: "GPT", state: .thinking, steps: ["Read README.md", "Searched for TODO"],
        lastMessage: nil, outputTokens: 5_200, contextTokens: 21_000, turns: 4,
        started: now.addingTimeInterval(-3 * 60), updated: liveUntil, id: "demo-codex", project: "landing-page",
        title: "Write the changelog", contextFraction: 0.11),
    ]
  }

  static func agenda(now: Date = .now, calendar: Calendar) -> [CalendarAgendaDay] {
    let day = calendar.startOfDay(for: now)
    func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
      calendar.date(byAdding: DateComponents(day: dayOffset, hour: hour, minute: minute), to: day) ?? now
    }
    let items = [
      CalendarAgendaItem(id: "demo-1", kind: .event, title: "Design review", start: now.addingTimeInterval(25 * 60),
                         end: now.addingTimeInterval(85 * 60), isAllDay: false, color: .red, joinURL: nil),
      CalendarAgendaItem(id: "demo-2", kind: .reminder, title: "Send the launch email", start: at(0, 18),
                         end: nil, isAllDay: false, color: .orange, joinURL: nil),
      CalendarAgendaItem(id: "demo-3", kind: .event, title: "Team standup", start: at(1, 10),
                         end: at(1, 10, 15), isAllDay: false, color: .blue, joinURL: nil),
      CalendarAgendaItem(id: "demo-4", kind: .event, title: "Coffee with Alex", start: at(1, 16),
                         end: at(1, 17), isAllDay: false, color: .green, joinURL: nil),
      CalendarAgendaItem(id: "demo-5", kind: .reminder, title: "Book the studio", start: at(2, 9),
                         end: nil, isAllDay: false, color: .orange, joinURL: nil),
      CalendarAgendaItem(id: "demo-6", kind: .event, title: "Launch day", start: at(3, 0),
                         end: nil, isAllDay: true, color: .purple, joinURL: nil),
    ]
    return CalendarAgendaBuilder.groupExpanded(items, calendar: calendar)
  }

  static func meeting(now: Date = .now) -> CalendarMeeting {
    CalendarMeeting(id: "demo-1", title: "Design review", startsAt: now.addingTimeInterval(25 * 60),
                    endsAt: now.addingTimeInterval(85 * 60), calendar: "Work", joinURL: nil)
  }
}
