import AppKit
import Foundation
import SQLite3
import Testing

@testable import Brim

private func item(pinned: Bool = false, age: TimeInterval = 0, now: Date = .now) -> FileTrayItem {
  FileTrayItem(
    id: UUID(), addedAt: now.addingTimeInterval(-age), bookmark: Data(), path: "/tmp/x-\(UUID().uuidString)",
    pinned: pinned)
}

struct TrayPolicyTests {
  @Test func routingFollowsPlacement() {
    #expect(TrayRouting.islandDrop(.notch) == .notchTray)
    #expect(TrayRouting.islandDrop(.both) == .notchTray)
    #expect(TrayRouting.islandDrop(.floating) == .floatingTray)
    #expect(TrayRouting.shakeOpensFloatingTray(.notch) == false)
    #expect(TrayRouting.shakeOpensFloatingTray(.floating))
    #expect(TrayRouting.shakeOpensFloatingTray(.both) == false)
  }

  @Test func openAfterDropNeedsBothTheSettingAndTheNotchTray() {
    #expect(TrayRouting.opensIslandAfterDrop(placement: .both, openAfterDrop: true))
    #expect(!TrayRouting.opensIslandAfterDrop(placement: .both, openAfterDrop: false))
    #expect(!TrayRouting.opensIslandAfterDrop(placement: .floating, openAfterDrop: true))
  }

  @Test func pinnedItemsLeadAndSurviveTheCap() {
    let a = item(), b = item(pinned: true), c = item(), d = item(pinned: true)
    let arranged = FileTrayOrdering.arranged([a, b, c, d])
    #expect(arranged.map(\.id) == [b.id, d.id, a.id, c.id])
    #expect(FileTrayOrdering.arranged([a, c, b], limit: 2).map(\.id) == [b.id, a.id])
  }

  @Test func retentionKeepsPinnedAndKnowsShortWindows() {
    let now = Date()
    let old = item(age: 90_000, now: now), pinnedOld = item(pinned: true, age: 90_000, now: now)
    let fresh = item(age: 60, now: now)
    #expect(FileTrayRetention.kept([old, pinnedOld, fresh], retention: .day, now: now).map(\.id) == [pinnedOld.id, fresh.id])
    #expect(FileTrayRetention.kept([fresh], retention: .fiveMinutes, now: now).count == 1)
    #expect(FileTrayRetention.kept([item(age: 400, now: now)], retention: .fiveMinutes, now: now).isEmpty)
    #expect(FileTrayRetention.month.interval == 2_592_000)
  }

  @Test func dragOutRemovesOnlyWhenEnabledAwayFromTraysAndUnpinned() {
    #expect(DragOutPolicy.shouldRemove(enabled: true, releasedOnTray: false, pinned: false))
    #expect(!DragOutPolicy.shouldRemove(enabled: false, releasedOnTray: false, pinned: false))
    #expect(!DragOutPolicy.shouldRemove(enabled: true, releasedOnTray: true, pinned: false))
    #expect(!DragOutPolicy.shouldRemove(enabled: true, releasedOnTray: false, pinned: true))
  }

  @Test func syncOnlyChangesTraysThatDiffer() {
    let a = URL(fileURLWithPath: "/a"), b = URL(fileURLWithPath: "/b")
    #expect(TraySync.mirror(source: [a], target: [a]) == nil)
    #expect(TraySync.mirror(source: [a, b], target: [a]) == [a, b])
    #expect(TraySync.mirror(source: [], target: [a]) == [])
  }

  @MainActor @Test func basketModelReplaceIsIdempotent() {
    let model = BasketModel()
    let a = URL(fileURLWithPath: "/a")
    model.replace(with: [a])
    #expect(model.urls == [a])
    model.replace(with: [a])
    model.replace(with: [])
    #expect(model.urls.isEmpty)
  }

  @Test func legacyTrayJSONDecodesAsUnpinned() throws {
    let legacy = """
      [{"id":"\(UUID().uuidString)","addedAt":0,"bookmark":"","path":"/tmp/legacy"}]
      """
    let items = try JSONDecoder().decode([FileTrayItem].self, from: Data(legacy.utf8))
    #expect(items.count == 1 && items[0].pinned == false)
    let round = try JSONDecoder().decode([FileTrayItem].self, from: JSONEncoder().encode([item(pinned: true)]))
    #expect(round[0].pinned)
  }

  @Test func settingsDefaultsKeepTodaysBehavior() {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "qs-tray-\(UUID())")!)
    #expect(settings.trayPlacement == .both)
    #expect(settings.trayOpenAfterDrop)
    #expect(!settings.trayProtectOriginals && !settings.trayRemoveAfterDragOut && !settings.floatingTraySync)
    settings.trayPlacement = .floating
    settings.trackedFolderPaths = ["/a", "/b", "/a"]
    #expect(settings.trayPlacement == .floating)
    #expect(settings.trackedFolderPaths == ["/a", "/b"])
    settings.transformTrashOriginals = true
    #expect(settings.transformOutputPolicy.moveOriginalsToTrash)
    settings.trayProtectOriginals = true
    #expect(!settings.transformOutputPolicy.moveOriginalsToTrash)
  }
}

@MainActor
@Suite(.serialized)
struct TrayStoreGapTests {
  private let root = FileManager.default.temporaryDirectory.appendingPathComponent("QS-TrayGap-\(UUID().uuidString)")

  private func file(_ name: String) throws -> URL {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent(name)
    try Data("x".utf8).write(to: url)
    return url
  }

  @Test func pinTogglesPersistsAndOrders() throws {
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = root.appendingPathComponent("s")
    let store = FileTrayStore(directory: storage)
    store.add([try file("a.txt"), try file("b.txt")])
    let last = try #require(store.items.last)
    store.togglePin([last.id])
    #expect(store.items.first?.id == last.id && store.items.first?.pinned == true)
    let reloaded = FileTrayStore(directory: storage)
    #expect(reloaded.items.first?.pinned == true)
    reloaded.togglePin([last.id])
    #expect(reloaded.items.allSatisfy { !$0.pinned })
  }

  @Test func pinnedItemsOutliveRetention() throws {
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTrayStore(directory: root.appendingPathComponent("s"), retention: { .hour })
    store.add([try file("a.txt"), try file("b.txt")], now: .now.addingTimeInterval(-7_200))
    store.togglePin([store.items[0].id])
    #expect(store.pruneExpired() == 1)
    #expect(store.items.count == 1 && store.items[0].pinned)
  }

  @Test func renameCopiesWhenOriginalsAreProtected() throws {
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try file("old.txt")
    let store = FileTrayStore(directory: root.appendingPathComponent("s"), protectOriginals: { true })
    store.add([source])
    store.rename(store.items[0], to: "new.txt")
    #expect(FileManager.default.fileExists(atPath: source.path))
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("new.txt").path))
    #expect(store.url(for: store.items[0]).lastPathComponent == "new.txt")
  }

  @Test func renameMovesWhenNotProtected() throws {
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try file("old.txt")
    let store = FileTrayStore(directory: root.appendingPathComponent("s"))
    store.add([source])
    store.rename(store.items[0], to: "new.txt")
    #expect(!FileManager.default.fileExists(atPath: source.path))
  }

  @Test func protectiveDragCopyLeavesTheOriginalAndGoesStale() throws {
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try file("keep.txt")
    let copy = try #require(TrayDragOut.protectedCopy(of: source))
    #expect(copy != source && copy.lastPathComponent == "keep.txt")
    #expect(FileManager.default.fileExists(atPath: copy.path))
    let scratch = copy.deletingLastPathComponent().deletingLastPathComponent()
    TrayDragOut.removeStale(in: scratch, now: .now.addingTimeInterval(7_200))
    #expect(!FileManager.default.fileExists(atPath: copy.path))
  }
}

struct TrackedFolderTests {
  @Test func ignoresHiddenAndPartialFiles() {
    for name in [".DS_Store", "~$doc.docx", "a.crdownload", "b.download", "c.part", "d.TMP"] {
      #expect(TrackedFolderScan.isIgnorable(name), "\(name)")
    }
    #expect(!TrackedFolderScan.isIgnorable("report.pdf"))
  }

  @Test func reportsOnlyUnknownNames() {
    let current = ["a.png", "b.png", ".hidden", "c.part"].map { URL(fileURLWithPath: "/f/\($0)") }
    let fresh = TrackedFolderScan.newFiles(current: current, known: ["a.png"])
    #expect(fresh.map(\.lastPathComponent) == ["b.png"])
  }

  @Test func watchableKeepsExistingFoldersOnce() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("QS-W-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(TrackedFolderScan.watchable([folder.path, folder.path, "/nope/missing"]) == [folder.path])
  }
}

struct MailAppChoiceTests {
  @Test func routesToTheChosenInstalledApp() {
    #expect(MailAppChoice.route(chosen: "", installed: ["com.readdle.smartemail-Mac"]) == .sharingService)
    #expect(MailAppChoice.route(chosen: "com.apple.mail", installed: ["com.apple.mail"]) == .sharingService)
    #expect(MailAppChoice.route(chosen: "com.x.gone", installed: ["com.apple.mail"]) == .sharingService)
    #expect(MailAppChoice.route(chosen: "com.readdle.smartemail-Mac", installed: ["com.readdle.smartemail-Mac"])
      == .openWith(bundleID: "com.readdle.smartemail-Mac"))
  }
}
