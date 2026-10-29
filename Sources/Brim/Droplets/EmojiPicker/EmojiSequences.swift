import CoreText
import Foundation

/// Emoji made of several code points (families, professions, keycaps, rainbow flag…), which the
/// Unicode name table cannot list. Each is kept only if this Mac's emoji font draws it as ONE glyph,
/// so an older macOS never shows a broken pair.
enum EmojiSequences {
  private static let zwj = "\u{200D}"
  private static let fe0f = "\u{FE0F}"

  static func all() -> [EmojiItem] {
    (people() + faces() + animalsAndSymbols() + keycaps() + flagSequences()).filter { rendersAsOneGlyph($0.character) }
  }

  private static func item(_ scalars: [String], _ name: String, _ category: EmojiCategory, tone: Bool = false) -> EmojiItem {
    EmojiItem(character: scalars.joined(), name: name, category: category, supportsSkinTone: tone)
  }

  // MARK: People

  private static func people() -> [EmojiItem] {
    var items: [EmojiItem] = []
    let bases = [("🧑", "person"), ("👨", "man"), ("👩", "woman")]
    let jobs: [(String, String)] = [
      ("⚕\(fe0f)", "health worker"), ("🎓", "student"), ("🏫", "teacher"), ("⚖\(fe0f)", "judge"), ("🌾", "farmer"),
      ("🍳", "cook"), ("🔧", "mechanic"), ("🏭", "factory worker"), ("💼", "office worker"), ("🔬", "scientist"),
      ("💻", "technologist"), ("🎤", "singer"), ("🎨", "artist"), ("✈\(fe0f)", "pilot"), ("🚀", "astronaut"),
      ("🚒", "firefighter"),
    ]
    for (base, who) in bases {
      for (object, job) in jobs {
        items.append(item([base, zwj, object], who == "person" ? job : "\(who) \(job)", .people, tone: true))
      }
    }
    // Gendered activities: the person emoji, a joiner, then the male or female sign.
    let activities: [(String, String)] = [
      ("🤦", "facepalming"), ("🤷", "shrugging"), ("🙋", "raising hand"), ("🙆", "gesturing OK"), ("🙅", "gesturing no"),
      ("💁", "tipping hand"), ("🙇", "bowing"), ("🏃", "running"), ("🚶", "walking"), ("🧘", "in lotus position"),
      ("🏄", "surfing"), ("🏊", "swimming"), ("🚴", "biking"), ("🧙", "mage"), ("🧛", "vampire"), ("🧜", "merperson"),
      ("🧚", "fairy"), ("🦸", "superhero"), ("🦹", "supervillain"), ("💆", "getting massage"), ("💇", "getting haircut"),
      ("👷", "construction worker"), ("👮", "police officer"), ("💂", "guard"), ("🕵\(fe0f)", "detective"),
    ]
    for (emoji, label) in activities {
      items.append(item([emoji, zwj, "♂\(fe0f)"], "man \(label)", .people, tone: !emoji.hasSuffix(fe0f)))
      items.append(item([emoji, zwj, "♀\(fe0f)"], "woman \(label)", .people, tone: !emoji.hasSuffix(fe0f)))
    }
    // Families and couples.
    let adults = [("👨", "man"), ("👩", "woman")]
    let kids = [("👦", "boy"), ("👧", "girl")]
    for (a, an) in adults { for (b, bn) in adults where an != bn || a == "👨" || a == "👩" {
      for (k, kn) in kids { items.append(item([a, zwj, b, zwj, k], "family: \(an), \(bn), \(kn)", .people)) }
    } }
    items.append(item(["🧑", zwj, "🤝", zwj, "🧑"], "people holding hands", .people, tone: true))
    items.append(item(["👩", zwj, "❤\(fe0f)", zwj, "👨"], "couple with heart: woman, man", .people))
    items.append(item(["👨", zwj, "❤\(fe0f)", zwj, "👨"], "couple with heart: man, man", .people))
    items.append(item(["👩", zwj, "❤\(fe0f)", zwj, "👩"], "couple with heart: woman, woman", .people))
    items.append(item(["🧑", zwj, "🎄"], "mx claus", .people, tone: true))
    items.append(item(["🧑", zwj, "🦰"], "person: red hair", .people, tone: true))
    items.append(item(["🧑", zwj, "🦳"], "person: white hair", .people, tone: true))
    items.append(item(["🧑", zwj, "🦲"], "person: bald", .people, tone: true))
    items.append(item(["🧑", zwj, "🦯"], "person with white cane", .people, tone: true))
    items.append(item(["🧑", zwj, "🦼"], "person in motorized wheelchair", .people, tone: true))
    return items
  }

  private static func faces() -> [EmojiItem] {
    [
      item(["😮", zwj, "💨"], "face exhaling", .smileys), item(["😵", zwj, "💫"], "face with spiral eyes", .smileys),
      item(["😶", zwj, "🌫\(fe0f)"], "face in clouds", .smileys), item(["❤\(fe0f)", zwj, "🔥"], "heart on fire", .smileys),
      item(["❤\(fe0f)", zwj, "🩹"], "mending heart", .smileys), item(["👁\(fe0f)", zwj, "🗨\(fe0f)"], "eye in speech bubble", .symbols),
    ]
  }

  private static func animalsAndSymbols() -> [EmojiItem] {
    [
      item(["🐻", zwj, "❄\(fe0f)"], "polar bear", .animals), item(["🐕", zwj, "🦺"], "service dog", .animals),
      item(["🐦", zwj, "⬛"], "black bird", .animals), item(["🐈", zwj, "⬛"], "black cat", .animals),
    ]
  }

  private static func keycaps() -> [EmojiItem] {
    ["#", "*", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"].map {
      item([$0, fe0f, "\u{20E3}"], "keycap: \($0)", .symbols)
    }
  }

  private static func flagSequences() -> [EmojiItem] {
    var items = [
      item(["🏳\(fe0f)", zwj, "🌈"], "rainbow flag", .flags), item(["🏳\(fe0f)", zwj, "⚧\(fe0f)"], "transgender flag", .flags),
      item(["🏴", zwj, "☠\(fe0f)"], "pirate flag", .flags),
    ]
    for (code, name) in [("gbeng", "england"), ("gbsct", "scotland"), ("gbwls", "wales")] {
      var flag = "\u{1F3F4}"
      for letter in code.unicodeScalars { if let tag = Unicode.Scalar(0xE0000 + letter.value) { flag.unicodeScalars.append(tag) } }
      flag.unicodeScalars.append(Unicode.Scalar(0xE007F)!)
      items.append(EmojiItem(character: flag, name: "flag: \(name)", category: .flags, supportsSkinTone: false))
    }
    return items
  }

  // MARK: Font check

  /// True when the emoji font lays the sequence out as a single glyph (a supported ligature).
  static func rendersAsOneGlyph(_ text: String) -> Bool {
    let font = CTFontCreateWithName("Apple Color Emoji" as CFString, 20, nil)
    let attributed = NSAttributedString(string: text, attributes: [.font: font])
    let line = CTLineCreateWithAttributedString(attributed)
    let runs = (CTLineGetGlyphRuns(line) as? [CTRun]) ?? []
    return runs.reduce(0) { $0 + CTRunGetGlyphCount($1) } == 1
  }
}

/// Friendly names for the Unicode name table ("WHITE FROWNING FACE" -> "Frowning Face").
enum EmojiNames {
  private static let small: Set<String> = ["with", "of", "and", "in", "on", "the", "a", "for", "to", "over", "under"]
  private static let shout: Set<String> = ["ok", "sos", "id", "ng", "cl", "vs", "ab", "atm", "wc", "tm"]

  static func friendly(_ raw: String) -> String {
    var name = raw.lowercased()
    let rules: [(String, String)] = [
      (#"^(?:white|black) (up|down|left|right) pointing backhand index$"#, "backhand index pointing $1"),
      (#"^(?:white|black) (frowning|smiling) face$"#, "$1 face"),
      (#"^waving (white|black) flag$"#, "$1 flag"),
      (#"^black universal recycling symbol$"#, "recycling symbol"),
      (#"^(.+) hand sign$"#, "$1 hand"),
      (#"^(.+) sign$"#, "$1"),
      (#"^(?:white|black) (sun|scissors|nib|telephone|spade suit|heart suit|club suit|diamond suit)(.*)$"#, "$1$2"),
    ]
    for (pattern, template) in rules {
      let result = name.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
      if result != name { name = result; break }
    }
    return name.split(separator: " ").enumerated().map { index, word -> String in
      let w = String(word)
      if shout.contains(w) { return w.uppercased() }
      if index > 0, small.contains(w) { return w }
      return w.prefix(1).uppercased() + w.dropFirst()
    }.joined(separator: " ")
  }
}

extension EmojiItem {
  /// The name shown to people: title-cased, without the legacy "white"/"sign" wording.
  var displayName: String { EmojiNames.friendly(name) }
}
