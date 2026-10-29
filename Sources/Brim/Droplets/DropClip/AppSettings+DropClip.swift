import Foundation

extension AppSettings {
  var dropClipEnabled: Bool {
    get { defaults.bool(forKey: "dropClipEnabled") }
    set { defaults.set(newValue, forKey: "dropClipEnabled") }
  }
  /// Default: ⌃⌥D.
  var dropClipShortcut: DropletShortcut {
    get { .load("dropClip", fallback: DropletShortcut(keyCode: 2, modifiers: 6144), from: defaults) }
    set { newValue.save("dropClip", to: defaults) }
  }
  /// Built-in actions shown on the bar (raw ids), in order. Defaults to all of them.
  var dropClipActions: [DropClipAction] {
    get {
      guard let raw = defaults.stringArray(forKey: "dropClipActions") else { return DropClipAction.builtIns }
      return raw.compactMap(DropClipAction.init(rawValue:))
    }
    set { defaults.set(newValue.map(\.rawValue), forKey: "dropClipActions") }
  }
  var dropClipCustomActions: [DropClipCustomAction] {
    get { defaults.data(forKey: "dropClipCustomActions").flatMap { try? JSONDecoder().decode([DropClipCustomAction].self, from: $0) } ?? [] }
    set { defaults.set(try? JSONEncoder().encode(Array(newValue.prefix(12))), forKey: "dropClipCustomActions") }
  }
  var dropClipRules: DropClipRules {
    get { defaults.data(forKey: "dropClipRules").flatMap { try? JSONDecoder().decode(DropClipRules.self, from: $0) } ?? DropClipRules() }
    set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "dropClipRules") }
  }
  var dropClipSearchTemplate: String {
    get { defaults.string(forKey: "dropClipSearchTemplate") ?? DropClipTransforms.defaultSearchTemplate }
    set { defaults.set(newValue, forKey: "dropClipSearchTemplate") }
  }
  /// Language code to translate into; "system" uses this Mac's language.
  var dropClipTranslateTarget: String {
    get { defaults.string(forKey: "dropClipTranslateTarget") ?? "system" }
    set { defaults.set(newValue, forKey: "dropClipTranslateTarget") }
  }
  /// Allow the ⌘C fallback for apps that don't expose their selection to Accessibility.
  var dropClipCopyFallback: Bool {
    get { defaults.object(forKey: "dropClipCopyFallback") as? Bool ?? true }
    set { defaults.set(newValue, forKey: "dropClipCopyFallback") }
  }
}
