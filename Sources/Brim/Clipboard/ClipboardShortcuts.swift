// ClipboardShortcuts.swift
// Brim
//
// The library's keyboard map. Pure, so it can be tested without a window.

import Foundation

enum ClipboardKey: Equatable {
    case character(Character)
    case left, right, up, down, returnKey, escape, delete
}

enum ClipboardShortcut: Equatable {
    case copy, deleteItem, focusSearch, togglePin, toggleBlur, saveAs, tag, selectAll, pasteAll
    case move(Int)
    case activate, cancel, toggleSelect
}

enum ClipboardShortcuts {
    /// What a key press means in the library. `searching` means the search field has focus, where
    /// only Escape and the arrows keep their meaning so typing and ⌘C/⌘A behave normally.
    static func command(for key: ClipboardKey, command: Bool, shift: Bool, option: Bool,
                        searching: Bool) -> ClipboardShortcut? {
        if searching {
            switch key {
            case .escape: return .cancel
            case .down where !command: return .move(0)
            case .returnKey where !command: return .move(0)
            default: return nil
            }
        }
        switch key {
        case .left: return .move(-1)
        case .right: return .move(1)
        case .up: return .move(-1)
        case .down: return .move(1)
        case .returnKey: return command ? .pasteAll : .activate
        case .escape: return .cancel
        case .delete: return command ? .deleteItem : nil
        case .character(let raw):
            let character = Character(raw.lowercased())
            if command, !option {
                switch character {
                case "c": return .copy
                case "d": return .deleteItem
                case "f": return .focusSearch
                case "p": return .togglePin
                case "b": return .toggleBlur
                case "s": return shift ? .saveAs : nil
                case "t": return .tag
                case "a": return .selectAll
                default: return nil
                }
            }
            if !command, character == " " { return .toggleSelect }
            return nil
        }
    }
}
