import Foundation
import Testing
@testable import Brim

/// Reads the shipped Resources/<lang>.lproj tables straight from the repository.
private enum Tables {
  static let root: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

  static func load(_ lang: String) -> [String: String] {
    let url = root.appendingPathComponent("Resources/\(lang).lproj/Localizable.strings")
    return (NSDictionary(contentsOf: url) as? [String: String]) ?? [:]
  }

  static func bundle(_ lang: String) -> Bundle? {
    Bundle(path: root.appendingPathComponent("Resources/\(lang).lproj").path)
  }

  /// Decodes the escapes a Swift literal uses so it can be compared with the table's real characters.
  static func unescape(_ literal: String) -> String {
    var out = literal.replacingOccurrences(of: "\\\"", with: "\"")
    let unicode = try! NSRegularExpression(pattern: #"\\u\{([0-9A-Fa-f]+)\}"#)
    for match in unicode.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
      guard let whole = Range(match.range, in: out), let hex = Range(match.range(at: 1), in: out),
            let value = UInt32(out[hex], radix: 16), let scalar = Unicode.Scalar(value) else { continue }
      out.replaceSubrange(whole, with: String(Character(scalar)))
    }
    return out
  }

  /// Every non-interpolated literal that SwiftUI localizes on its own (Text, Toggle, Button, ...).
  static func swiftUILiterals() -> Set<String> {
    let sources = root.appendingPathComponent("Sources/Brim")
    let pattern = try! NSRegularExpression(
      pattern: #"\b(?:Text|Toggle|Button|Label|Section|Picker|Stepper|LabeledContent|DisclosureGroup)\(\s*"((?:[^"\\\n]|\\.)*)""#
        + #"|String\(localized:\s*"((?:[^"\\\n]|\\.)*)""#
        + #"|L10n\.tr\(\s*"((?:[^"\\\n]|\\.)*)""#
        + #"|\.(?:help|navigationTitle)\(\s*"((?:[^"\\\n]|\\.)*)""#)
    var found = Set<String>()
    let walker = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
    for case let url as URL in walker ?? NSEnumerator() where url.pathExtension == "swift" {
      guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
      let range = NSRange(text.startIndex..., in: text)
      for match in pattern.matches(in: text, range: range) {
        for group in 1...4 {
          guard let r = Range(match.range(at: group), in: text) else { continue }
          let literal = String(text[r])
          if literal.contains("\\(") || literal.range(of: "[A-Za-z]{2}", options: .regularExpression) == nil { continue }
          found.insert(unescape(literal))
        }
      }
    }
    return found
  }
}

@Suite("Localization")
struct LocalizationTests {
  @Test func bothLanguagesShipTheSameKeys() {
    let en = Tables.load("en"), ro = Tables.load("ro")
    #expect(!en.isEmpty)
    #expect(Set(en.keys) == Set(ro.keys))
    #expect(ro.values.allSatisfy { !$0.isEmpty })
  }

  @Test func englishIsTheIdentity() {
    let en = Tables.load("en")
    #expect(en.allSatisfy { $0.key == $0.value })
  }

  @Test func romanianActuallyTranslates() {
    let en = Tables.load("en"), ro = Tables.load("ro")
    let changed = en.keys.filter { ro[$0] != $0 }.count
    #expect(Double(changed) / Double(en.count) > 0.85)
  }

  @Test func formatSpecifiersSurviveTranslation() {
    let ro = Tables.load("ro")
    for (key, value) in ro where key.contains("%") {
      let count: (String) -> Int = { $0.components(separatedBy: "%").count }
      #expect(count(key) == count(value), "placeholder mismatch in \(key)")
    }
  }

  @Test func everyUserFacingLiteralIsInTheTable() {
    let ro = Tables.load("ro")
    let missing = Tables.swiftUILiterals().filter { ro[$0] == nil }.sorted()
    #expect(Tables.swiftUILiterals().count > 300)
    #expect(missing.isEmpty, "Missing from Localizable.strings: \(missing)")
  }

  @Test func lookupReturnsRomanianAndFallsBackToEnglish() throws {
    let ro = try #require(Tables.bundle("ro"))
    let saved = L10n.bundle
    defer { L10n.bundle = saved }
    L10n.bundle = ro
    #expect(L10n.tr("Cancel") == "Anulează")
    #expect(L10n.tr("Page %lld of %lld", 2, 5) == "Pagina 2 din 5")
    #expect(L10n.tr("A string nobody translated") == "A string nobody translated")
  }

  @Test func languageChoiceMapsToAppleLanguages() {
    #expect(AppLanguage.system.appleLanguages == nil)
    #expect(AppLanguage.romanian.appleLanguages == ["ro"])
    #expect(AppLanguage.resolve(preferred: ["ro-RO", "en-US"]) == "ro")
    #expect(AppLanguage.resolve(preferred: ["fr-FR"]) == "en")
  }

  @Test func languageChoicePersistsAndWritesOverride() throws {
    let suite = UserDefaults(suiteName: "loc-test-\(UUID().uuidString)")!
    AppSettings.applyLanguageOverride(.romanian, to: suite)
    #expect(suite.stringArray(forKey: "AppleLanguages") == ["ro"])
    AppSettings.applyLanguageOverride(.system, to: suite)
    #expect(suite.stringArray(forKey: "AppleLanguages") != ["ro"])
  }
}
