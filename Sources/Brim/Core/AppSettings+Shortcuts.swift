// AppSettings+Shortcuts.swift
// Brim
//
// Editable bindings for the shortcuts that used to be hard-coded: the Ring, the island toggle and
// the clipboard library. Stored as `<prefix>ShortcutKey` / `<prefix>ShortcutMods`; modifiers == 0
// means "no shortcut".

import Carbon.HIToolbox
import Foundation

extension AppSettings {
    var ringShortcut: DropletShortcut {
        get { .load("ring", fallback: ShortcutCatalog.defaultBinding(.ring), from: defaults) }
        set { newValue.save("ring", to: defaults) }
    }

    var islandToggleShortcut: DropletShortcut {
        get { .load("islandToggle", fallback: ShortcutCatalog.defaultBinding(.islandToggle), from: defaults) }
        set { newValue.save("islandToggle", to: defaults) }
    }

    var clipboardShortcut: DropletShortcut {
        get { .load("clipboard", fallback: ShortcutCatalog.defaultBinding(.clipboard), from: defaults) }
        set { newValue.save("clipboard", to: defaults) }
    }
}

extension AppSettings {
    /// Opens or closes the floating Notes window from any app. Unassigned by default.
    var showNotesShortcut: DropletShortcut {
        get { .load("showNotes", fallback: ShortcutCatalog.defaultBinding(.showNotes), from: defaults) }
        set { newValue.save("showNotes", to: defaults) }
    }

    /// Starts a new note in the Notes window. Unassigned by default.
    var newNoteShortcut: DropletShortcut {
        get { .load("newNote", fallback: ShortcutCatalog.defaultBinding(.newNote), from: defaults) }
        set { newValue.save("newNote", to: defaults) }
    }
}
