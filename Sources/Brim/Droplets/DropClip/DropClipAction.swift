// DropClipAction.swift
// Brim
//
// The actions on the bar: built-ins, user-defined custom actions, and per-app rules.

import Foundation

enum DropClipAction: Hashable, Identifiable {
  case copy, search, translate, define, uppercase, lowercase, titleCase, count, notes, pinboard
  case custom(UUID)

  static let builtIns: [DropClipAction] = [
    .copy, .search, .translate, .define, .uppercase, .lowercase, .titleCase, .count, .notes, .pinboard,
  ]

  var id: String { rawValue }

  var rawValue: String {
    switch self {
    case .copy: "copy"
    case .search: "search"
    case .translate: "translate"
    case .define: "define"
    case .uppercase: "upper"
    case .lowercase: "lower"
    case .titleCase: "title"
    case .count: "count"
    case .notes: "notes"
    case .pinboard: "pinboard"
    case .custom(let id): "custom:" + id.uuidString
    }
  }

  init?(rawValue: String) {
    if rawValue.hasPrefix("custom:"), let uuid = UUID(uuidString: String(rawValue.dropFirst(7))) {
      self = .custom(uuid)
      return
    }
    guard let match = Self.builtIns.first(where: { $0.rawValue == rawValue }) else { return nil }
    self = match
  }

  var title: String {
    switch self {
    case .copy: "Copy"
    case .search: "Search the web"
    case .translate: "Translate"
    case .define: "Define"
    case .uppercase: "UPPERCASE"
    case .lowercase: "lowercase"
    case .titleCase: "Title Case"
    case .count: "Count words"
    case .notes: "Send to Notes"
    case .pinboard: "Add to clipboard pinboard"
    case .custom: "Custom action"
    }
  }

  var symbol: String {
    switch self {
    case .copy: "doc.on.doc"
    case .search: "magnifyingglass"
    case .translate: "translate"
    case .define: "character.book.closed"
    case .uppercase: "textformat.size.larger"
    case .lowercase: "textformat.size.smaller"
    case .titleCase: "textformat"
    case .count: "number"
    case .notes: "note.text.badge.plus"
    case .pinboard: "pin"
    case .custom: "bolt.fill"
    }
  }
}

/// A user-defined action: open a URL built from the text, or run a shell snippet (always confirmed).
struct DropClipCustomAction: Codable, Identifiable, Equatable {
  enum Kind: String, Codable, CaseIterable { case url, shell }
  var id = UUID()
  var title: String
  var kind: Kind
  /// URL template using `{text}` / `{text+}`, or the shell snippet (the text arrives in $DROPCLIP_TEXT and on stdin).
  var template: String
  var action: DropClipAction { .custom(id) }
}

/// What the bar shows for a given frontmost app.
struct DropClipAppRule: Codable, Equatable {
  /// false hides the bar entirely in this app.
  var enabled = true
  /// Raw action ids removed from the bar in this app.
  var hidden: Set<String> = []
}

struct DropClipRules: Codable, Equatable {
  var apps: [String: DropClipAppRule] = [:]

  func isEnabled(in bundleID: String?) -> Bool {
    guard let bundleID else { return true }
    return apps[bundleID]?.enabled ?? true
  }

  /// Actions to show, in order, honoring the global list and this app's rule.
  func actions(global: [DropClipAction], in bundleID: String?) -> [DropClipAction] {
    guard let bundleID, let rule = apps[bundleID] else { return global }
    return global.filter { !rule.hidden.contains($0.rawValue) }
  }

  func setting(_ rule: DropClipAppRule, for bundleID: String) -> DropClipRules {
    var copy = self
    copy.apps[bundleID] = rule
    return copy
  }

  func removing(_ bundleID: String) -> DropClipRules {
    var copy = self
    copy.apps[bundleID] = nil
    return copy
  }
}
