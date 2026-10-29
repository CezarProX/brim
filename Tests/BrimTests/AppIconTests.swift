import AppKit
import Foundation
import Testing
@testable import Brim

@Suite("App icon variants")
struct AppIconTests {
  private func settings() -> AppSettings {
    AppSettings(defaults: UserDefaults(suiteName: "icon-test-\(UUID().uuidString)")!)
  }

  private func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
    let tiff = try #require(image.tiffRepresentation)
    return try #require(NSBitmapImageRep(data: tiff))
  }

  private func png(_ rep: NSBitmapImageRep) throws -> Data {
    try #require(rep.representation(using: .png, properties: [:]))
  }

  @Test func offersTheDefaultPlusFourAlternates() {
    #expect(AppIconVariant.allCases.count == 5)
    #expect(AppIconVariant.allCases.first == .standard)
    #expect(Set(AppIconVariant.allCases.map(\.title)).count == 5)
  }

  @Test func defaultsToTheStandardIcon() {
    #expect(settings().appIconVariant == .standard)
  }

  @Test func theChoiceSurvivesARestart() {
    let suite = UserDefaults(suiteName: "icon-persist-\(UUID().uuidString)")!
    let first = AppSettings(defaults: suite)
    first.appIconVariant = .aurora
    #expect(AppSettings(defaults: suite).appIconVariant == .aurora)
  }

  @Test func anUnknownStoredValueFallsBackToStandard() {
    let suite = UserDefaults(suiteName: "icon-bad-\(UUID().uuidString)")!
    suite.set("retired-icon", forKey: "appIconVariant")
    #expect(AppSettings(defaults: suite).appIconVariant == .standard)
  }

  @MainActor @Test func everyVariantDrawsADistinctOpaqueIcon() throws {
    var fingerprints = Set<Data>()
    for variant in AppIconVariant.allCases {
      let image = AppIconRenderer.image(for: variant, size: 128)
      let rep = try bitmap(image)
      #expect(rep.pixelsWide >= 128)
      let centre = try #require(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2))
      #expect(centre.alphaComponent > 0.9)
      let corner = try #require(rep.colorAt(x: 1, y: 1))
      #expect(corner.alphaComponent < 0.1, "the transparent margin keeps the icon a rounded tile")
      fingerprints.insert(try png(rep))
    }
    #expect(fingerprints.count == AppIconVariant.allCases.count)
  }

  @MainActor @Test func renderPreviews() throws {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for variant in AppIconVariant.allCases {
      let image = AppIconRenderer.image(for: variant, size: 256)
      try png(try bitmap(image)).write(to: dir.appendingPathComponent("icon-\(variant.rawValue).png"))
    }
  }
}
