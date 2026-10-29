import Foundation

enum EmojiSkinTone: Int, CaseIterable, Identifiable, Sendable {
  case none, light, mediumLight, medium, mediumDark, dark
  var id: Int { rawValue }
  var title: String {
    switch self {
    case .none: "Default"
    case .light: "Light"
    case .mediumLight: "Medium-light"
    case .medium: "Medium"
    case .mediumDark: "Medium-dark"
    case .dark: "Dark"
    }
  }
  /// A hand shown on the settings swatch.
  var swatch: String { apply(to: "👋", supportsSkinTone: true) }

  /// Adds the Fitzpatrick modifier after the first scalar, dropping the variation selector.
  func apply(to character: String, supportsSkinTone: Bool) -> String {
    guard self != .none, supportsSkinTone, let first = character.unicodeScalars.first,
      let modifier = Unicode.Scalar(EmojiCatalog.skinToneModifiers[rawValue - 1])
    else { return character }
    var result = String(first)
    result.unicodeScalars.append(modifier)
    // Keep the rest of a multi-part emoji (a cook's pan, a gender sign), without the old selector.
    var rest = Array(character.unicodeScalars.dropFirst())
    if rest.first?.value == 0xFE0F { rest.removeFirst() }
    rest.forEach { result.unicodeScalars.append($0) }
    return result
  }
}

/// Search over the catalog and the recents list. Pure, so it is tested without UI.
enum EmojiSearch {
  /// Common words people type that the Unicode names do not contain.
  static let aliases: [String: [String]] = [
    "lol": ["face with tears of joy", "rolling on the floor"], "haha": ["face with tears of joy", "grinning"],
    "love": ["red heart", "smiling face with hearts", "smiling face with heart-eyes"],
    "like": ["thumbs up sign"], "ok": ["ok hand sign", "white heavy check mark"], "yes": ["thumbs up sign", "white heavy check mark"],
    "no": ["thumbs down sign", "cross mark"], "sad": ["crying face", "disappointed face", "loudly crying face"],
    "cry": ["crying face", "loudly crying face"], "happy": ["smiling face", "grinning face"],
    "angry": ["pouting face", "angry face"], "fire": ["fire"], "party": ["party popper", "confetti ball"],
    "cool": ["smiling face with sunglasses"], "think": ["thinking face"], "poop": ["pile of poo"],
    "money": ["money bag", "heavy dollar sign"], "ship": ["rocket"], "celebrate": ["party popper"],
    "bug": ["bug", "lady beetle"], "idea": ["electric light bulb"], "wave": ["waving hand sign"],
    "clap": ["clapping hands sign"], "pray": ["person with folded hands"], "thanks": ["person with folded hands"],
  ]

  static func filter(_ items: [EmojiItem], query: String) -> [EmojiItem] {
    let terms = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
    guard !terms.isEmpty else { return items }
    let scored: [(EmojiItem, Int)] = items.compactMap { item in
      var total = 0
      for term in terms {
        guard let score = score(item, term: term) else { return nil }
        total += score
      }
      return (item, total)
    }
    return scored.enumerated()
      .sorted { lhs, rhs in
        lhs.element.1 != rhs.element.1 ? lhs.element.1 < rhs.element.1 : lhs.offset < rhs.offset
      }
      .map(\.element.0)
  }

  /// Lower is better: -1 the whole name ("fire" finds fire before fire extinguisher), 0 whole-word match, 1 word prefix, 2 anywhere in the name, 3 alias.
  private static func score(_ item: EmojiItem, term: String) -> Int? {
    if item.character == term || item.name == term || (item.name.contains(term) && item.displayName.lowercased() == term) { return -1 }
    let words = item.name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == ":" }).map(String.init)
    // A whole word of the name beats a piece of a hyphenated one ("heart" before "heart-shaped").
    if item.name.split(whereSeparator: { $0 == " " || $0 == ":" }).contains(where: { $0 == term }) { return 0 }
    if words.contains(term) { return 1 }
    if words.contains(where: { $0.hasPrefix(term) }) { return 1 }
    if item.name.contains(term) { return 2 }
    if let names = aliases[term], names.contains(where: { item.name == $0 || item.name.hasPrefix($0) }) { return 3 }
    return nil
  }

  /// Recents first-in-last-out, de-duplicated, capped.
  static func pushing(_ character: String, onto recents: [String], limit: Int = 32) -> [String] {
    Array(([character] + recents.filter { $0 != character }).prefix(limit))
  }

  /// Maps stored recents back to catalog items (skin-toned variants resolve to their base).
  static func recentItems(_ recents: [String], in items: [EmojiItem]) -> [EmojiItem] {
    let byCharacter = Dictionary(items.map { ($0.character, $0) }, uniquingKeysWith: { first, _ in first })
    return recents.compactMap { character in
      if let item = byCharacter[character] { return item }
      guard let first = character.unicodeScalars.first else { return nil }
      let base = String(first)
      let guess = byCharacter[base] ?? byCharacter[base + "\u{FE0F}"]
      return guess.map {
        EmojiItem(character: character, name: $0.name, category: $0.category, supportsSkinTone: false)
      }
    }
  }
}
