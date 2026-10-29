// ShelfKeyboardShortcuts.swift
// Brim
//
// Keyboard shortcuts for the open file tray: Cmd+A selects
// every file, Esc clears the selection, Delete removes the selected files from the tray, Cmd+C copies
// them to the pasteboard and Return opens them. The rules are pure so they can be tested; the view
// modifier turns each rule into a hidden button, which only fires while the island window is key.

import AppKit
import SwiftUI

enum ShelfShortcut: CaseIterable, Sendable {
  case selectAll, deselect, remove, copy, open

  var key: KeyEquivalent {
    switch self {
    case .selectAll: "a"
    case .deselect: .escape
    case .remove: .delete
    case .copy: "c"
    case .open: .return
    }
  }

  var modifiers: EventModifiers {
    switch self {
    case .selectAll, .copy: .command
    case .deselect, .remove, .open: []
    }
  }

  /// The files an action works on. Destructive and file-handing actions use only the files the user
  /// picked: with nothing selected they do nothing, so Delete can never empty the tray by accident.
  static func targets(for action: ShelfShortcut, selection: Set<UUID>, items: [UUID]) -> Set<UUID> {
    let present = selection.intersection(items)
    switch action {
    case .selectAll: return Set(items)
    case .deselect: return []
    case .remove, .copy, .open: return present
    }
  }
}

/// What the tray view does for each shortcut; each closure receives the files the shortcut applies to.
struct ShelfShortcutHandlers {
  var items: [UUID]
  var selection: Set<UUID>
  var selectAll: (Set<UUID>) -> Void
  var deselect: () -> Void
  var remove: (Set<UUID>) -> Void
  var copy: (Set<UUID>) -> Void
  var open: (Set<UUID>) -> Void

  /// A shortcut with nothing to act on is disabled, so its key (Esc, Delete) still reaches the island.
  func isEnabled(_ action: ShelfShortcut) -> Bool {
    switch action {
    case .selectAll: !items.isEmpty
    case .deselect: !selection.isEmpty
    case .remove, .copy, .open: !ShelfShortcut.targets(for: action, selection: selection, items: items).isEmpty
    }
  }

  func perform(_ action: ShelfShortcut) {
    let targets = ShelfShortcut.targets(for: action, selection: selection, items: items)
    switch action {
    case .selectAll: selectAll(targets)
    case .deselect: deselect()
    case .remove: if !targets.isEmpty { remove(targets) }
    case .copy: if !targets.isEmpty { copy(targets) }
    case .open: if !targets.isEmpty { open(targets) }
    }
  }
}

extension View {
  /// Adds the shelf shortcuts as invisible buttons behind the view.
  func shelfKeyboardShortcuts(_ handlers: ShelfShortcutHandlers) -> some View {
    background {
      ZStack {
        ForEach(ShelfShortcut.allCases, id: \.self) { action in
          Button("") { handlers.perform(action) }
            .keyboardShortcut(action.key, modifiers: action.modifiers)
            .disabled(!handlers.isEnabled(action))
        }
      }
      .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
    }
  }
}

enum ShelfPasteboard {
  /// Puts the files on the general pasteboard so Cmd+V in Finder pastes them.
  @MainActor static func copy(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    let board = NSPasteboard.general
    board.clearContents()
    board.writeObjects(urls as [NSURL])
  }
}
