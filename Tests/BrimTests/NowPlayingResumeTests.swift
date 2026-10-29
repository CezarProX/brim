import AppKit
import Testing

@testable import Brim

struct NowPlayingResumeTests {
  @Test func pageURLKeepsOnlyTheSongAndItsPlaylist() {
    let raw = "https://music.youtube.com/watch?v=5KRM9707tyA&list=RDAMVM5KRM9707tyA&si=tracking&pp=abc"
    #expect(NowPlayingResume.sanitizedPage(raw) == "https://music.youtube.com/watch?v=5KRM9707tyA&list=RDAMVM5KRM9707tyA")
    #expect(NowPlayingResume.sanitizedPage("https://music.youtube.com/watch?v=5KRM9707tyA")
      == "https://music.youtube.com/watch?v=5KRM9707tyA")
    #expect(NowPlayingResume.sanitizedPage("https://evil.example/watch?v=5KRM9707tyA") == nil)
    #expect(NowPlayingResume.sanitizedPage("https://music.youtube.com/browse/xyz") == nil)
  }

  @Test func resumeStartsAtTheSavedSecond() {
    let page = "https://music.youtube.com/watch?v=5KRM9707tyA&list=RDAMVM5KRM9707tyA"
    #expect(NowPlayingResume.resumeURL(page: page, position: 90.7, duration: 200)?.absoluteString
      == "https://music.youtube.com/watch?v=5KRM9707tyA&list=RDAMVM5KRM9707tyA&t=90")
  }

  @Test func aFinishedSongStartsOver() {
    let page = "https://music.youtube.com/watch?v=5KRM9707tyA"
    #expect(NowPlayingResume.resumeURL(page: page, position: 197, duration: 200)?.absoluteString
      == "https://music.youtube.com/watch?v=5KRM9707tyA")
  }

  @Test func unknownOrHostileTimesNeitherRestartNorCrash() {
    let page = "https://music.youtube.com/watch?v=5KRM9707tyA"
    #expect(NowPlayingResume.resumeURL(page: page, position: 90, duration: 0)?.absoluteString
      == "https://music.youtube.com/watch?v=5KRM9707tyA&t=90")
    #expect(NowPlayingResume.resumeURL(page: page, position: 90, duration: .infinity)?.absoluteString
      == "https://music.youtube.com/watch?v=5KRM9707tyA&t=90")
    #expect(NowPlayingResume.resumeURL(page: page, position: 1e30, duration: 0)?.absoluteString
      == "https://music.youtube.com/watch?v=5KRM9707tyA&t=86400")
    #expect(NowPlayingResume.resumeURL(page: page, position: .nan, duration: .nan)?.absoluteString
      == "https://music.youtube.com/watch?v=5KRM9707tyA")
  }

  @Test func lastPlayedSurvivesARelaunch() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("last-\(UUID().uuidString)")
    let store = NowPlayingResume.Store(directory: dir)
    let last = NowPlayingResume.LastPlayed(
      source: .youtubeApp, title: "Cachalma", artist: "Artist", album: "", duration: 200, position: 90,
      pageURL: "https://music.youtube.com/watch?v=5KRM9707tyA", savedAt: Date(timeIntervalSince1970: 1_790_000_000))
    store.save(last, artwork: Data([1, 2, 3]))
    let reopened = NowPlayingResume.Store(directory: dir)
    #expect(reopened.load() == last)
    #expect(reopened.artwork() == Data([1, 2, 3]))
  }
}

@MainActor
struct NowPlayingRecentlyPlayedModelTests {
  private actor Provider: NowPlayingProviding {
    var snapshots: [NowPlayingSource: NowPlayingSnapshot] = [:]
    var failing: Set<NowPlayingSource> = []
    func set(_ value: NowPlayingSnapshot?, for source: NowPlayingSource) { snapshots[source] = value }
    func fail(_ source: NowPlayingSource) { failing.insert(source) }
    func connect(_ source: NowPlayingSource) async throws {}
    func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? {
      if failing.contains(source) { throw NowPlayingFailure.unavailable("Enable Allow JavaScript from Apple Events") }
      return snapshots[source]
    }
    func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
  }

  @Test func closingThePlayerKeepsTheLastSongInsteadOfAnError() async {
    let provider = Provider()
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("model-\(UUID().uuidString)")
    var song = NowPlayingSnapshot(source: .youtubeApp, title: "Cachalma", artist: "Artist", album: "", duration: 200,
                                  position: 90, isPlaying: true)
    song.pageURL = "https://music.youtube.com/watch?v=5KRM9707tyA"
    await provider.set(song, for: .youtubeApp)
    let model = NowPlayingModel(provider: provider, enabledSources: [.youtubeApp, .youtubeChrome],
                                resumeStore: NowPlayingResume.Store(directory: dir))
    await provider.fail(.youtubeChrome)
    await model.refreshNow()
    await provider.set(nil, for: .youtubeApp)
    // The player clears on the second empty read in a row.
    await model.refreshNow()
    await model.refreshNow()
    #expect(model.track == nil)
    #expect(model.lastPlayed?.title == "Cachalma")
    #expect(model.lastPlayed?.position == 90)
    #expect(!model.status.contains("JavaScript"))
  }

  @Test func aSongWithoutACoverNeverInheritsThePreviousCover() async throws {
    let provider = Provider()
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("model-\(UUID().uuidString)")
    let model = NowPlayingModel(provider: provider, enabledSources: [.youtubeApp],
                                resumeStore: NowPlayingResume.Store(directory: dir))
    var first = NowPlayingSnapshot(source: .youtubeApp, title: "With cover", artist: "A", album: "", duration: 200,
                                   position: 10, isPlaying: true, artworkData: try artwork())
    await provider.set(first, for: .youtubeApp)
    await model.refreshNow()
    try await waitForArtwork(model)
    first = NowPlayingSnapshot(source: .youtubeApp, title: "With cover", artist: "A", album: "", duration: 200,
                               position: 11, isPlaying: false, artworkData: try artwork())
    await provider.set(first, for: .youtubeApp)
    await model.refreshNow()
    await provider.set(NowPlayingSnapshot(source: .youtubeApp, title: "No cover", artist: "B", album: "",
                                          duration: 200, position: 5, isPlaying: true), for: .youtubeApp)
    await model.refreshNow()
    await provider.set(nil, for: .youtubeApp)
    // The player clears on the second empty read in a row.
    await model.refreshNow()
    await model.refreshNow()
    #expect(model.lastPlayed?.title == "No cover")
    #expect(model.lastArtwork == nil)
    #expect(NowPlayingResume.Store(directory: dir).artwork() == nil)
  }

  @Test func aDownloadedCoverIsKeptForResumeAfterThePlayerQuits() async throws {
    let provider = Provider()
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("model-\(UUID().uuidString)")
    let cover = try artwork()
    let model = NowPlayingModel(provider: provider, enabledSources: [.youtubeApp], artworkLoader: { _ in cover },
                                resumeStore: NowPlayingResume.Store(directory: dir))
    let song = NowPlayingSnapshot(source: .youtubeApp, title: "Thumbnail", artist: "A", album: "", duration: 200,
                                  position: 10, isPlaying: true,
                                  artworkURL: "https://i.ytimg.com/vi/5KRM9707tyA/maxresdefault.jpg")
    await provider.set(song, for: .youtubeApp)
    await model.refreshNow()
    try await waitForArtwork(model)
    await model.refreshNow()
    await provider.set(nil, for: .youtubeApp)
    // The player clears on the second empty read in a row.
    await model.refreshNow()
    await model.refreshNow()
    #expect(model.lastArtwork != nil)
    // Offline, or when YouTube has no maxres thumbnail, Recently Played still has the cover.
    #expect(NowPlayingResume.Store(directory: dir).artwork() != nil)
  }

  private func waitForArtwork(_ model: NowPlayingModel) async throws {
    for _ in 0..<200 where model.track?.artwork == nil { try await Task.sleep(for: .milliseconds(10)) }
    try #require(model.track?.artwork != nil)
  }

  private func artwork() throws -> Data {
    let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                        space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
    let image = NSImage(cgImage: try #require(context.makeImage()), size: CGSize(width: 32, height: 32))
    return try ImageEncoder.pngDataPreservingAlpha(from: image)
  }
}
