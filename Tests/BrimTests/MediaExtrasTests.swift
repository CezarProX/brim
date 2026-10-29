import AppKit
import Foundation
import Testing

@testable import Brim

struct MediaVisibilityRulesTests {
  @Test func titleMarkers() {
    #expect(MediaVisibilityRules.titleLooksPrivate("Lo-fi mix - Google Chrome (Incognito)"))
    #expect(MediaVisibilityRules.titleLooksPrivate("Private Browsing — Firefox"))
    #expect(MediaVisibilityRules.titleLooksPrivate("InPrivate - Microsoft Edge"))
    #expect(!MediaVisibilityRules.titleLooksPrivate("Kill Bill - YouTube Music"))
  }

  @Test func privateWindowShowingTheTrackHidesIt() {
    let windows = [BrowserWindowInfo(title: "Kill Bill - YouTube Music", isPrivate: true),
                   BrowserWindowInfo(title: "Inbox", isPrivate: false)]
    #expect(MediaVisibilityRules.isPrivateMedia(trackTitle: "Kill Bill", windows: windows))
  }

  @Test func normalWindowWithSameTrackWins() {
    let windows = [BrowserWindowInfo(title: "Kill Bill - YouTube Music", isPrivate: true),
                   BrowserWindowInfo(title: "Kill Bill - YouTube Music", isPrivate: false)]
    #expect(!MediaVisibilityRules.isPrivateMedia(trackTitle: "Kill Bill", windows: windows))
  }

  @Test func allPrivateHidesAndUnknownNeverHides() {
    #expect(MediaVisibilityRules.isPrivateMedia(trackTitle: "x", windows: [BrowserWindowInfo(title: "a", isPrivate: true)]))
    #expect(!MediaVisibilityRules.isPrivateMedia(trackTitle: "Kill Bill", windows: []))
    #expect(!MediaVisibilityRules.isPrivateMedia(trackTitle: "Kill Bill", windows: [BrowserWindowInfo(title: "Inbox", isPrivate: false)]))
  }

  @Test func shortTitlesDoNotMatchByAccident() {
    let windows = [BrowserWindowInfo(title: "Go - private", isPrivate: true), BrowserWindowInfo(title: "News", isPrivate: false)]
    #expect(!MediaVisibilityRules.isPrivateMedia(trackTitle: "Go", windows: windows))
  }

  @Test func allowListEmptyMeansEverything() {
    #expect(MediaVisibilityRules.isSourceAllowed(bundleID: "com.spotify.client", allowed: []))
    #expect(MediaVisibilityRules.isSourceAllowed(bundleID: "com.spotify.client", allowed: ["com.spotify.client"]))
    #expect(!MediaVisibilityRules.isSourceAllowed(bundleID: "com.apple.Safari", allowed: ["com.spotify.client"]))
  }

  @Test func parsesChromeWindowRecords() {
    let text = "normal\u{1F}Inbox\u{1E}incognito\u{1F}Kill Bill - YouTube Music\u{1E}"
    let windows = BrowserWindowProbe.parseChromeWindows(text)
    #expect(windows == [BrowserWindowInfo(title: "Inbox", isPrivate: false),
                        BrowserWindowInfo(title: "Kill Bill - YouTube Music", isPrivate: true)])
  }
}

struct DiscordIPCProtocolTests {
  @Test func frameLayoutIsLittleEndianOpcodeLengthJSON() throws {
    let data = DiscordIPCProtocol.frame(.frame, json: Data("{}".utf8))
    #expect(Array(data.prefix(8)) == [1, 0, 0, 0, 2, 0, 0, 0])
    #expect(String(decoding: data.dropFirst(8), as: UTF8.self) == "{}")
  }

  @Test func handshakeCarriesClientID() throws {
    let data = try DiscordIPCProtocol.handshake(clientID: "123456789012345678")
    #expect(data[0] == 0)
    #expect(String(decoding: data.dropFirst(8), as: UTF8.self) == #"{"client_id":"123456789012345678","v":1}"#)
  }

  @Test func parseRoundTripsAndWaitsForWholeFrames() throws {
    let data = DiscordIPCProtocol.frame(.ping, json: Data("hello".utf8))
    #expect(try DiscordIPCProtocol.parse(data.prefix(10)) == nil)
    let parsed = try #require(try DiscordIPCProtocol.parse(data + Data([9, 9])))
    #expect(parsed.opcode == .ping)
    #expect(parsed.consumed == 13)
    #expect(String(decoding: parsed.payload, as: UTF8.self) == "hello")
  }

  @Test func parseRejectsHostileHeaders() {
    var bad = Data()
    withUnsafeBytes(of: Int32(1).littleEndian) { bad.append(contentsOf: $0) }
    withUnsafeBytes(of: Int32(10_000_000).littleEndian) { bad.append(contentsOf: $0) }
    #expect(throws: DiscordError.badFrame) { try DiscordIPCProtocol.parse(bad) }
    var unknown = Data()
    withUnsafeBytes(of: Int32(77).littleEndian) { unknown.append(contentsOf: $0) }
    withUnsafeBytes(of: Int32(0).littleEndian) { unknown.append(contentsOf: $0) }
    #expect(throws: DiscordError.badFrame) { try DiscordIPCProtocol.parse(unknown) }
  }

  @Test func activityPayload() throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let data = try DiscordIPCProtocol.setActivity(
      title: "Kill Bill", artist: "SZA", album: "SOS", elapsed: 60, duration: 150, isPlaying: true, pid: 42, nonce: "n", now: now)
    let json = try #require(JSONSerialization.jsonObject(with: data.dropFirst(8)) as? [String: Any])
    #expect(json["cmd"] as? String == "SET_ACTIVITY")
    let args = try #require(json["args"] as? [String: Any])
    #expect(args["pid"] as? Int == 42)
    let activity = try #require(args["activity"] as? [String: Any])
    #expect(activity["details"] as? String == "Kill Bill")
    #expect(activity["state"] as? String == "SZA")
    #expect(activity["type"] as? Int == 2)
    let times = try #require(activity["timestamps"] as? [String: Int])
    #expect(times["start"] == 940)
    #expect(times["end"] == 1_090)
  }

  @Test func pausedClearsActivityAndTextIsCleaned() throws {
    let data = try DiscordIPCProtocol.setActivity(
      title: "T", artist: "", album: "", elapsed: 0, duration: 0, isPlaying: false, pid: 1, nonce: "n")
    let json = try #require(JSONSerialization.jsonObject(with: data.dropFirst(8)) as? [String: Any])
    #expect((json["args"] as? [String: Any])?["activity"] is NSNull)
    #expect(DiscordIPCProtocol.clean("A").count == 3, "padded to Discord's 2-char minimum")
    #expect(DiscordIPCProtocol.clean(String(repeating: "x", count: 300)).count == 128)
  }

  @Test func clientIDValidation() {
    #expect(DiscordIPCProtocol.isValidClientID("123456789012345678"))
    #expect(!DiscordIPCProtocol.isValidClientID("abc"))
    #expect(!DiscordIPCProtocol.isValidClientID("12345678901234x678"))
    #expect(!DiscordIPCProtocol.isValidClientID(""))
  }
}

struct AutomixDetectorTests {
  private func input(position: Double, duration: Double = 200, fade: Double = 6, on: Bool = true, music: Bool = true,
                     playing: Bool = true) -> AutomixDetector.Input {
    .init(isMusicApp: music, isPlaying: playing, position: position, duration: duration, crossfadeEnabled: on, crossfadeSeconds: fade)
  }

  @Test func quietInTheMiddleOfASong() {
    #expect(AutomixDetector.progress(input(position: 100)) == 0)
  }

  @Test func rampsUpApproachingTheEnd() {
    #expect(AutomixDetector.progress(input(position: 200 - 9.5)) == 0)
    let mid = AutomixDetector.progress(input(position: 200 - 7.5))
    #expect(mid > 0 && mid < 1)
    #expect(AutomixDetector.progress(input(position: 200 - 5)) == 1)
  }

  @Test func holdsThenFadesAfterTheMixLands() {
    let early = AutomixDetector.progress(input(position: 0.5))
    let later = AutomixDetector.progress(input(position: 5))
    #expect(early > later)
    #expect(AutomixDetector.progress(input(position: 30)) == 0)
  }

  @Test func offWhenDisabledPausedOrNotMusic() {
    #expect(AutomixDetector.progress(input(position: 198, on: false)) == 0)
    #expect(AutomixDetector.progress(input(position: 198, playing: false)) == 0)
    #expect(AutomixDetector.progress(input(position: 198, music: false)) == 0)
    #expect(AutomixDetector.progress(input(position: 198, duration: 0)) == 0)
  }
}

struct AudioQualityTests {
  @Test func classification() {
    #expect(AudioQuality.classify(kind: "Apple Lossless audio file", sampleRate: 44_100) == .lossless)
    #expect(AudioQuality.classify(kind: "Apple Lossless audio file", sampleRate: 96_000) == .hiRes)
    #expect(AudioQuality.classify(kind: "Dolby Atmos", sampleRate: 48_000) == .atmos)
    #expect(AudioQuality.classify(kind: "Apple Music AAC audio stream", sampleRate: 44_100) == nil)
    #expect(AudioQuality.classify(kind: nil, sampleRate: nil, extras: ["Spatial Audio"]) == .atmos)
  }
}

struct MediaInteractionRuleTests {
  @Test func spacebarRule() {
    func go(_ key: UInt16 = 49, _ mods: NSEvent.ModifierFlags = [], enabled: Bool = true, open: Bool = true,
            editing: Bool = false, track: Bool = true) -> Bool {
      IslandSpacebarMonitor.shouldHandle(keyCode: key, modifiers: mods, enabled: enabled, islandOpen: open, editingText: editing, hasTrack: track)
    }
    #expect(go())
    #expect(!go(36))
    #expect(!go(49, .command))
    #expect(!go(enabled: false))
    #expect(!go(open: false))
    #expect(!go(editing: true))
    #expect(!go(track: false))
  }

  @Test func settingsDefaultsAndRoundTrip() {
    let suite = "media-extras-\(UUID().uuidString)"
    let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
    #expect(settings.discordPresenceEnabled == false, "Discord is opt-in")
    #expect(settings.mediaHideOnPauseMinutes == 10)
    #expect(settings.notchMusicClickAction == .openIsland)
    settings.discordClientID = "  123456789012345678 "
    settings.mediaHideOnPauseMinutes = -5
    settings.notchMusicClickAction = .playPause
    #expect(settings.discordClientID == "123456789012345678")
    #expect(settings.mediaHideOnPauseMinutes == 0)
    #expect(settings.notchMusicClickAction == .playPause)
  }
}
