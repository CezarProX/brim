import AppKit
import Foundation
import Testing

@testable import Brim

@MainActor
struct PlayingNextPendingTests {
  actor Played {
    private(set) var titles: [String] = []
    func add(_ title: String) { titles.append(title) }
  }

  private func song(_ title: String) -> NowPlayingTrack {
    NowPlayingTrack(snapshot: NowPlayingSnapshot(source: .music, title: title, artist: "A", album: "B", duration: 100,
                                                 position: 0, isPlaying: true, isFavorite: nil, isShuffling: nil),
                    artwork: nil)
  }

  private func item(_ index: Int, _ title: String) -> QueueItem {
    QueueItem(index: index, persistentID: "id\(index)", title: title, artist: "A", duration: 100)
  }

  /// A model whose queue after "Now" is One, Two, Three; plays are recorded, not sent anywhere.
  private func model(_ played: Played) async -> PlayingNextModel {
    let rows = [item(2, "One"), item(3, "Two"), item(4, "Three")]
    let backend = QueueBackend(read: { _, _ in rows }, play: { item, _ in await played.add(item.title) },
                               artwork: { _ in nil })
    let model = PlayingNextModel(music: backend, youtube: backend)
    model.refresh(for: song("Now"))
    for _ in 0..<50 where model.items.isEmpty { await Task.yield() }
    return model
  }

  @Test func playNextMovesTheRowUpWithoutPlaying() async {
    let played = Played()
    let model = await model(played)
    model.playNext(item(4, "Three"), track: song("Now"))
    #expect(model.items.map(\.title) == ["Three", "One", "Two"])
    #expect(model.pendingNext?.title == "Three")
    #expect(await played.titles.isEmpty)
  }

  @Test func naturalAdvancePlaysThePick() async {
    let played = Played()
    let model = await model(played)
    model.playNext(item(4, "Three"), track: song("Now"))
    await model.trackChanged(song("Now"))?.value
    #expect(model.pendingNext != nil, "the same song (a settings sync) changes nothing")
    await model.trackChanged(song("One"))?.value
    #expect(await played.titles == ["Three"])
    #expect(model.pendingNext == nil)
  }

  @Test func reachingThePickOrChoosingAnotherSongClearsIt() async {
    let played = Played()
    let model = await model(played)
    model.playNext(item(4, "Three"), track: song("Now"))
    await model.trackChanged(song("Three"))?.value
    #expect(model.pendingNext == nil)
    model.playNext(item(3, "Two"), track: song("Three"))
    await model.trackChanged(song("Something else"))?.value
    #expect(model.pendingNext == nil, "the user picked another song in the player")
    #expect(await played.titles.isEmpty)
  }

  @Test func chromeWithoutAppleEventsJavaScriptIsShownNotHidden() async {
    let message = "Google Chrome got an error: Executing JavaScript through AppleScript is turned off. To turn it on, "
      + "from the menu bar, go to View > Developer > Allow JavaScript from Apple Events."
    let backend = QueueBackend(read: { _, _ in throw NowPlayingFailure.unavailable(message) }, play: { _, _ in },
                               artwork: { _ in nil })
    let model = PlayingNextModel(music: backend, youtube: backend)
    model.refresh(for: song("Now"))
    for _ in 0..<50 where !model.isUnavailable { await Task.yield() }
    #expect(model.needsChromeJavaScript)
    #expect(!PlayingNextModel.isChromeJavaScriptOff(NowPlayingFailure.unavailable("Apple Music did not answer.")))
  }

  @Test func aPickThePlayerRefusesStillSkips() async {
    let backend = QueueBackend(read: { _, _ in [self.item(2, "One")] },
                               play: { _, _ in throw NowPlayingFailure.unavailable("The queued song is no longer listed.") },
                               artwork: { _ in nil })
    let model = PlayingNextModel(music: backend, youtube: backend)
    model.refresh(for: song("Now"))
    for _ in 0..<50 where model.items.isEmpty { await Task.yield() }
    model.playNext(item(2, "One"), track: song("Now"))
    var skipped = false
    await model.skipToPending(from: song("Now"), fallback: { skipped = true })?.value
    #expect(skipped, "the press of Next falls back to the player's own skip")
  }

  @Test func youTubeMusicQueuesThePickItself() async {
    let played = Played()
    let rows = [item(2, "One"), item(3, "Two")]
    var backend = QueueBackend(read: { _, _ in rows }, play: { _, _ in }, artwork: { _ in nil })
    backend.playNext = { item, _ in await played.add("next:" + item.title) }
    let model = PlayingNextModel(music: backend, youtube: backend)
    model.refresh(for: song("Now"))
    for _ in 0..<50 where model.items.isEmpty { await Task.yield() }
    await model.playNext(item(3, "Two"), track: song("Now"))?.value
    #expect(await played.titles == ["next:Two"], "YouTube Music's own Play next is used")
    #expect(model.pendingNext?.title == "Two")
    #expect(model.skipToPending(from: song("Now")) == nil, "the player's own skip already honours it")
    model.trackChanged(song("Two"))
    #expect(model.pendingNext == nil)
  }

  @Test func playNextWithChromeScriptingOffAsksForIt() async {
    var backend = QueueBackend(read: { _, _ in [self.item(2, "One")] }, play: { _, _ in }, artwork: { _ in nil })
    backend.playNext = { _, _ in
      throw NowPlayingFailure.unavailable("Executing JavaScript through AppleScript is turned off.")
    }
    let model = PlayingNextModel(music: backend, youtube: backend)
    model.refresh(for: song("Now"))
    for _ in 0..<50 where model.items.isEmpty { await Task.yield() }
    await model.playNext(item(2, "One"), track: song("Now"))?.value
    #expect(model.needsChromeJavaScript)
    #expect(model.pendingNext == nil)
  }

  @Test func playNextScriptsEmbedInAppleScript() throws {
    let open = try YouTubeMusicQueueReader.openMenuScript(title: "Say \"Hi\" \\ now", current: "Now")
    let choose = try YouTubeMusicQueueReader.choosePlayNextScript(current: "Now")
    for script in [open, choose] {
      #expect(!script.contains("\""), "no double quotes")
      #expect(!script.contains("\\"), "no backslashes")
      #expect(script.contains("location.hostname !== 'music.youtube.com'"))
    }
    #expect(!open.contains("Hi"), "page data travels base64-encoded")
    #expect(choose.contains("'redă după melodia actuală'"), "the Romanian app's Play next label")
    #expect(!open.contains("ytmusic-player-bar"), "the new player UI has no player bar")
  }

  @Test func pageTransportScriptsEmbedInAppleScriptAndCheckTheSong() throws {
    let next = try YouTubeMusicQueueReader.transportScript(.next, current: "Say \"Hi\" \\ now")
    let previous = try YouTubeMusicQueueReader.transportScript(.previous, current: "Now")
    for script in [next, previous] {
      #expect(!script.contains("\""), "no double quotes")
      #expect(!script.contains("\\"), "no backslashes")
      #expect(script.contains("navigator.mediaSession"))
      #expect(script.contains("location.hostname !== 'music.youtube.com'"))
    }
    #expect(!next.contains("Hi"), "page data travels base64-encoded")
    #expect(next.contains("'înainte'") && previous.contains("'înapoi'"), "the Romanian app's labels")
    #expect(throws: NowPlayingFailure.self) { try YouTubeMusicQueueReader.transportScript(.playPause, current: "Now") }
  }

  @Test func everyRowGetsItsCover() async {
    let rows = (2...11).map { item($0, "Song \($0)") }
    let png = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
      .representation(using: .png, properties: [:])!
    let backend = QueueBackend(read: { _, _ in rows }, play: { _, _ in }, artwork: { _ in png })
    let model = PlayingNextModel(music: backend, youtube: backend)
    model.refresh(for: song("Now"))
    for _ in 0..<300 where model.artwork.count < rows.count { try? await Task.sleep(for: .milliseconds(10)) }
    #expect(model.artwork.count == rows.count, "not only the first six")
  }

  @Test func skipGoesStraightToThePick() async {
    let played = Played()
    let model = await model(played)
    #expect(model.skipToPending(from: song("Now")) == nil, "no pick: the player skips as usual")
    model.playNext(item(3, "Two"), track: song("Now"))
    await model.skipToPending(from: song("Now"))?.value
    #expect(await played.titles == ["Two"])
    #expect(model.pendingNext == nil)
  }
}
