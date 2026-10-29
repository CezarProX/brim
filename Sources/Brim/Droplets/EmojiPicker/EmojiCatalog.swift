import Foundation

enum EmojiCategory: String, CaseIterable, Identifiable, Sendable {
  case smileys, people, animals, food, activity, travel, objects, symbols, flags
  var id: String { rawValue }
  var title: String {
    switch self {
    case .smileys: "Smileys & Hearts"
    case .people: "People & Body"
    case .animals: "Animals & Nature"
    case .food: "Food & Drink"
    case .activity: "Activity"
    case .travel: "Travel & Places"
    case .objects: "Objects"
    case .symbols: "Symbols"
    case .flags: "Flags"
    }
  }
  var symbol: String {
    switch self {
    case .smileys: "face.smiling"
    case .people: "hand.raised"
    case .animals: "pawprint"
    case .food: "fork.knife"
    case .activity: "soccerball"
    case .travel: "car"
    case .objects: "lightbulb"
    case .symbols: "number"
    case .flags: "flag"
    }
  }
}

struct EmojiItem: Identifiable, Equatable, Sendable {
  /// The emoji as it is inserted (with the emoji variation selector where one is needed).
  let character: String
  /// Lowercase Unicode / CLDR-style name used for search.
  let name: String
  let category: EmojiCategory
  /// Whether the five Fitzpatrick skin tones apply.
  let supportsSkinTone: Bool
  var id: String { character }
}

/// The emoji set, built from the Unicode data the running macOS ships with, so it always
/// matches the system's fonts and needs no bundled catalog.
enum EmojiCatalog {
  /// Built once, off the main thread if the caller wants (it takes a few milliseconds).
  static let all: [EmojiItem] = build()

  static let skinToneModifiers: [UInt32] = [0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF]

  static func build() -> [EmojiItem] {
    var items: [EmojiItem] = []
    let ranges: [ClosedRange<UInt32>] = [0x203C...0x3299, 0x1F000...0x1FAFF]
    for range in ranges {
      for value in range {
        guard let scalar = Unicode.Scalar(value), isCandidate(scalar), let name = scalar.properties.name
        else { continue }
        let character = scalar.properties.isEmojiPresentation ? String(scalar) : String(scalar) + "\u{FE0F}"
        items.append(
          EmojiItem(
            character: character, name: name.lowercased(), category: category(of: value, scalar: scalar),
            supportsSkinTone: scalar.properties.isEmojiModifierBase))
      }
    }
    let order = Dictionary(uniqueKeysWithValues: EmojiCategory.allCases.enumerated().map { ($1, $0) })
    // Stable sort: group order first, Unicode order within a group.
    let grouped = items.enumerated().sorted {
      let (l, r) = (order[$0.element.category] ?? 0, order[$1.element.category] ?? 0)
      if l != r { return l < r }
      // Text-style symbols (a frowning face, a heart) sort after the colorful emoji block.
      let (lRank, rRank) = (Self.sortRank($0.element), Self.sortRank($1.element))
      return lRank != rRank ? lRank < rRank : $0.offset < $1.offset
    }
    return grouped.map(\.element) + EmojiSequences.all() + flags()
  }

  /// The classic faces lead, then the rest of the colorful block, then text-style symbols.
  private static func sortRank(_ item: EmojiItem) -> Int {
    let value = item.character.unicodeScalars.first?.value ?? 0
    if (0x1F600...0x1F64F).contains(value) { return 0 }
    return value >= 0x1F000 ? 1 : 2
  }

  private static func isCandidate(_ scalar: Unicode.Scalar) -> Bool {
    let props = scalar.properties
    guard props.isEmoji else { return false }
    let value = scalar.value
    if (0x1F1E6...0x1F1FF).contains(value) || (0x1F3FB...0x1F3FF).contains(value) { return false }
    if (0xE0020...0xE007F).contains(value) { return false }
    return props.isEmojiPresentation || value >= 0x203C
  }

  /// Flag emoji from the region codes the system knows, named by their localized country.
  static func flags(locale: Locale = Locale(identifier: "en_US")) -> [EmojiItem] {
    Locale.Region.isoRegions.compactMap { region -> EmojiItem? in
      let code = region.identifier
      guard code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter }),
        let name = locale.localizedString(forRegionCode: code)
      else { return nil }
      let scalars = code.uppercased().unicodeScalars.compactMap { Unicode.Scalar(0x1F1E6 + $0.value - 65) }
      guard scalars.count == 2 else { return nil }
      var flag = ""
      scalars.forEach { flag.unicodeScalars.append($0) }
      return EmojiItem(
        character: flag, name: "flag: " + name.lowercased(), category: .flags, supportsSkinTone: false)
    }
    .sorted { $0.name < $1.name }
  }

  // MARK: Categories

  /// A small set of code-point ranges per group, following the Unicode emoji group order.
  static func category(of value: UInt32, scalar: Unicode.Scalar) -> EmojiCategory {
    if scalar.properties.isEmojiModifierBase { return .people }
    for (category, ranges) in groupRanges where ranges.contains(where: { $0.contains(value) }) { return category }
    return value < 0x1F000 ? .symbols : .objects
  }

  private static let groupRanges: [(EmojiCategory, [ClosedRange<UInt32>])] = [
    (.smileys, [0x1F600...0x1F644, 0x1F910...0x1F92F, 0x1F970...0x1F97A, 0x1F493...0x1F49F, 0x1F5A4...0x1F5A4,
                0x1F90D...0x1F90E, 0x1F9E1...0x1F9E1, 0x2764...0x2764, 0x2639...0x263A, 0x1F644...0x1F64A,
                0x1F4A2...0x1F4A9, 0x1F47B...0x1F47F, 0x1F480...0x1F480]),
    (.people, [0x1F440...0x1F450, 0x1F463...0x1F487, 0x1F9B0...0x1F9B9, 0x1F9D0...0x1F9FF, 0x1F645...0x1F64F]),
    (.animals, [0x1F400...0x1F43F, 0x1F980...0x1F9AE, 0x1F330...0x1F344, 0x1F490...0x1F492, 0x1F338...0x1F33F,
                0x1F98B...0x1F9A2, 0x1FAB0...0x1FAB9, 0x1F331...0x1F335, 0x1F300...0x1F30C]),
    (.food, [0x1F345...0x1F37F, 0x1F950...0x1F96B, 0x1F32D...0x1F32F, 0x1F9C0...0x1F9CB, 0x1FAD0...0x1FADB,
             0x2615...0x2615]),
    (.activity, [0x1F380...0x1F3C9, 0x1F3CF...0x1F3D3, 0x1F94A...0x1F94F, 0x26BD...0x26BE, 0x1F3AE...0x1F3AF,
                 0x1FA80...0x1FA86, 0x1F9E9...0x1F9E9]),
    (.travel, [0x1F680...0x1F6FF, 0x1F3D4...0x1F3DF, 0x1F3E0...0x1F3F0, 0x1F30D...0x1F321, 0x26F0...0x26FA,
               0x1F301...0x1F301, 0x2708...0x2708]),
    (.objects, [0x1F4A1...0x1F4A1, 0x1F4B0...0x1F4FF, 0x1F500...0x1F500, 0x1F507...0x1F53D, 0x231A...0x23F3,
                0x1F5A5...0x1F5FF, 0x1FA70...0x1FAFF, 0x1F9F0...0x1F9FF, 0x260E...0x260E, 0x2692...0x26A1]),
    (.symbols, [0x2600...0x2699, 0x2B00...0x2BFF, 0x1F7E0...0x1F7EB, 0x2190...0x21FF, 0x2795...0x2797, 0x2753...0x2757,
                0x1F170...0x1F251, 0x1F520...0x1F53D]),
  ]
}
