import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Logic of the four island apps (Emoji Picker, Launcher, Cleaner, Menu Bar), run against temp fixtures.
@MainActor
@Suite(.serialized)
struct IslandDropletAppsTests {
  // MARK: Cleaner fixtures

  private struct Fixture {
    let root: URL
    let home: URL
    let trash: URL
    let apps: [InstalledApp]
    var model: CleanerModel
  }

  private func fixture() throws -> Fixture {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("island-cleaner-\(UUID().uuidString)")
    let home = root.appendingPathComponent("me")
    let trash = root.appendingPathComponent("trash")
    try fm.createDirectory(at: trash, withIntermediateDirectories: true)
    let lib = home.appendingPathComponent("Library")
    for path in [
      "Application Support/com.example.Slack", "Caches/com.example.Slack", "Caches/Slack", "Containers/com.example.Slack",
      "Logs/Slack", "Caches/Spotify", "Caches/com.apple.Safari", "Applications/Slack.app",
    ] {
      try fm.createDirectory(at: path.hasPrefix("Applications") ? home.appendingPathComponent(path) : lib.appendingPathComponent(path), withIntermediateDirectories: true)
    }
    try Data(repeating: 1, count: 4_000_000).write(to: lib.appendingPathComponent("Application Support/com.example.Slack/db"))
    try Data(repeating: 1, count: 900_000).write(to: lib.appendingPathComponent("Caches/com.example.Slack/blob"))
    try Data(repeating: 1, count: 90_000).write(to: lib.appendingPathComponent("Caches/Slack/x"))
    try Data(repeating: 1, count: 300_000).write(to: lib.appendingPathComponent("Caches/Spotify/x"))
    let slack = InstalledApp(name: "Slack", url: home.appendingPathComponent("Applications/Slack.app"), bundleID: "com.example.Slack")
    let others = ["Spotify", "Figma", "Notion", "Docker"].map {
      InstalledApp(name: $0, url: home.appendingPathComponent("Applications/\($0).app"), bundleID: "com.example.\($0)")
    }
    let model = CleanerModel(home: home, apps: [slack] + others) { url in
      try fm.moveItem(at: url, to: trash.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent))
    }
    return Fixture(root: root, home: home, trash: trash, apps: [slack] + others, model: model)
  }

  private func settle(_ model: CleanerModel) async throws {
    for _ in 0..<40 {
      if !model.isScanning { return }
      try await Task.sleep(for: .milliseconds(50))
    }
  }

  @Test func cleanerTicksNothingForYouAndMovesNothingWithoutConfirming() async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    f.model.choose(f.apps[0])
    try await settle(f.model)
    #expect(f.model.items.count >= 3)
    #expect(f.model.selected.isEmpty)
    #expect(!f.model.includeApp)
    #expect(f.model.selectionCount == 0)
    f.model.requestMove()  // nothing ticked: nothing to confirm
    #expect(!f.model.confirming)
    // A confirm without a request does nothing, even with items ticked.
    f.model.selectSuggested()
    f.model.confirmMove()
    #expect(FileManager.default.fileExists(atPath: f.home.appendingPathComponent("Library/Caches/com.example.Slack").path))
    #expect((try FileManager.default.contentsOfDirectory(atPath: f.trash.path)).isEmpty)
  }

  @Test func suggestedTicksOnlyBundleIdentifierMatches() async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    f.model.choose(f.apps[0])
    try await settle(f.model)
    f.model.selectSuggested()
    let ticked = f.model.items.filter { f.model.selected.contains($0.id) }
    #expect(!ticked.isEmpty)
    #expect(ticked.allSatisfy { $0.leftover.confidence == .bundleID })
    #expect(f.model.items.contains { $0.leftover.confidence == .name && !f.model.selected.contains($0.id) })
  }

  @Test func confirmedMoveSendsOnlyTickedItemsToTheTrash() async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    f.model.choose(f.apps[0])
    try await settle(f.model)
    let cache = try #require(f.model.items.first { $0.leftover.url.lastPathComponent == "com.example.Slack" && $0.leftover.category == "Caches" })
    f.model.toggle(cache)
    f.model.requestMove()
    #expect(f.model.confirming)
    #expect(f.model.selectionCount == 1)
    f.model.confirmMove()
    let fm = FileManager.default
    #expect(!fm.fileExists(atPath: cache.leftover.url.path))
    #expect(fm.fileExists(atPath: f.home.appendingPathComponent("Library/Application Support/com.example.Slack").path))
    #expect(fm.fileExists(atPath: f.home.appendingPathComponent("Applications/Slack.app").path))
    #expect(try fm.contentsOfDirectory(atPath: f.trash.path).count == 1)
    #expect(f.model.message?.isEmpty == false)
    #expect(!f.model.items.contains { $0.id == cache.id })
  }

  @Test func untickingAfterRequestCancelsTheConfirmation() async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    f.model.choose(f.apps[0])
    try await settle(f.model)
    f.model.selectSuggested()
    f.model.requestMove()
    #expect(f.model.confirming)
    f.model.toggle(f.model.items[0])
    #expect(!f.model.confirming)
    f.model.requestMove()
    f.model.cancelMove()
    f.model.confirmMove()
    #expect((try FileManager.default.contentsOfDirectory(atPath: f.trash.path)).isEmpty)
  }

  @Test func theAppItselfIsOptInAndMovedLast() async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    f.model.choose(f.apps[0])
    try await settle(f.model)
    f.model.toggleApp()
    #expect(f.model.includeApp && f.model.selectionCount == 1)
    f.model.requestMove()
    f.model.confirmMove()
    #expect(!FileManager.default.fileExists(atPath: f.home.appendingPathComponent("Applications/Slack.app").path))
    #expect(f.model.chosen == nil)  // back on the list, the app gone from it
    #expect(!f.model.filteredApps.contains { $0.name == "Slack" })
  }

  @Test func cachesNeverPreselectAndSkipApple() async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    f.model.switchMode(.caches)
    try await settle(f.model)
    let names = f.model.cacheItems.map(\.leftover.url.lastPathComponent)
    #expect(names.contains("Spotify") && !names.contains("com.apple.Safari"))
    #expect(f.model.selected.isEmpty)
    f.model.selectAll()
    #expect(f.model.selected.count == f.model.cacheItems.count)
    f.model.requestMove()
    f.model.confirmMove()
    #expect(f.model.cacheItems.isEmpty)
    #expect(FileManager.default.fileExists(atPath: f.home.appendingPathComponent("Library/Caches/com.apple.Safari").path))
  }

  // MARK: Emoji

  @Test func emojiCatalogCoversEveryCategoryOnThisMac() {
    let all = EmojiCatalog.all
    var counts: [EmojiCategory: Int] = [:]
    for item in all { counts[item.category, default: 0] += 1 }
    print("EMOJI total \(all.count): " + EmojiCategory.allCases.map { "\($0.rawValue)=\(counts[$0] ?? 0)" }.joined(separator: " "))
    for category in EmojiCategory.allCases { #expect((counts[category] ?? 0) > 20, "\(category) is nearly empty") }
    #expect(EmojiSearch.filter(all, query: "thumbs").contains { $0.character == "👍" })
    #expect(EmojiSearch.filter(all, query: "pizza").contains { $0.character == "🍕" })
  }

  @Test func emojiCatalogHasMultiPartEmojiAndFriendlyNames() {
    let all = EmojiCatalog.all
    let characters = Set(all.map(\.character))
    print("EMOJI sequences present: " + ["👩‍👩‍👧", "🏳️‍🌈", "1️⃣", "👨‍🍳", "🤦‍♀️", "❤️‍🔥", "🏴󠁧󠁢󠁥󠁮󠁧󠁿"].map { "\($0)=\(characters.contains($0))" }.joined(separator: " "))
    #expect(characters.contains("🏳️‍🌈") && characters.contains("1️⃣") && characters.contains("👨‍🍳"))
    #expect(all.contains { $0.character.unicodeScalars.contains { $0.value == 0x200D } && $0.category == .people })
    #expect(EmojiSearch.filter(all, query: "family").contains { $0.character.unicodeScalars.contains { $0.value == 0x200D } })
    let names = Dictionary(all.map { ($0.character, $0.displayName) }, uniquingKeysWith: { a, _ in a })
    #expect(names["☹\u{FE0F}"] == "Frowning Face")
    #expect(names["😀"] == "Grinning Face")
    #expect(names["👍"] == "Thumbs Up")
    #expect(names["⚡"] == "High Voltage")
    #expect(!all.contains { $0.displayName.lowercased().hasPrefix("white ") && $0.name.contains("face") })
    #expect(EmojiSkinTone.dark.apply(to: "👨‍🍳", supportsSkinTone: true) == "👨\u{1F3FF}‍🍳")
  }

  @Test func emojiIslandModelUsesTwelveColumnsAndPicks() {
    let settings = DropletRender.isolatedSettings()
    let model = EmojiPickerModel(settings: settings, columns: 12)
    var picked: String?
    model.onPick = { picked = $0 }
    model.query = "fire"
    model.queryChanged()
    model.pickSelected()
    #expect(picked == "🔥")
    #expect(model.recents.first == "🔥")
    #expect(model.columns == 12)
  }

  // MARK: Launcher

  @Test func launcherEmptyQueryAndExamplesWork() {
    let apps = ["Safari", "Slack"].map { InstalledApp(name: $0, url: URL(fileURLWithPath: "/Applications/\($0).app"), bundleID: nil) }
    let settings = DropletRender.isolatedSettings()
    let model = ThunderstormModel(settings: settings, apps: apps)
    #expect(model.results.isEmpty)  // empty box shows the example chips, not a wall of rows
    model.query = "12 * 8"
    #expect(model.results.first?.title == "96")
    model.query = "5 km in mi"
    #expect(model.results.first?.kind == .conversion)
    model.query = "saf"
    #expect(model.results.first?.title == "Safari")
  }

  @Test func launcherEnableTurnsTheSettingOn() {
    let settings = DropletRender.isolatedSettings()
    let state = LauncherEnabledState(settings: settings)
    #expect(!state.enabled)
    #expect(!settings.thunderstormEnabled)
  }
}
