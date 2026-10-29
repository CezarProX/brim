import Foundation
import Testing

@testable import Brim

struct ClaudeArtTests {
  @Test func findsTheNewestInstalledExtensionsArt() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ext-\(UUID().uuidString)")
    for version in ["2.1.9", "2.1.280"] {
      let resources = root.appendingPathComponent("anthropic.claude-code-\(version)-darwin-arm64/resources")
      try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
      try Data("<svg/>".utf8).write(to: resources.appendingPathComponent("clawd.svg"))
    }
    try FileManager.default.createDirectory(at: root.appendingPathComponent("someone.else-1.0"), withIntermediateDirectories: true)
    let found = try #require(ClaudeArt.resource(named: "clawd.svg", in: [root]))
    #expect(found.path.contains("2.1.280"))
  }

  @Test func missingExtensionFallsBackToNothing() {
    let nowhere = FileManager.default.temporaryDirectory.appendingPathComponent("none-\(UUID().uuidString)")
    #expect(ClaudeArt.resource(named: "clawd.svg", in: [nowhere]) == nil)
  }
}
