import Foundation
import Testing

@testable import Brim

@MainActor
@Suite(.serialized)
struct TransformTrayTests {
  private func item(age: TimeInterval, now: Date) -> FileTrayItem {
    FileTrayItem(id: UUID(), addedAt: now.addingTimeInterval(-age), bookmark: Data(), path: "/tmp/x-\(UUID().uuidString)")
  }

  @Test func retentionKeepsOnlyRecentReferences() {
    let now = Date()
    let items = [item(age: 60, now: now), item(age: 7_200, now: now), item(age: 100_000, now: now), item(age: 700_000, now: now)]
    #expect(FileTrayRetention.kept(items, retention: .never, now: now).count == 4)
    #expect(FileTrayRetention.kept(items, retention: .hour, now: now).count == 1)
    #expect(FileTrayRetention.kept(items, retention: .day, now: now).count == 2)
    #expect(FileTrayRetention.kept(items, retention: .week, now: now).count == 3)
  }

  @Test func storePrunesStaleItemsAndLeavesFilesAlone() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("QS-Ret-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let old = root.appendingPathComponent("old.txt"), fresh = root.appendingPathComponent("fresh.txt")
    try "o".write(to: old, atomically: true, encoding: .utf8)
    try "f".write(to: fresh, atomically: true, encoding: .utf8)
    let storage = root.appendingPathComponent("storage")
    var setting = FileTrayRetention.never
    let store = FileTrayStore(directory: storage, flashes: nil, retention: { setting })
    store.add([old], now: Date().addingTimeInterval(-3 * 86_400))
    store.add([fresh])
    #expect(store.items.count == 2)
    #expect(store.pruneExpired() == 0)
    setting = .day
    #expect(store.pruneExpired() == 1)
    #expect(store.items.map { store.url(for: $0).lastPathComponent } == ["fresh.txt"])
    #expect(FileManager.default.fileExists(atPath: old.path))
    // The pruned list is what comes back after a relaunch, and a stale one is pruned on load.
    #expect(FileTrayStore(directory: storage, flashes: nil, retention: { setting }).items.count == 1)
    setting = .hour
    store.add([old], now: Date().addingTimeInterval(-7_200))
    #expect(FileTrayStore(directory: storage, flashes: nil, retention: { .hour }).items.count == 1)
  }

  @Test func shakesOpenMoreTraysUpToTheLimit() {
    #expect(FloatingTrayPolicy.onShake(openTrays: 0, multiple: false) == .createNew)
    #expect(FloatingTrayPolicy.onShake(openTrays: 1, multiple: false) == .reuseLatest)
    #expect(FloatingTrayPolicy.onShake(openTrays: 1, multiple: true) == .createNew)
    #expect(FloatingTrayPolicy.onShake(openTrays: 3, multiple: true) == .createNew)
    #expect(FloatingTrayPolicy.onShake(openTrays: 4, multiple: true) == .reuseLatest)
  }

  @Test func oneDragShakesOnlyOnce() {
    var gate = DragShakeGate()
    let results = [7, 7, 7, 8].map { gate.admit(drag: $0) }
    #expect(results == [true, false, false, true])
  }

  @Test func quickActionTileUnderThePoint() {
    let targets: [DropTarget] = [.keep, .convert, .airDrop]
    let pad = FloatingTrayLayout.padding, row = FloatingTrayLayout.tileHeight + FloatingTrayLayout.tileSpacing
    let width = FloatingTrayLayout.width
    #expect(FloatingTrayLayout.target(at: CGPoint(x: pad + 10, y: pad + 10), in: targets) == .keep)
    #expect(FloatingTrayLayout.target(at: CGPoint(x: width - pad - 10, y: pad + 10), in: targets) == .convert)
    // The odd last tile spans its row, so either half picks it.
    #expect(FloatingTrayLayout.target(at: CGPoint(x: width - pad - 10, y: pad + row + 10), in: targets) == .airDrop)
    #expect(FloatingTrayLayout.target(at: CGPoint(x: pad + 10, y: pad + row + 10), in: targets) == .airDrop)
    #expect(FloatingTrayLayout.target(at: CGPoint(x: -1, y: 20), in: targets) == nil)
    #expect(FloatingTrayLayout.target(at: CGPoint(x: 20, y: 20), in: []) == nil)
  }

  @Test func temporaryDropsAreCopiedSomewhereLasting() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("keeper-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let temporary = root.appendingPathComponent("T"), lasting = root.appendingPathComponent("Kept")
    let elsewhere = root.appendingPathComponent("Desktop/b.png")
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: elsewhere.deletingLastPathComponent(), withIntermediateDirectories: true)
    let screenshot = temporary.appendingPathComponent("Screenshot.png")
    try Data([1, 2, 3]).write(to: screenshot)
    try Data([4]).write(to: elsewhere)

    let kept = DroppedFileKeeper.lasting([screenshot, elsewhere], temporary: temporary, folder: lasting)
    #expect(kept[0].path.hasPrefix(lasting.path) && kept[0].lastPathComponent == "Screenshot.png")
    #expect(try Data(contentsOf: kept[0]) == Data([1, 2, 3]))
    #expect(kept[1] == elsewhere)
    // The temporary original going away no longer loses the file.
    try FileManager.default.removeItem(at: screenshot)
    #expect(FileManager.default.fileExists(atPath: kept[0].path))
  }

  @Test func keptCopiesTakeTheSuggestedName() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("keeper-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let promised = root.appendingPathComponent("tmp-1234.png")
    try Data([9]).write(to: promised)
    let folder = root.appendingPathComponent("Kept")
    #expect(DroppedFileKeeper.keep(promised, named: "Screenshot 1", folder: folder)?.lastPathComponent == "Screenshot 1.png")
    #expect(DroppedFileKeeper.keep(promised, named: "Screenshot 2.PNG", folder: folder)?.lastPathComponent == "Screenshot 2.PNG")
    #expect(DroppedFileKeeper.keep(promised, folder: folder)?.lastPathComponent == "tmp-1234.png")
  }

  @Test func newTraysCascadeAndStayOnScreen() {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let size = CGSize(width: 280, height: 190)
    let first = FloatingTrayPolicy.origin(near: CGPoint(x: 300, y: 400), size: size, index: 0, bounds: bounds)
    let second = FloatingTrayPolicy.origin(near: CGPoint(x: 300, y: 400), size: size, index: 1, bounds: bounds)
    #expect(second.x > first.x && second.y < first.y)
    let edge = FloatingTrayPolicy.origin(near: CGPoint(x: 990, y: 5), size: size, index: 3, bounds: bounds)
    #expect(edge.x <= bounds.maxX - size.width && edge.y >= bounds.minY)
  }

  @Test func shakeSensitivityScalesTheThresholds() {
    let balanced = JiggleDetector(sensitivity: 3)
    #expect(balanced.minimumSwing == JiggleDetector().minimumSwing)
    #expect(JiggleDetector(sensitivity: 1).minimumSwing > balanced.minimumSwing)
    #expect(JiggleDetector(sensitivity: 5).minimumSwing < balanced.minimumSwing)
    #expect(JiggleDetector(sensitivity: 99).minimumSwing == JiggleDetector(sensitivity: 5).minimumSwing)
    // A modest wiggle trips high sensitivity but not low.
    func trips(_ level: Int) -> Bool {
      var detector = JiggleDetector(sensitivity: level)
      var fired = false
      for (step, x) in [0.0, 25, 0, 25, 0, 25].enumerated() { fired = detector.add(x: x, time: Double(step) * 0.05) || fired }
      return fired
    }
    #expect(trips(5))
    #expect(!trips(1))
  }

  @Test func quickActionExtrasAreSanitizedAndPersisted() {
    #expect(DropTarget.sanitizedExtras([.keep, .convert, .airDrop, .airDrop, .zip]) == [.airDrop, .zip])
    #expect(DropTarget.sanitizedExtras(DropTarget.optional).count == AppSettings.maximumQuickActionExtras)
    let suite = UserDefaults(suiteName: "QS-Transform-\(UUID().uuidString)")!
    let settings = AppSettings(defaults: suite)
    #expect(settings.quickActionTargets == [.keep, .convert, .airDrop])
    settings.quickActionExtras = [.mail, .copy]
    #expect(settings.quickActionTargets == [.keep, .convert, .mail, .copy])
    settings.quickActionExtras = []
    #expect(settings.quickActionTargets == [.keep, .convert])
  }

  @Test func transformSettingsRoundTrip() {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "QS-Transform-\(UUID().uuidString)")!)
    #expect(settings.transformOutputPolicy == TransformOutputPolicy())
    #expect(!settings.transformTrashOriginals)
    settings.transformDestination = .downloads
    settings.transformTrashOriginals = true
    settings.trayRetention = .week
    settings.shakeSensitivity = 99
    #expect(settings.transformOutputPolicy.destination == .downloads)
    #expect(settings.transformOutputPolicy.moveOriginalsToTrash)
    #expect(settings.trayRetention == .week)
    #expect(settings.shakeSensitivity == 5)
    var preset = TransformPreset.chatGIF
    preset.id = "mine"
    preset.isBuiltIn = false
    settings.transformUserPresets = [preset, TransformPreset.lightPDF]
    #expect(settings.transformUserPresets.map(\.id) == ["mine"])
  }

  @Test func panelModelPicksSensibleDefaultsAndRunsPresets() async throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let image = try fixtures.image("m.jpg")
    let model = TransformPanelModel(files: [image], settings: AppSettings(defaults: UserDefaults(suiteName: "QS-Panel-\(UUID().uuidString)")!))
    #expect(model.operation == .compress)
    #expect(model.groups == [.size, .format, .edit, .files])
    #expect(model.presets.map(\.id).contains("builtin.web"))
    model.apply(TransformPreset.webReady())
    #expect(model.options.limitLongestSide && model.options.stripMetadata)
    model.select(.zip)
    #expect(model.group == .files)
    model.select(.splitPDF)  // not available for an image
    #expect(model.operation == .zip)
    model.select(.compress)
    model.options.imageQuality = 0.3
    model.run()
    for _ in 0..<100 where model.phase != .finished { try await Task.sleep(for: .milliseconds(50)) }
    #expect(model.phase == .finished)
    let result = try #require(model.results.first)
    // Web ready picks WebP when this Mac can write it (natively or through an installed cwebp).
    let expected = TransformPreset.webReady().options.imageFormat == .webp ? "webp" : "jpg"
    #expect(result.lastPathComponent == "m-compressed.\(expected)")
    #expect(model.totalSummary?.contains("→") == true)
  }
}
