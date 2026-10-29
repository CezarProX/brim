import Foundation
import Testing

/// Under the hardened runtime, a usage description alone isn't enough: without the matching
/// entitlement macOS silently refuses to prompt (tccd: "Policy disallows prompt").
struct EntitlementTests {
  private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()

  private func plist(_ path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: root.appendingPathComponent(path))
    return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
  }

  @Test func everyProtectedResourceTheAppDescribesIsEntitled() throws {
    let info = try plist("Resources/Info.plist")
    let entitlements = try plist("Resources/Brim.entitlements")
    let required: [String: String] = [
      "NSCalendarsFullAccessUsageDescription": "com.apple.security.personal-information.calendars",
      "NSCalendarsUsageDescription": "com.apple.security.personal-information.calendars",
      "NSMicrophoneUsageDescription": "com.apple.security.device.audio-input",
      "NSCameraUsageDescription": "com.apple.security.device.camera",
    ]
    for (description, entitlement) in required where info[description] != nil {
      #expect(entitlements[entitlement] as? Bool == true, "\(description) needs \(entitlement)")
    }
  }
}
