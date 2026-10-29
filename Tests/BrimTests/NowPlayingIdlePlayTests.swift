import Foundation
import Testing

@testable import Brim

/// Play with nothing on screen must behave like the Mac's play key: one system MediaRemote command,
/// never a relaunch of the last player at its page (the old path opened a new YouTube Music window).
@MainActor
struct NowPlayingIdlePlayTests {
  /// Records every side effect the router asks for.
  @MainActor
  final class Recorder {
    var systemSends: [Int32] = []
    var playerSends: [(Int32, String)] = []
    var confirms = 0
    var opens = 0
    var systemResult: Result<Bool, Error> = .success(true)
    var playerResult: Result<Bool, Error> = .success(true)
    var confirmResults: [Bool] = [true]
    var running: Set<String> = []
    /// Keeps the start pending, as a slow player does, so a second press lands mid-start.
    var confirmWaits = false

    var actions: NowPlayingIdlePlay.Actions {
      NowPlayingIdlePlay.Actions(
        sendToSystem: { command in self.systemSends.append(command); return try self.systemResult.get() },
        sendToPlayer: { command, bundle in self.playerSends.append((command, bundle)); return try self.playerResult.get() },
        confirmPlayback: {
          self.confirms += 1
          if self.confirmWaits { try? await Task.sleep(for: .seconds(2)) }
          return self.confirmResults.isEmpty ? false : self.confirmResults.removeFirst()
        },
        isRunning: { self.running.contains($0) },
        openMusic: { self.opens += 1; return true })
    }
  }

  // MARK: Routing decision

  @Test func theSystemCommandGoesFirstOnlyWhenTheLastPlayerIsGone() {
    for source in NowPlayingSource.allCases {
      #expect(NowPlayingIdlePlay.steps(lastPlayed: source, running: false) == [.system])
    }
    #expect(NowPlayingIdlePlay.steps(lastPlayed: nil, running: false) == [.system, .openMusic])
  }

  /// The system command goes to whatever macOS calls now playing, which can be a film in a browser
  /// (Disney+ in Arc started instead of YouTube Music). A running music player gets it directly.
  @Test func aRunningLastPlayerIsTheOnlyTarget() {
    for source in NowPlayingSource.allCases {
      #expect(NowPlayingIdlePlay.steps(lastPlayed: source, running: true) == [.player(bundleID: source.bundleID)])
    }
  }

  @Test func onlyAPlayerThatNeverPlayedOpensMusic() {
    for source in NowPlayingSource.allCases {
      #expect(!NowPlayingIdlePlay.steps(lastPlayed: source).contains(.openMusic))
    }
  }

  @Test func anAcceptedSystemPlayIsTheWholeJob() async {
    let recorder = Recorder()
    let outcome = await NowPlayingIdlePlay.run(lastPlayed: .youtubeApp, actions: recorder.actions)
    #expect(outcome == .started(.system))
    #expect(recorder.systemSends == [NowPlayingIdlePlay.play])
    #expect(recorder.playerSends.isEmpty)
    #expect(recorder.opens == 0)
  }

  @Test func aRunningPlayerGetsTheCommandAndTheSystemNever() async {
    let recorder = Recorder()
    recorder.running = [NowPlayingSource.youtubeApp.bundleID]
    let outcome = await NowPlayingIdlePlay.run(lastPlayed: .youtubeApp, actions: recorder.actions)
    #expect(outcome == .started(.player(bundleID: NowPlayingSource.youtubeApp.bundleID)))
    #expect(recorder.playerSends.map(\.0) == [NowPlayingIdlePlay.play])
    #expect(recorder.systemSends.isEmpty)
    #expect(recorder.opens == 0)
  }

  /// When another app is now playing, macOS won't route a command to Apple Music or Spotify, but
  /// both take play and pause straight from Apple Events. The YouTube Music players can't.
  @Test func onlyAppleMusicAndSpotifyHaveADirectTransport() {
    #expect(NowPlayingIdlePlay.directSource(forBundle: NowPlayingSource.music.bundleID) == .music)
    #expect(NowPlayingIdlePlay.directSource(forBundle: NowPlayingSource.spotify.bundleID) == .spotify)
    for source in [NowPlayingSource.youtubeApp, .youtubeChrome, .youtubeSafari] {
      #expect(NowPlayingIdlePlay.directSource(forBundle: source.bundleID) == nil)
    }
  }

  @Test func aRefusedRunningPlayerFailsInsteadOfPlayingSomethingElse() async {
    let recorder = Recorder()
    recorder.running = [NowPlayingSource.youtubeApp.bundleID]
    recorder.playerResult = .failure(NowPlayingFailure.unavailable("not now playing"))
    let outcome = await NowPlayingIdlePlay.run(lastPlayed: .youtubeApp, actions: recorder.actions)
    #expect(outcome == .failed("not now playing"))
    #expect(recorder.systemSends.isEmpty)
  }

  @Test func aQuitPlayerIsNeitherTargetedNorLaunched() async {
    let recorder = Recorder()
    recorder.systemResult = .failure(NowPlayingFailure.unavailable("refused"))
    let outcome = await NowPlayingIdlePlay.run(lastPlayed: .youtubeApp, actions: recorder.actions)
    #expect(outcome == .failed("refused"))
    #expect(recorder.playerSends.isEmpty)
    #expect(recorder.opens == 0)
  }

  @Test func aRefusedCommandWithNothingEverPlayedOpensMusicLikeMacOS() async {
    let recorder = Recorder()
    recorder.systemResult = .success(false)
    let outcome = await NowPlayingIdlePlay.run(lastPlayed: nil, actions: recorder.actions)
    #expect(outcome == .started(.openMusic))
    #expect(recorder.opens == 1)
    #expect(recorder.confirms == 0)
  }

  // MARK: Model wiring

  private struct SilentPlayer: NowPlayingProviding {
    var snapshot: NowPlayingSnapshot?
    func connect(_ source: NowPlayingSource) async throws {}
    func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? { snapshot }
    func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
  }

  private func model(_ recorder: Recorder, snapshot: NowPlayingSnapshot? = nil,
                     store: NowPlayingResume.Store = .ephemeral) -> NowPlayingModel {
    NowPlayingModel(provider: SilentPlayer(snapshot: snapshot), enabledSources: snapshot.map { [$0.source] } ?? [],
                    resumeStore: store, stream: nil, idlePlay: recorder.actions)
  }

  private func settle(_ condition: () -> Bool) async {
    for _ in 0..<100 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
  }

  @Test func idlePlayFlipsAtOnceAndLaunchesNothingWhenAPlayerAnswers() async {
    let recorder = Recorder()
    let player = model(recorder)
    player.playFromIdle()
    #expect(player.isStartingPlayback)
    await settle { recorder.confirms > 0 }
    #expect(recorder.systemSends == [NowPlayingIdlePlay.play])
    #expect(recorder.playerSends.isEmpty)
    #expect(recorder.opens == 0)
  }

  @Test func recentlyPlayedResumesThroughTheSystemNotTheSavedPage() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = NowPlayingResume.Store(directory: directory)
    store.save(NowPlayingResume.LastPlayed(
      source: .youtubeApp, title: "Song", artist: "Band", album: "", duration: 200, position: 42,
      pageURL: "https://music.youtube.com/watch?v=dQw4w9WgXcQ", artworkURL: nil, savedAt: .now))
    let recorder = Recorder()
    let player = model(recorder, store: store)
    #expect(player.lastPlayed?.source == .youtubeApp)
    player.resume()
    await settle { recorder.confirms > 0 }
    #expect(recorder.systemSends == [NowPlayingIdlePlay.play])
    #expect(recorder.playerSends.isEmpty)
    #expect(recorder.opens == 0)
  }

  @Test func aFailedIdlePlayRollsBackAndExplains() async {
    let recorder = Recorder()
    recorder.systemResult = .failure(NowPlayingFailure.unavailable("macOS did not accept the media command."))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = NowPlayingResume.Store(directory: directory)
    store.save(NowPlayingResume.LastPlayed(
      source: .spotify, title: "Song", artist: "Band", album: "", duration: 200, position: 42,
      pageURL: nil, artworkURL: nil, savedAt: .now))
    let player = model(recorder, store: store)
    player.playFromIdle()
    await settle { !player.isStartingPlayback }
    #expect(!player.isStartingPlayback)
    #expect(player.commandError == "macOS did not accept the media command.")
    #expect(recorder.opens == 0)
  }

  @Test func aSecondPressWhileStartingPausesAgain() async {
    let recorder = Recorder()
    recorder.confirmResults = []
    let player = model(recorder)
    player.playFromIdle()
    await settle { !recorder.systemSends.isEmpty }
    player.playFromIdle()
    #expect(!player.isStartingPlayback)
    await settle { recorder.systemSends.count == 2 }
    #expect(recorder.systemSends == [NowPlayingIdlePlay.play, NowPlayingIdlePlay.pause])
  }

  @Test func aSecondPressPausesTheRunningPlayerNotTheSystem() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = NowPlayingResume.Store(directory: directory)
    store.save(NowPlayingResume.LastPlayed(
      source: .youtubeApp, title: "Song", artist: "Band", album: "", duration: 200, position: 42,
      pageURL: nil, artworkURL: nil, savedAt: .now))
    let recorder = Recorder()
    recorder.confirmWaits = true
    recorder.running = [NowPlayingSource.youtubeApp.bundleID]
    let player = model(recorder, store: store)
    player.playFromIdle()
    await settle { !recorder.playerSends.isEmpty }
    player.playFromIdle()
    await settle { recorder.playerSends.count == 2 }
    #expect(recorder.playerSends.map(\.0) == [NowPlayingIdlePlay.play, NowPlayingIdlePlay.pause])
    #expect(recorder.systemSends.isEmpty)
  }

  @Test func aPausedSongOnScreenUsesItsOwnControlNotTheSystem() async {
    let recorder = Recorder()
    let paused = NowPlayingSnapshot(source: .music, title: "S", artist: "A", album: "", duration: 100,
                                    position: 5, isPlaying: false)
    let player = model(recorder, snapshot: paused)
    await player.refreshNow()
    #expect(player.track != nil)
    player.playFromIdle()
    #expect(player.track?.isPlaying == true)  // the overlay flips it at once
    #expect(recorder.systemSends.isEmpty)
  }
}
