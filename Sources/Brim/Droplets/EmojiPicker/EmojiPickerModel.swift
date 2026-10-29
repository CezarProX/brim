import SwiftUI

@MainActor
final class EmojiPickerModel: ObservableObject {
  @Published var query = ""
  @Published var category: EmojiCategory?
  @Published var selection = 0
  @Published private(set) var recents: [String]
  @Published var skinTone: EmojiSkinTone
  let columns: Int
  private let items: [EmojiItem]
  private let settings: AppSettings
  var onPick: (String) -> Void = { _ in }

  init(items: [EmojiItem] = EmojiCatalog.all, settings: AppSettings = .shared, columns: Int? = nil) {
    self.items = items
    self.settings = settings
    self.recents = settings.emojiRecents
    self.skinTone = EmojiSkinTone(rawValue: settings.emojiSkinToneRaw) ?? .none
    self.columns = columns ?? settings.emojiColumns
  }

  /// What the grid shows: search results, or the chosen category, or recents then everything.
  var visible: [EmojiItem] {
    if !query.trimmingCharacters(in: .whitespaces).isEmpty { return EmojiSearch.filter(items, query: query) }
    if let category { return items.filter { $0.category == category } }
    return EmojiSearch.recentItems(recents, in: items) + items
  }

  var recentCount: Int {
    query.isEmpty && category == nil ? EmojiSearch.recentItems(recents, in: items).count : 0
  }

  func display(_ item: EmojiItem) -> String { skinTone.apply(to: item.character, supportsSkinTone: item.supportsSkinTone) }

  func move(dx: Int, dy: Int) {
    let count = visible.count
    guard count > 0 else { return }
    selection = min(count - 1, max(0, selection + dx + dy * columns))
  }

  func pickSelected() {
    let list = visible
    guard list.indices.contains(selection) else { return }
    pick(list[selection])
  }

  func pick(_ item: EmojiItem) {
    let character = display(item)
    recents = EmojiSearch.pushing(character, onto: recents)
    settings.emojiRecents = recents
    onPick(character)
  }

  func setSkinTone(_ tone: EmojiSkinTone) {
    skinTone = tone
    settings.emojiSkinToneRaw = tone.rawValue
  }

  func queryChanged() { selection = 0 }
}
