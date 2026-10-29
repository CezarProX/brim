import AppKit
import Testing

@testable import Brim

@MainActor
struct HomeIdlePlayerCardTests {
  /// The song's cover arrives after the song itself, so "last artwork" can still be empty; the card
  /// must show the playing song's own cover.
  @Test func showsThePlayingSongsCoverBeforeItIsRemembered() async throws {
    let model = await OnboardingSamples.nowPlaying()
    let cover = try #require(model.track?.artwork)
    #expect(HomeIdlePlayerCard.cover(for: model) === cover)
  }

  @Test func showsNoCoverWithoutASong() {
    let model = NowPlayingModel(provider: SilentPlayer(), enabledSources: [], stream: nil)
    #expect(HomeIdlePlayerCard.cover(for: model) == nil)
  }
}

private actor SilentPlayer: NowPlayingProviding {
  func connect(_ source: NowPlayingSource) async throws {}
  func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? { nil }
  func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
}
