import Foundation
import Testing

@testable import Brim

/// Installs from before the rename keep their data: folders and preferences move over once.
struct LegacyMigrationTests {
  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("LegacyMigrationTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func movesTheOldFolderIntoTheNewOneWithoutOverwriting() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let old = root.appendingPathComponent("Old"), new = root.appendingPathComponent("New")
    try FileManager.default.createDirectory(at: old.appendingPathComponent("Clipboard"), withIntermediateDirectories: true)
    try Data("history".utf8).write(to: old.appendingPathComponent("Clipboard/entries.json"))
    try Data("old".utf8).write(to: old.appendingPathComponent("shared.txt"))
    try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
    try Data("new".utf8).write(to: new.appendingPathComponent("shared.txt"))

    LegacyMigration.mergeFolder(from: old, into: new)

    #expect(try String(contentsOf: new.appendingPathComponent("Clipboard/entries.json"), encoding: .utf8) == "history")
    #expect(try String(contentsOf: new.appendingPathComponent("shared.txt"), encoding: .utf8) == "new")
    // What could not move stays where it was, so nothing is lost.
    #expect(FileManager.default.fileExists(atPath: old.appendingPathComponent("shared.txt").path))
    #expect(!FileManager.default.fileExists(atPath: old.appendingPathComponent("Clipboard").path))
  }

  @Test func mergesAFolderThatAlreadyExistsOnBothSides() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let old = root.appendingPathComponent("Old"), new = root.appendingPathComponent("New")
    try FileManager.default.createDirectory(at: old.appendingPathComponent("Clipboard"), withIntermediateDirectories: true)
    try Data("history".utf8).write(to: old.appendingPathComponent("Clipboard/entries.json"))
    try FileManager.default.createDirectory(at: new.appendingPathComponent("Clipboard"), withIntermediateDirectories: true)

    LegacyMigration.mergeFolder(from: old, into: new)

    #expect(try String(contentsOf: new.appendingPathComponent("Clipboard/entries.json"), encoding: .utf8) == "history")
    #expect(!FileManager.default.fileExists(atPath: old.path))
  }

  @Test func aMissingOldFolderIsNotAnError() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    LegacyMigration.mergeFolder(from: root.appendingPathComponent("Nope"), into: root.appendingPathComponent("New"))
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("New").path))
  }

  @Test func copiesOldPreferencesOnceWithoutOverwritingNewOnes() throws {
    let suite = "LegacyMigrationTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("new", forKey: "kept")

    LegacyMigration.mergePreferences(["kept": "old", "theme": "dark"], into: defaults, domain: suite)
    #expect(defaults.string(forKey: "kept") == "new")
    #expect(defaults.string(forKey: "theme") == "dark")

    defaults.set("light", forKey: "theme")
    LegacyMigration.mergePreferences(["theme": "dark"], into: defaults, domain: suite)
    #expect(defaults.string(forKey: "theme") == "light")
  }
}
