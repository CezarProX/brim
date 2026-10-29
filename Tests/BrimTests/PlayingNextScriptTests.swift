import AppKit
import Foundation
import Testing

@testable import Brim

/// The Playing Next column once showed AppleScript's own compile error ("Expected class name but
/// found “to”.") as its text. The queue scripts must compile, and a failing read must look empty.
@MainActor
struct PlayingNextScriptTests {
  nonisolated private static let musicInstalled =
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") != nil

  /// Compiling resolves Music's terminology from its bundle without sending it any event.
  private func compileError(_ source: String) -> String? {
    var error: NSDictionary?
    let script = NSAppleScript(source: source)
    guard let script, script.compileAndReturnError(&error) else {
      return (error?[NSAppleScript.errorMessage] as? String) ?? "could not create the script"
    }
    return nil
  }

  @Test(.enabled(if: musicInstalled)) func queueScriptsCompile() {
    #expect(compileError(MusicQueueReader.script(limit: 12)) == nil)
    #expect(compileError(MusicQueueReader.playScript(index: 3)) == nil)
    #expect(compileError(MusicQueueReader.artworkScript(index: 3)) == nil)
  }

  @Test func queueScriptAvoidsMusicKeywordsAsVariables() {
    let script = MusicQueueReader.script(limit: 12)
    for reserved in ["set last to", "set artists to", "thru last of"] { #expect(!script.contains(reserved)) }
  }

  @Test func aFailingReadShowsTheEmptyStateNotTheScriptError() async {
    let raw = "Expected class name but found “to”."
    let model = PlayingNextModel(read: { _ in throw NowPlayingFailure.unavailable(raw) }, perform: { _ in "" },
                                 fetchArtwork: { _ in nil })
    let snapshot = NowPlayingSnapshot(source: .music, title: "S", artist: "A", album: "", duration: 100,
                                      position: 1, isPlaying: true)
    model.refresh(for: NowPlayingTrack(snapshot: snapshot, artwork: nil))
    for _ in 0..<40 where !model.isUnavailable { try? await Task.sleep(for: .milliseconds(10)) }
    #expect(model.isUnavailable)
    #expect(model.items.isEmpty)
    #expect(!model.isLoading)
    // Nothing the model publishes carries the raw message.
    let published = Mirror(reflecting: model).children.map { String(describing: $0.value) }
    #expect(!published.contains { $0.contains(raw) })
  }

  @Test func aLaterGoodReadClearsTheUnavailableState() async {
    var fail = true
    let model = PlayingNextModel(
      read: { _ in if fail { throw NowPlayingFailure.unavailable("boom") }; return "2\u{1F}i\u{1F}Next\u{1F}Art\u{1F}10" },
      perform: { _ in "" }, fetchArtwork: { _ in nil })
    let snapshot = NowPlayingSnapshot(source: .music, title: "S", artist: "A", album: "", duration: 100,
                                      position: 1, isPlaying: true)
    let track = NowPlayingTrack(snapshot: snapshot, artwork: nil)
    model.refresh(for: track)
    for _ in 0..<40 where !model.isUnavailable { try? await Task.sleep(for: .milliseconds(10)) }
    fail = false
    model.refresh(for: track)
    for _ in 0..<40 where model.items.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
    #expect(!model.isUnavailable)
    #expect(model.items.map(\.title) == ["Next"])
  }
}
