import Foundation
import Testing

@testable import Brim

/// A temp folder with two vault folders and an Obsidian-style vault registry.
private struct Fixture {
  let dir: URL
  let first: URL
  let second: URL
  var config: URL { dir.appendingPathComponent("obsidian.json") }

  init() throws {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent("obsidian-link-\(UUID().uuidString)")
    first = dir.appendingPathComponent("first")
    second = dir.appendingPathComponent("second")
    for vault in [first, second] {
      try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
      try "# \(vault.lastPathComponent)".write(to: vault.appendingPathComponent("Note.md"), atomically: true, encoding: .utf8)
    }
  }

  /// Writes the registry; `open` names the vault Obsidian has open.
  func register(open: URL?, extra: String = "") throws {
    func entry(_ url: URL, ts: Int) -> String {
      #""\#(url.lastPathComponent)":{"path":"\#(url.path)","ts":\#(ts),"open":\#(url == open)}"#
    }
    let json = #"{"vaults":{\#(entry(first, ts: 1_000)),\#(entry(second, ts: 2_000))\#(extra)}}"#
    try json.write(to: config, atomically: true, encoding: .utf8)
  }

  func cleanUp() { try? FileManager.default.removeItem(at: dir) }
}

struct ObsidianAppLinkTests {
  @Test func knownVaultsPutTheOpenVaultFirstThenNewest() throws {
    let fx = try Fixture()
    defer { fx.cleanUp() }
    try fx.register(open: fx.first)
    #expect(ObsidianAppLink.knownVaults(configURL: fx.config).map(\.name) == ["first", "second"])
    try fx.register(open: nil)
    #expect(ObsidianAppLink.knownVaults(configURL: fx.config).map(\.name) == ["second", "first"])
  }

  @Test func knownVaultsSkipMissingFoldersAndBadFiles() throws {
    let fx = try Fixture()
    defer { fx.cleanUp() }
    try fx.register(open: nil, extra: #","gone":{"path":"/nope/missing-vault","ts":9999,"open":true}"#)
    #expect(ObsidianAppLink.knownVaults(configURL: fx.config).map(\.name) == ["second", "first"])
    try "not json".write(to: fx.config, atomically: true, encoding: .utf8)
    #expect(ObsidianAppLink.knownVaults(configURL: fx.config).isEmpty)
    #expect(ObsidianAppLink.knownVaults(configURL: fx.dir.appendingPathComponent("absent.json")).isEmpty)
  }

  @Test func openURLPointsAtTheNoteFile() throws {
    let root = URL(fileURLWithPath: "/Users/me/my brain")
    let url = try #require(ObsidianAppLink.openURL(vaultRoot: root, relativePath: "Proiecte/a b.md"))
    #expect(url.scheme == "obsidian" && url.host == "open")
    let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "path" }?.value
    #expect(path == "/Users/me/my brain/Proiecte/a b.md")
  }
}

@MainActor
struct ObsidianModelLinkTests {
  @Test func connectsToTheOpenVaultAndFollowsSwitches() throws {
    let fx = try Fixture()
    defer { fx.cleanUp() }
    try fx.register(open: fx.first)
    let model = ObsidianModel(vaultPath: nil, obsidianConfig: fx.config)
    #expect(model.followsObsidian)
    #expect(model.vault?.name == "first")
    #expect(model.files.map(\.relativePath) == ["Note.md"])

    try fx.register(open: fx.second)
    model.reload()
    #expect(model.vault?.name == "second")
    #expect(model.selectedPath == nil)
  }

  @Test func aHandPickedVaultIsNotOverridden() throws {
    let fx = try Fixture()
    defer { fx.cleanUp() }
    try fx.register(open: fx.second)
    let model = ObsidianModel(vaultPath: fx.first.path, obsidianConfig: fx.config)
    #expect(!model.followsObsidian)
    model.reload()
    #expect(model.vault?.name == "first")
    #expect(model.knownVaults.map(\.name) == ["second", "first"])
  }

  @Test func rendersLinkedVaultPanel() async throws {
    let fx = try Fixture()
    defer { fx.cleanUp() }
    try "# Plan\n- [x] Import\n- [ ] Ship".write(
      to: fx.first.appendingPathComponent("Plan.md"), atomically: true, encoding: .utf8)
    try fx.register(open: fx.first)
    let model = ObsidianModel(vaultPath: nil, obsidianConfig: fx.config)
    model.select("Plan.md")
    _ = try await ProductivityRenderTests.render(NotesPanelView(obsidian: model, mode: .obsidian), name: "obsidian-linked")
    let empty = ObsidianModel(vaultPath: nil, obsidianConfig: nil)
    _ = try await ProductivityRenderTests.render(NotesPanelView(obsidian: empty, mode: .obsidian), name: "obsidian-none")
  }

  @Test func noRegistryMeansNoVault() {
    let model = ObsidianModel(vaultPath: nil, obsidianConfig: nil)
    #expect(model.vault == nil)
    #expect(model.knownVaults.isEmpty)
  }
}
