import Foundation
import Testing

@testable import Brim

struct EmojiPickerTests {
  @Test func catalogIsBuiltFromSystemUnicodeData() {
    let all = EmojiCatalog.all
    #expect(all.count > 1200)
    #expect(all.contains { $0.character == "😀" && $0.name == "grinning face" })
    #expect(all.contains { $0.category == .flags && $0.name.contains("japan") })
    // Text-presentation emoji carry the variation selector so they render in color.
    #expect(all.contains { $0.character == "❤\u{FE0F}" })
  }

  @Test func searchRanksWholeWordsBeforePrefixes() {
    let hits = EmojiSearch.filter(EmojiCatalog.all, query: "heart")
    #expect(!hits.isEmpty)
    #expect(hits.first?.name.split(separator: " ").contains("heart") == true)
  }

  @Test func multiWordSearchRequiresEveryTerm() {
    let hits = EmojiSearch.filter(EmojiCatalog.all, query: "face tears")
    #expect(hits.contains { $0.character == "😂" })
    #expect(hits.allSatisfy { $0.name.contains("face") && $0.name.contains("tears") })
  }

  @Test func aliasesFindWordsNotInUnicodeNames() {
    #expect(EmojiSearch.filter(EmojiCatalog.all, query: "lol").contains { $0.character == "😂" })
  }

  @Test func searchByTheEmojiItselfAndEmptyQuery() {
    #expect(EmojiSearch.filter(EmojiCatalog.all, query: "🔥").first?.character == "🔥")
    #expect(EmojiSearch.filter(EmojiCatalog.all, query: "  ").count == EmojiCatalog.all.count)
    #expect(EmojiSearch.filter(EmojiCatalog.all, query: "zzzzqqqq").isEmpty)
  }

  @Test func skinTonesApplyOnlyWhereSupported() {
    #expect(EmojiSkinTone.dark.apply(to: "👋", supportsSkinTone: true) == "👋\u{1F3FF}")
    #expect(EmojiSkinTone.dark.apply(to: "😀", supportsSkinTone: false) == "😀")
    #expect(EmojiSkinTone.none.apply(to: "👋", supportsSkinTone: true) == "👋")
    #expect(EmojiCatalog.all.first { $0.character == "👋" }?.supportsSkinTone == true)
  }

  @Test func recentsAreUniqueNewestFirstAndCapped() {
    var recents: [String] = []
    for character in ["😀", "🔥", "😀"] { recents = EmojiSearch.pushing(character, onto: recents) }
    #expect(recents == ["😀", "🔥"])
    let many = (0..<50).map { "\($0)" }.reduce([String]()) { EmojiSearch.pushing($1, onto: $0, limit: 5) }
    #expect(many.count == 5 && many.first == "49")
  }

  @MainActor @Test func pickingRecordsRecentsAndReportsTheToneVariant() {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "QS-Emoji-\(UUID().uuidString)")!)
    settings.emojiColumns = 3
    #expect(settings.emojiColumns == 5)  // clamped
    let model = EmojiPickerModel(settings: settings)
    model.setSkinTone(.medium)
    var inserted: String?
    model.onPick = { inserted = $0 }
    model.query = "waving hand"
    model.selection = 0
    model.pickSelected()
    #expect(inserted?.unicodeScalars.contains { $0.value == 0x1F3FD } == true)
    #expect(settings.emojiRecents.first == inserted)
    #expect(settings.emojiSkinToneRaw == 3)
  }

  @MainActor @Test func arrowKeysStayInsideTheGrid() {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "QS-Emoji-\(UUID().uuidString)")!)
    let model = EmojiPickerModel(settings: settings)
    model.move(dx: -1, dy: -1)
    #expect(model.selection == 0)
    model.move(dx: 0, dy: 1)
    #expect(model.selection == model.columns)
  }
}
