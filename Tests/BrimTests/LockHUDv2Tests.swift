import Foundation
import Testing

@testable import Brim

@Suite struct DownloadDetectionTests {
  @Test func recognisesPartialExtensions() {
    #expect(DownloadFileRules.isPartial("a.zip.crdownload"))
    #expect(DownloadFileRules.isPartial("Movie.mp4.download"))
    #expect(DownloadFileRules.isPartial("x.iso.PART"))
    #expect(!DownloadFileRules.isPartial("a.zip"))
    #expect(!DownloadFileRules.isPartial(".hidden.crdownload"))
    #expect(DownloadFileRules.finalName(forPartial: "a.zip.crdownload") == "a.zip")
    #expect(DownloadFileRules.isDiskImage("App.DMG"))
  }

  @Test func scannerReadsPlainAndSafariBundles() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data(count: 1000).write(to: dir.appendingPathComponent("a.zip.crdownload"))
    try Data(count: 5).write(to: dir.appendingPathComponent("done.zip"))
    let bundle = dir.appendingPathComponent("b.mov.download")
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    try Data(count: 400).write(to: bundle.appendingPathComponent("b.mov"))
    let info = try PropertyListSerialization.data(
      fromPropertyList: ["DownloadEntryProgressTotalToLoad": 2000], format: .xml, options: 0)
    try info.write(to: bundle.appendingPathComponent("Info.plist"))

    let found = DownloadScanner.scan(folder: dir).sorted { $0.partialName < $1.partialName }
    #expect(found.map(\.partialName) == ["a.zip.crdownload", "b.mov.download"])
    #expect(found[0].bytes == 1000 && found[0].totalBytes == nil)
    #expect(found[1].bytes == 400 && found[1].totalBytes == 2000)
    #expect(found[1].finalName == "b.mov")
  }

  @Test func etaFromSteadyRate() {
    var eta = DownloadETA()
    let t0 = Date(timeIntervalSince1970: 0)
    eta.add(bytes: 0, at: t0)
    #expect(eta.secondsLeft(bytes: 0, total: 1000) == nil)  // no rate yet
    eta.add(bytes: 100, at: t0 + 1)
    eta.add(bytes: 200, at: t0 + 2)
    let left = try! #require(eta.secondsLeft(bytes: 200, total: 1000))
    #expect(abs(left - 8) < 0.01)
    #expect(eta.secondsLeft(bytes: 200, total: nil) == nil)
    #expect(DownloadETA.fraction(bytes: 250, total: 1000) == 0.25)
  }

  @Test func etaIgnoresBackwardsSamplesAndSmooths() {
    var eta = DownloadETA()
    let t0 = Date(timeIntervalSince1970: 0)
    eta.add(bytes: 100, at: t0)
    eta.add(bytes: 50, at: t0 + 1)  // restart: ignored
    #expect(eta.bytesPerSecond == nil)
    eta.add(bytes: 150, at: t0 + 2)
    eta.add(bytes: 450, at: t0 + 3)  // burst of 300/s smoothed against 50/s
    let rate = try! #require(eta.bytesPerSecond)
    #expect(rate > 50 && rate < 300)
  }

  @Test func formatsTimeLeft() {
    #expect(DownloadETA.format(0.2) == "1 sec")
    #expect(DownloadETA.format(4.2) == "5 sec")
    #expect(DownloadETA.format(59) == "59 sec")
    #expect(DownloadETA.format(61) == "2 min")
    #expect(DownloadETA.format(3600) == "1 hr")
    #expect(DownloadETA.format(5400) == "1 hr 30 min")
  }

  @Test func plistTotals() throws {
    let data = try PropertyListSerialization.data(fromPropertyList: ["DownloadEntryProgressTotalToLoad": 12345], format: .xml, options: 0)
    #expect(DownloadFileRules.expectedBytes(infoPlist: data) == 12345)
    #expect(DownloadFileRules.expectedBytes(infoPlist: Data("junk".utf8)) == nil)
  }

  @Test func notifyPolicy() {
    #expect(LongTaskNotifyPolicy.shouldNotify(enabled: true, duration: 45, appIsActive: false))
    #expect(!LongTaskNotifyPolicy.shouldNotify(enabled: true, duration: 10, appIsActive: false))
    #expect(!LongTaskNotifyPolicy.shouldNotify(enabled: false, duration: 45, appIsActive: false))
    #expect(!LongTaskNotifyPolicy.shouldNotify(enabled: true, duration: 45, appIsActive: true))
  }

  @Test func diskImageInfoParsesAndGuardsPaths() throws {
    let plist: [String: Any] = ["images": [[
      "image-path": "/Users/me/Downloads/App.dmg",
      "system-entities": [["dev-entry": "/dev/disk4"], ["mount-point": "/Volumes/App"]],
    ]]]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    #expect(DiskImageInfo.parse(data) == ["/Volumes/App": "/Users/me/Downloads/App.dmg"])
    #expect(DiskImageInfo.isTrashable(path: "/Users/me/Downloads/App.dmg", downloads: "/Users/me/Downloads"))
    #expect(!DiskImageInfo.isTrashable(path: "/Users/me/Documents/App.dmg", downloads: "/Users/me/Downloads"))
    #expect(!DiskImageInfo.isTrashable(path: "/Users/me/Downloads/sub/App.dmg", downloads: "/Users/me/Downloads"))
    #expect(!DiskImageInfo.isTrashable(path: "/Users/me/Downloads/notes.txt", downloads: "/Users/me/Downloads"))
  }
}

@Suite @MainActor struct DownloadModelTests {
  @Test func progressThenFinish() {
    let settings = AppSettings.shared
    let model = DownloadProgressModel(folder: { nil })
    let folder = URL(fileURLWithPath: "/nonexistent")
    let wasRing = settings.downloadProgressRing
    settings.downloadProgressRing = true
    defer { settings.downloadProgressRing = wasRing }
    let t0 = Date(timeIntervalSince1970: 100)
    func entry(_ bytes: Int64) -> DownloadEntry { DownloadEntry(partialName: "f.zip.download", bytes: bytes, totalBytes: 1000) }
    model.apply([entry(0)], in: folder, now: t0)
    model.apply([entry(100)], in: folder, now: t0 + 1)
    #expect(model.active?.fraction == 0.1)
    #expect(model.active?.timeLeftText == "9 sec")
    model.apply([], in: folder, now: t0 + 2)
    #expect(model.active == nil)
  }
}

@Suite struct LockLyricsTests {
  private let lyrics = LRCParser.parse("[00:01.00]one\n[00:05.00]two\n[00:09.00]three\n[00:12.00]four")

  @Test func beforeFirstLineShowsNext() {
    let rows = LockLyricsLines.rows(lyrics: lyrics, time: 0)
    #expect(rows.map(\.role) == [.next] && rows[0].text == "one")
  }

  @Test func middleLineHasNeighbours() {
    let rows = LockLyricsLines.rows(lyrics: lyrics, time: 6)
    #expect(rows.map(\.text) == ["one", "two", "three"])
    #expect(rows.map(\.role) == [.previous, .active, .next])
  }

  @Test func firstAndLastClampToTwoRows() {
    #expect(LockLyricsLines.rows(lyrics: lyrics, time: 2).map(\.role) == [.active, .next])
    let last = LockLyricsLines.rows(lyrics: lyrics, time: 100)
    #expect(last.map(\.role) == [.previous, .active] && last.last?.text == "four")
  }

  @Test func lookaheadSwitchesEarlyAndBlankIsNote() {
    #expect(LockLyricsLines.rows(lyrics: lyrics, time: 4.95).first { $0.role == .active }?.text == "two")
    let blank = TimedLyrics(lines: [LyricLine(time: 0, text: "", words: [])])
    #expect(LockLyricsLines.displayText(LockLyricsLines.rows(lyrics: blank, time: 1)[0]) == "♪")
    #expect(LockLyricsLines.rows(lyrics: TimedLyrics(lines: []), time: 1).isEmpty)
  }

  @Test func layoutSitsAboveCardsAndNeedsRoom() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let cards = CGRect(x: 534, y: 180, width: 372, height: 168)
    let frame = LockLyricsLayout.frame(cardsFrame: cards, statusRow: nil, screen: screen)
    #expect(frame != nil && frame!.minY >= cards.maxY)
    #expect(LockLyricsLayout.frame(cardsFrame: nil, statusRow: nil, screen: screen) == nil)
    let tight = CGRect(x: 534, y: 540, width: 372, height: 168)
    #expect(LockLyricsLayout.frame(cardsFrame: tight, statusRow: nil, screen: screen) == nil)
  }
}

@Suite struct EdgeSliderTests {
  @Test func levelMapsFromTopOfTrack() {
    #expect(EdgeSliderMath.level(forY: 0, height: 200) == 1)
    #expect(EdgeSliderMath.level(forY: 200, height: 200) == 0)
    #expect(EdgeSliderMath.level(forY: 50, height: 200) == 0.75)
    #expect(EdgeSliderMath.level(forY: -40, height: 200) == 1)
    #expect(EdgeSliderMath.level(forY: 900, height: 200) == 0)
    #expect(EdgeSliderMath.level(forY: .nan, height: 200) == 0)
    #expect(EdgeSliderMath.level(forY: 10, height: 0) == 0)
  }

  @Test func fillAndSnap() {
    #expect(EdgeSliderMath.fillHeight(level: 0.5, trackHeight: 220) == 110)
    #expect(EdgeSliderMath.fillHeight(level: 2, trackHeight: 220) == 220)
    #expect(EdgeSliderMath.snapped(0.43, fine: false) == 0.4375)
    #expect(EdgeSliderMath.snapped(0.43, fine: true) == 0.4375)
    #expect(EdgeSliderMath.snapped(0.44, fine: true) == 0.4375)
    #expect(EdgeSliderMath.snapped(1.4, fine: false) == 1)
  }

  @Test func firstPressWideThenThin() {
    var session = EdgeSliderSession()
    let t = Date(timeIntervalSince1970: 1000)
    #expect(session.press(now: t) == .wide)
    #expect(session.press(now: t + 0.3) == .wide)  // still inside the wide moment
    #expect(session.press(now: t + 1.2) == .thin)
    #expect(session.press(now: t + 2.0) == .thin)
    #expect(session.isVisible(now: t + 2.5))
    #expect(!session.isVisible(now: t + 4.5))
    #expect(session.press(now: t + 6) == .wide)  // quiet spell: wide again
  }

  @Test func quarterStepsWithShiftOption() {
    // 16 steps normally, 64 with Shift+Option.
    #expect(HUDLevelMath.next(from: 0.5, direction: 1, fine: true) == 0.515625)
    #expect(HUDLevelMath.next(from: 0.5, direction: -1, fine: true) == 0.484375)
    #expect(HUDLevelMath.stepSize(fine: true) == 1.0 / 64)
  }
}

@Suite struct HUDDisplayPolicyTests {
  private let displays = [
    HUDDisplayPolicy.Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 800), isMain: true),
    HUDDisplayPolicy.Display(id: 2, frame: CGRect(x: 1000, y: 0, width: 1000, height: 800), isMain: false),
  ]

  @Test func targets() {
    let pointer = CGPoint(x: 1500, y: 100)
    #expect(HUDDisplayPolicy.targets(.underPointer, pointer: pointer, displays: displays) == [2])
    #expect(HUDDisplayPolicy.targets(.mainDisplay, pointer: pointer, displays: displays) == [1])
    #expect(HUDDisplayPolicy.targets(.allDisplays, pointer: pointer, displays: displays) == [1, 2])
    #expect(HUDDisplayPolicy.targets(.underPointer, pointer: CGPoint(x: -50, y: -50), displays: displays) == [1])
    #expect(HUDDisplayPolicy.targets(.allDisplays, pointer: pointer, displays: []).isEmpty)
    #expect(HUDDisplayPolicy.shows(on: 1, target: .underPointer, pointer: pointer, displays: displays) == false)
  }
}

@Suite struct LockKeepAwakePolicyTests {
  @Test func holdsOnlyInsideTheWindow() {
    var policy = LockKeepAwakePolicy()
    let t = Date(timeIntervalSince1970: 0)
    #expect(!policy.shouldHold(minutes: 5, now: t))
    policy.locked(at: t)
    #expect(policy.shouldHold(minutes: 5, now: t + 299))
    #expect(!policy.shouldHold(minutes: 5, now: t + 300))
    #expect(!policy.shouldHold(minutes: 0, now: t))
    #expect(policy.remaining(minutes: 5, now: t + 100) == 200)
    policy.unlocked()
    #expect(!policy.shouldHold(minutes: 5, now: t + 1))
  }
}

@Suite struct AirPodsAndCaptureTests {
  @Test func modeProbeReadsKnownKeysOnly() {
    #expect(AirPodsModeProbe.mode(from: ["device_listeningMode": "Transparency"]) == .transparency)
    #expect(AirPodsModeProbe.mode(from: ["device_noiseControlMode": "Noise Cancellation"]) == .noiseCancellation)
    #expect(AirPodsModeProbe.mode(from: ["device_listeningMode": "Adaptive"]) == .adaptive)
    #expect(AirPodsModeProbe.mode(from: ["device_batteryLevelLeft": "80%"]) == nil)
  }

  @Test @MainActor func modeChangesAnnounceOnlyAfterFirstReading() {
    let monitor = AirPodsModeMonitor()
    #expect(monitor.changes(["P": .off]).isEmpty)
    #expect(monitor.changes(["P": .off]).isEmpty)
    let change = monitor.changes(["P": .transparency])
    #expect(change.count == 1 && change[0].mode == .transparency)
  }

  @Test func batteriesGroupPerBudAndCase() {
    func battery(_ part: BatteryPart, _ percent: Int) -> DeviceBattery {
      DeviceBattery(id: "x\(part)", name: "n", symbol: "airpodspro", percent: percent, charging: nil,
                    accessoryID: "bluetooth:1", accessoryName: "Alex’s AirPods Pro", part: part, model: .airPodsPro,
                    onPower: nil, minutesToEmpty: nil, minutesToFull: nil)
    }
    let pods = AirPodsBatteries.from([battery(.left, 80), battery(.right, 76), battery(.case, 55)], accessoryID: "bluetooth:1")
    #expect(pods?.left == 80 && pods?.right == 76 && pods?.caseLevel == 55)
    #expect(pods?.symbol == "airpodspro")
    #expect(AirPodsBatteries.from([], accessoryID: "bluetooth:1") == nil)
  }

  @Test func captureThumbnailDefaultsCommand() {
    #expect(CaptureThumbnailPreference.writeArguments(hidden: true)
      == ["write", "com.apple.screencaptureui", "show-thumbnail", "-bool", "false"])
    #expect(CaptureThumbnailPreference.writeArguments(hidden: false).last == "true")
    #expect(CaptureThumbnailPreference.isHidden(readOutput: "0\n"))
    #expect(!CaptureThumbnailPreference.isHidden(readOutput: "1\n"))
    #expect(!CaptureThumbnailPreference.isHidden(readOutput: nil))
  }

  @Test func recordingFilePicksNewestVideoSinceStart() {
    let began = Date(timeIntervalSince1970: 1000)
    func c(_ name: String, _ t: TimeInterval, _ bytes: Int64 = 10) -> RecordingFileLocator.Candidate {
      .init(url: URL(fileURLWithPath: "/tmp/\(name)"), created: Date(timeIntervalSince1970: t), bytes: bytes)
    }
    let pick = RecordingFileLocator.pick(
      [c("old.mov", 500), c("a.mov", 1010), c("b.mp4", 1100), c("shot.png", 1200), c("empty.mov", 1300, 0)], since: began)
    #expect(pick?.lastPathComponent == "b.mp4")
    #expect(RecordingFileLocator.pick([c("old.mov", 500)], since: began) == nil)
    #expect(RecordingFileLocator.captureFolder(defaultsLocation: "~/Movies").path.hasSuffix("/Movies"))
  }
}
