import Foundation
import Testing

@testable import Brim

@Suite struct CleanerTests {
  /// A throwaway "home" with a Library tree, plus a sibling user and an outside folder.
  private func makeHome() throws -> (root: URL, home: URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cleaner-\(UUID().uuidString)")
    let home = root.appendingPathComponent("me")
    let fm = FileManager.default
    for path in [
      "Library/Application Support/com.foo.bar", "Library/Application Support/com.foo.barista",
      "Library/Application Support/Foobar", "Library/Caches/com.foo.bar", "Library/Caches/com.foo.bar.helper",
      "Library/Containers/com.foo.bar", "Library/Group Containers/ABCDE12345.com.foo.bar",
      "Library/Saved Application State/com.foo.bar.savedState", "Library/HTTPStorages/com.foo.bar",
      "Library/WebKit/com.foo.bar", "Library/Logs/Foobar", "Library/Preferences",
      "Library/Preferences/ByHost", "Documents", "other/Library/Caches/com.foo.bar",
    ] {
      try fm.createDirectory(at: home.appendingPathComponent(path), withIntermediateDirectories: true)
    }
    fm.createFile(atPath: home.appendingPathComponent("Library/Preferences/com.foo.bar.plist").path, contents: Data("x".utf8))
    fm.createFile(atPath: home.appendingPathComponent("Library/Preferences/ByHost/com.foo.bar.1234.plist").path, contents: Data("x".utf8))
    fm.createFile(atPath: home.appendingPathComponent("Library/Preferences/Foobar.plist").path, contents: Data("x".utf8))
    fm.createFile(atPath: home.appendingPathComponent("Documents/com.foo.bar").path, contents: Data("x".utf8))
    return (root, home)
  }

  @Test func matchesRespectIdentifierBoundaries() {
    #expect(CleanerMatcher.matchesBundleID("com.foo.bar", bundleID: "com.foo.bar"))
    #expect(CleanerMatcher.matchesBundleID("com.foo.bar.plist", bundleID: "com.foo.bar"))
    #expect(CleanerMatcher.matchesBundleID("com.foo.bar.helper", bundleID: "com.foo.bar"))
    #expect(CleanerMatcher.matchesBundleID("ABCDE12345.com.foo.bar", bundleID: "com.foo.bar"))
    #expect(CleanerMatcher.matchesBundleID("group.com.foo.bar", bundleID: "com.foo.bar"))
    #expect(!CleanerMatcher.matchesBundleID("com.foo.barista", bundleID: "com.foo.bar"))
    #expect(!CleanerMatcher.matchesBundleID("xcom.foo.bar", bundleID: "com.foo.bar"))
    #expect(!CleanerMatcher.matchesBundleID("anything", bundleID: ""))
  }

  @Test func nameMatchNeedsFourLettersAndAnExactStem() {
    #expect(CleanerMatcher.matchesName("Foobar", appName: "Foobar"))
    #expect(CleanerMatcher.matchesName("Foobar.plist", appName: "Foobar"))
    #expect(!CleanerMatcher.matchesName("Foobar Pro", appName: "Foobar"))
    #expect(!CleanerMatcher.matchesName("Zed", appName: "Zed"))
  }

  @Test func findsLeftoversOnlyInsideTheHomeLibrary() throws {
    let (root, home) = try makeHome()
    defer { try? FileManager.default.removeItem(at: root) }
    let found = CleanerMatcher.find(appName: "Foobar", bundleID: "com.foo.bar", home: home)
    let names = Set(found.map { $0.url.lastPathComponent })
    #expect(names.isSuperset(of: [
      "com.foo.bar", "com.foo.bar.helper", "ABCDE12345.com.foo.bar", "com.foo.bar.savedState", "com.foo.bar.plist",
      "com.foo.bar.1234.plist", "Foobar",
    ]))
    #expect(!names.contains("com.foo.barista"))
    let library = CleanerSafety.library(of: home).path + "/"
    for leftover in found {
      #expect(leftover.url.resolvingSymlinksInPath().path.hasPrefix(library), "\(leftover.url.path)")
      #expect(CleanerSafety.isSafeLeftover(leftover.url, home: home))
    }
    // Documents and the other user's Library are never picked up.
    #expect(!found.contains { $0.url.path.contains("/Documents/") || $0.url.path.contains("/other/") })
  }

  @Test func nameOnlyMatchesAreNotBundleConfident() throws {
    let (root, home) = try makeHome()
    defer { try? FileManager.default.removeItem(at: root) }
    let found = CleanerMatcher.find(appName: "Foobar", bundleID: "com.foo.bar", home: home)
    let byName = found.filter { $0.confidence == .name }.map { $0.url.lastPathComponent }
    #expect(byName.contains("Foobar"))
    #expect(!byName.contains("Foobar.plist"))  // Preferences are matched by bundle id only
  }

  @Test func safetyRefusesEverythingOutsideUserLibrary() throws {
    let (root, home) = try makeHome()
    defer { try? FileManager.default.removeItem(at: root) }
    let lib = home.appendingPathComponent("Library")
    #expect(!CleanerSafety.isSafeLeftover(lib, home: home))  // the Library itself
    #expect(!CleanerSafety.isSafeLeftover(lib.appendingPathComponent("Caches"), home: home))  // a top-level folder
    #expect(!CleanerSafety.isSafeLeftover(home.appendingPathComponent("Documents/com.foo.bar"), home: home))
    #expect(!CleanerSafety.isSafeLeftover(home.appendingPathComponent("other/Library/Caches/com.foo.bar"), home: home))
    #expect(!CleanerSafety.isSafeLeftover(URL(fileURLWithPath: "/Library/Caches/com.foo.bar"), home: home))
    #expect(!CleanerSafety.isSafeLeftover(URL(fileURLWithPath: "/System/Library/Caches/x"), home: home))
    #expect(!CleanerSafety.isSafeLeftover(URL(fileURLWithPath: "/Users/someoneelse/Library/Caches/x"), home: home))
    #expect(!CleanerSafety.isSafeLeftover(lib.appendingPathComponent("Caches/../../Documents/x"), home: home))
    #expect(!CleanerSafety.isSafeLeftover(URL(string: "https://example.com/Library/Caches/x")!, home: home))
    #expect(CleanerSafety.isSafeLeftover(lib.appendingPathComponent("Caches/com.foo.bar"), home: home))
  }

  @Test func aSymlinkInLibraryPointingOutsideIsRefused() throws {
    let (root, home) = try makeHome()
    defer { try? FileManager.default.removeItem(at: root) }
    let link = home.appendingPathComponent("Library/Caches/escape")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: home.appendingPathComponent("Documents"))
    #expect(!CleanerSafety.isSafeLeftover(link, home: home))
    let found = CleanerMatcher.find(appName: "escape", bundleID: nil, home: home)
    #expect(found.isEmpty)
  }

  @Test func appsOnlyRemovableFromApplicationsAndNeverAppleOrSelf() {
    let home = URL(fileURLWithPath: "/Users/me")
    #expect(CleanerSafety.isRemovableApp(URL(fileURLWithPath: "/Applications/Foo.app"), bundleID: "com.foo.bar", home: home))
    #expect(CleanerSafety.isRemovableApp(URL(fileURLWithPath: "/Users/me/Applications/Foo.app"), bundleID: nil, home: home))
    #expect(!CleanerSafety.isRemovableApp(URL(fileURLWithPath: "/System/Applications/Notes.app"), bundleID: "com.apple.Notes", home: home))
    #expect(!CleanerSafety.isRemovableApp(URL(fileURLWithPath: "/Applications/Safari.app"), bundleID: "com.apple.Safari", home: home))
    #expect(!CleanerSafety.isRemovableApp(URL(fileURLWithPath: "/Applications/Me.app"), bundleID: "com.me.self", home: home, ownBundleID: "com.me.self"))
    #expect(!CleanerSafety.isRemovableApp(URL(fileURLWithPath: "/Users/other/Applications/Foo.app"), bundleID: nil, home: home))
    #expect(!CleanerSafety.isRemovableApp(URL(fileURLWithPath: "/Applications/Foo"), bundleID: nil, home: home))
  }

  @Test func cacheListSkipsAppleAndOwnCaches() throws {
    let (root, home) = try makeHome()
    defer { try? FileManager.default.removeItem(at: root) }
    let caches = home.appendingPathComponent("Library/Caches")
    for name in ["com.apple.Safari", "com.me.self", "Spotify"] {
      try FileManager.default.createDirectory(at: caches.appendingPathComponent(name), withIntermediateDirectories: true)
    }
    let names = CleanerMatcher.cacheFolders(home: home, ownBundleID: "com.me.self").map(\.lastPathComponent)
    #expect(names.contains("Spotify"))
    #expect(!names.contains("com.apple.Safari"))
    #expect(!names.contains("com.me.self"))
  }

  @Test func trashRefusesDisallowedPathsAndLeavesThemInPlace() throws {
    let (root, home) = try makeHome()
    defer { try? FileManager.default.removeItem(at: root) }
    let outside = home.appendingPathComponent("Documents/com.foo.bar")
    let outcome = CleanerScanner.trash([outside]) { CleanerSafety.isSafeLeftover($0, home: home) }
    #expect(outcome.moved.isEmpty)
    #expect(outcome.failed.count == 1)
    #expect(FileManager.default.fileExists(atPath: outside.path))
  }

  @Test func sizesCountFileContents() throws {
    let (root, home) = try makeHome()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = home.appendingPathComponent("Library/Caches/com.foo.bar/blob")
    try Data(repeating: 1, count: 200_000).write(to: file)
    #expect(CleanerScanner.size(of: home.appendingPathComponent("Library/Caches/com.foo.bar")) >= 200_000)
  }
}
