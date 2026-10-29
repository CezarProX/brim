import AppKit
import Foundation
import Testing

@testable import Brim

@Suite("Capture thumbnail layout")
struct CaptureThumbnailLayoutTests {
  let laptop = CGRect(x: 0, y: 0, width: 1440, height: 875)
  let card = ThumbnailLayout.cardSize
  let margin = ThumbnailLayout.margin

  @Test func newestCardSitsInEachCornerAtTheMargin() {
    let br = ThumbnailLayout.cardFrame(slot: 0, corner: .bottomRight, in: laptop)
    #expect(br == CGRect(x: 1440 - margin - card.width, y: margin, width: card.width, height: card.height))
    let bl = ThumbnailLayout.cardFrame(slot: 0, corner: .bottomLeft, in: laptop)
    #expect(bl.minX == margin && bl.minY == margin)
    let tr = ThumbnailLayout.cardFrame(slot: 0, corner: .topRight, in: laptop)
    #expect(tr.maxX == 1440 - margin && tr.maxY == 875 - margin)
    let tl = ThumbnailLayout.cardFrame(slot: 0, corner: .topLeft, in: laptop)
    #expect(tl.minX == margin && tl.maxY == 875 - margin)
  }

  @Test(arguments: ThumbnailCorner.allCases)
  func olderCardsStackAwayFromTheCorner(corner: ThumbnailCorner) {
    let newest = ThumbnailLayout.cardFrame(slot: 0, corner: corner, in: laptop)
    let older = ThumbnailLayout.cardFrame(slot: 1, corner: corner, in: laptop)
    let step = card.height + ThumbnailLayout.spacing
    #expect(older.minX == newest.minX)
    #expect(older.minY - newest.minY == (corner.isBottom ? step : -step))
    #expect(!older.intersects(newest))
  }

  @Test(arguments: ThumbnailCorner.allCases)
  func cardsStayOnTheirOwnScreen(corner: ThumbnailCorner) {
    let left = CGRect(x: -1920, y: -180, width: 1920, height: 1050)
    let right = CGRect(x: 1440, y: 300, width: 2560, height: 1415)
    for screen in [left, right, laptop] {
      for slot in 0..<ThumbnailLayout.capacity(in: screen) {
        #expect(screen.contains(ThumbnailLayout.cardFrame(slot: slot, corner: corner, in: screen)))
      }
    }
  }

  @Test func capacityFollowsScreenHeightUpToFour() {
    #expect(ThumbnailLayout.capacity(in: laptop) == 3)
    #expect(ThumbnailLayout.capacity(in: CGRect(x: 0, y: 0, width: 1920, height: 1050)) == 4)
    #expect(ThumbnailLayout.capacity(in: CGRect(x: 0, y: 0, width: 2560, height: 2000)) == 4)
    #expect(ThumbnailLayout.capacity(in: CGRect(x: 0, y: 0, width: 800, height: 120)) == 1)
  }

  @Test func panelLeavesRoomForShadowAndReachesTheEdge() {
    let cardFrame = ThumbnailLayout.cardFrame(slot: 0, corner: .bottomRight, in: laptop)
    let panel = ThumbnailLayout.panelFrame(forCard: cardFrame)
    #expect(panel.contains(cardFrame))
    #expect(panel.maxX >= laptop.maxX)
    let leftPanel = ThumbnailLayout.panelFrame(forCard: ThumbnailLayout.cardFrame(slot: 0, corner: .topLeft, in: laptop))
    #expect(leftPanel.minX <= laptop.minX)
  }

  @Test func offscreenOffsetPointsAtTheNearestEdge() {
    #expect(ThumbnailLayout.offscreenOffset(for: .bottomRight) > card.width)
    #expect(ThumbnailLayout.offscreenOffset(for: .topLeft) < -card.width)
  }

  @Test func newestGetsSlotZero() {
    #expect(ThumbnailLayout.slots(oldestFirst: ["a", "b", "c"]) == ["c": 0, "b": 1, "a": 2])
  }

  @Test func evictionsDropOldestUnpinnedFirst() {
    let ids = ["a", "b", "c", "d", "e"]
    #expect(ThumbnailLayout.evictions(oldestFirst: ids, pinned: [], capacity: 4) == ["a"])
    #expect(ThumbnailLayout.evictions(oldestFirst: ids, pinned: ["a"], capacity: 3) == ["b", "c"])
    #expect(ThumbnailLayout.evictions(oldestFirst: ["a", "b"], pinned: ["a", "b"], capacity: 1) == ["a"])
    #expect(ThumbnailLayout.evictions(oldestFirst: ids, pinned: [], capacity: 5).isEmpty)
  }
}

@Suite("Capture thumbnail auto-dismiss")
struct CaptureThumbnailClockTests {
  let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

  @Test func expiresAfterTheDelay() {
    let clock = ThumbnailDismissClock(delay: 6, start: t0)
    #expect(!clock.isExpired(at: t0.addingTimeInterval(5.9)))
    #expect(clock.isExpired(at: t0.addingTimeInterval(6)))
  }

  @Test func hoverPausesAndResumesWithWhatWasLeft() {
    var clock = ThumbnailDismissClock(delay: 6, start: t0)
    clock.hold(.hover, at: t0.addingTimeInterval(1))
    #expect(clock.isPaused)
    #expect(!clock.isExpired(at: t0.addingTimeInterval(500)))
    clock.release(.hover, at: t0.addingTimeInterval(100))
    #expect(clock.deadline == t0.addingTimeInterval(105))
  }

  @Test func resumingAlwaysLeavesAGracePeriod() {
    var clock = ThumbnailDismissClock(delay: 6, start: t0)
    clock.hold(.hover, at: t0.addingTimeInterval(5.5))
    clock.release(.hover, at: t0.addingTimeInterval(10))
    #expect(clock.deadline == t0.addingTimeInterval(10 + ThumbnailDismissClock.resumeGrace))
  }

  @Test func pinKeepsItOpenAfterHoverEnds() {
    var clock = ThumbnailDismissClock(delay: 6, start: t0)
    clock.hold(.pin, at: t0)
    clock.hold(.hover, at: t0)
    clock.release(.hover, at: t0.addingTimeInterval(1))
    #expect(clock.isPaused)
    #expect(!clock.isExpired(at: t0.addingTimeInterval(1_000)))
    clock.release(.pin, at: t0.addingTimeInterval(2))
    #expect(clock.isExpired(at: t0.addingTimeInterval(8)))
  }

  @Test func releasingSomethingNotHeldChangesNothing() {
    var clock = ThumbnailDismissClock(delay: 6, start: t0)
    let before = clock
    clock.release(.drag, at: t0.addingTimeInterval(3))
    #expect(clock == before)
  }

  @Test func zeroDelayNeverCloses() {
    var clock = ThumbnailDismissClock(delay: 0, start: t0)
    #expect(clock.deadline == nil)
    clock.hold(.hover, at: t0)
    clock.release(.hover, at: t0)
    #expect(!clock.isExpired(at: .distantFuture))
  }

  @Test func restartGivesTheFullDelayAgain() {
    var clock = ThumbnailDismissClock(delay: 6, start: t0)
    clock.restart(at: t0.addingTimeInterval(5))
    #expect(clock.deadline == t0.addingTimeInterval(11))
  }
}

@Suite("Capture thumbnail gestures and policy")
struct CaptureThumbnailGestureTests {
  @Test func smallMovesAreStillClicks() {
    #expect(ThumbnailGesture.intent(translation: CGSize(width: 3, height: 2), corner: .bottomRight) == .undecided)
  }

  @Test func flickTowardTheEdgeIsASwipe() {
    #expect(ThumbnailGesture.intent(translation: CGSize(width: 20, height: 4), corner: .bottomRight) == .swipe)
    #expect(ThumbnailGesture.intent(translation: CGSize(width: -20, height: 4), corner: .topLeft) == .swipe)
  }

  @Test func dragInwardOrUpwardMovesTheFile() {
    #expect(ThumbnailGesture.intent(translation: CGSize(width: -20, height: 4), corner: .bottomRight) == .fileDrag)
    #expect(ThumbnailGesture.intent(translation: CGSize(width: 6, height: 30), corner: .bottomRight) == .fileDrag)
    #expect(ThumbnailGesture.intent(translation: CGSize(width: 20, height: 0), corner: .bottomLeft) == .fileDrag)
  }

  @Test func swipeFollowsOutwardAndRubberBandsInward() {
    #expect(ThumbnailGesture.swipeOffset(translationX: 50, corner: .bottomRight) == 50)
    #expect(ThumbnailGesture.swipeOffset(translationX: -50, corner: .bottomRight) == -10)
    #expect(ThumbnailGesture.swipeOffset(translationX: -50, corner: .bottomLeft) == -50)
  }

  @Test func swipeDismissesWhenFarOrFast() {
    #expect(ThumbnailGesture.swipeDismisses(offset: 90, velocity: 0, corner: .bottomRight))
    #expect(ThumbnailGesture.swipeDismisses(offset: 20, velocity: 900, corner: .bottomRight))
    #expect(!ThumbnailGesture.swipeDismisses(offset: 30, velocity: 100, corner: .bottomRight))
    #expect(ThumbnailGesture.swipeDismisses(offset: -90, velocity: 0, corner: .topLeft))
    #expect(!ThumbnailGesture.swipeDismisses(offset: 90, velocity: 0, corner: .topLeft))
  }

  @Test func whichActionsShowAThumbnail() {
    for action in [OverlayAction.copy, .save, .upload, .share] {
      #expect(ThumbnailPolicy.presents(action, copyAfterSelection: false, enabled: true))
    }
    #expect(!ThumbnailPolicy.presents(.print, copyAfterSelection: true, enabled: true))
    #expect(ThumbnailPolicy.presents(.confirm, copyAfterSelection: true, enabled: true))
    #expect(!ThumbnailPolicy.presents(.confirm, copyAfterSelection: false, enabled: true))
    #expect(!ThumbnailPolicy.presents(.copy, copyAfterSelection: true, enabled: false))
  }
}

@Suite("Capture thumbnail settings")
struct CaptureThumbnailSettingsTests {
  private func isolated() -> AppSettings {
    AppSettings(defaults: UserDefaults(suiteName: "QS-Thumb-\(UUID().uuidString)")!)
  }

  @Test func defaults() {
    let settings = isolated()
    #expect(settings.captureThumbnailEnabled)
    #expect(settings.captureThumbnailCorner == .bottomRight)
    #expect(settings.captureThumbnailAutoClose == 6)
  }

  @Test func valuesPersistAndClamp() {
    let settings = isolated()
    settings.captureThumbnailEnabled = false
    settings.captureThumbnailCorner = .topLeft
    settings.captureThumbnailAutoClose = 500
    #expect(!settings.captureThumbnailEnabled)
    #expect(settings.captureThumbnailCorner == .topLeft)
    #expect(settings.captureThumbnailAutoClose == 60)
    settings.captureThumbnailAutoClose = -4
    #expect(settings.captureThumbnailAutoClose == 0)
  }

  @Test func delayChoicesIncludeNever() {
    #expect(AppSettings.captureThumbnailDelayChoices.contains(6))
    #expect(AppSettings.captureThumbnailDelayChoices.last == 0)
  }

  @Test func cornerGeometryFlags() {
    #expect(ThumbnailCorner.bottomRight.isRight && ThumbnailCorner.bottomRight.isBottom)
    #expect(!ThumbnailCorner.topLeft.isRight && !ThumbnailCorner.topLeft.isBottom)
    #expect(ThumbnailCorner.bottomLeft.outward == -1)
  }
}

@MainActor
@Suite("Capture thumbnail saving")
struct CaptureThumbnailSaverTests {
  private func tempFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("QS-ThumbSave-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func uniqueNamesCountUp() throws {
    let folder = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let first = ThumbnailSaver.uniqueURL(in: folder, baseName: "Shot", ext: "png")
    #expect(first.lastPathComponent == "Shot.png")
    try Data([1]).write(to: first)
    #expect(ThumbnailSaver.uniqueURL(in: folder, baseName: "Shot", ext: "png").lastPathComponent == "Shot 2.png")
  }

  @Test func saveWritesIntoTheFolderAndRecordsHistory() throws {
    let folder = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    var recorded: [HistoryEntry] = []
    let url = try #require(ThumbnailSaver.save(ThumbnailFixtures.image(), to: folder, record: { recorded.append($0) }))
    #expect(url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(recorded.count == 1)
  }

  @Test func dragFileIsAPNGOnDisk() throws {
    let url = try #require(ThumbnailSaver.dragFile(for: ThumbnailFixtures.image()))
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    #expect(url.pathExtension == "png")
    #expect(NSImage(contentsOf: url) != nil)
  }

  @Test func saveFolderFallsBackToTheDesktop() {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "QS-ThumbFolder-\(UUID().uuidString)")!)
    #expect(ThumbnailSaver.saveFolder(settings: settings).lastPathComponent == "Desktop")
    let chosen = URL(fileURLWithPath: "/tmp/QS-Chosen", isDirectory: true)
    settings.defaultSaveFolder = chosen
    #expect(ThumbnailSaver.saveFolder(settings: settings).standardizedFileURL.path == chosen.standardizedFileURL.path)
  }
}

enum ThumbnailFixtures {
  /// A small capture-like image: a window with a title bar and a few text lines.
  static func image(size: CGSize = CGSize(width: 320, height: 200)) -> NSImage {
    NSImage(size: size, flipped: false) { rect in
      NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.96, alpha: 1).setFill()
      rect.fill()
      NSColor(calibratedWhite: 0.85, alpha: 1).setFill()
      CGRect(x: 0, y: rect.height - 26, width: rect.width, height: 26).fill()
      for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
        color.setFill()
        NSBezierPath(ovalIn: CGRect(x: 10 + CGFloat(index) * 16, y: rect.height - 18, width: 10, height: 10)).fill()
      }
      NSColor.systemBlue.withAlphaComponent(0.85).setFill()
      NSBezierPath(roundedRect: CGRect(x: 18, y: rect.height - 70, width: rect.width * 0.45, height: 22), xRadius: 5, yRadius: 5).fill()
      NSColor(calibratedWhite: 0.6, alpha: 1).setFill()
      for line in 0..<5 {
        let width = rect.width * (line % 2 == 0 ? 0.78 : 0.6)
        NSBezierPath(roundedRect: CGRect(x: 18, y: rect.height - 100 - CGFloat(line) * 18, width: width, height: 8), xRadius: 4, yRadius: 4).fill()
      }
      return true
    }
  }
}
