import Foundation

/// The "Show notes" and "New note" global shortcuts. Both are unassigned until the user picks a key.
@MainActor
final class NotesHotkeys {
  static let shared = NotesHotkeys()
  private init() {}

  func start() {
    let settings = AppSettings.shared
    DropletHotkeyCenter.shared.register(.showNotes, shortcut: settings.showNotesShortcut) {
      NotesWindowController.shared.toggle()
    }
    DropletHotkeyCenter.shared.register(.newNote, shortcut: settings.newNoteShortcut) {
      NotesWindowController.shared.newNote()
    }
  }

  /// Re-reads both bindings after the user edits one in Settings.
  func settingsChanged() { start() }
}
