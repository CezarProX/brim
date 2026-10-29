// EditorKeyCommand.swift
// Brim
//
// Keyboard shortcuts of the "Edit screenshot" window, as a pure mapping
// from a key press to a command so it can be tested without events.

import AppKit

enum EditorKeyCommand: Equatable {
    case escape
    case close
    case copy
    case save
    case done
    case undo
    case redo
    case delete
    case zoomIn
    case zoomOut
    case actualSize
    case zoomToFit
    case toggleSidebar
    case tool(AnnotationTool?)

    static let escapeKeyCode: UInt16 = 53
    static let deleteKeyCodes: Set<UInt16> = [51, 117]
    static let returnKeyCodes: Set<UInt16> = [36, 76]

    /// - Parameter isEditingText: an inline text field owns plain keys,
    ///   Delete and the standard editing shortcuts while it is active.
    @MainActor
    static func command(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags,
                        isEditingText: Bool) -> EditorKeyCommand? {
        let flags = modifiers.intersection([.command, .shift, .option, .control])
        if keyCode == escapeKeyCode { return .escape }
        let key = characters?.lowercased() ?? ""
        if flags.contains(.command) {
            return commandShortcut(key: key, keyCode: keyCode, shift: flags.contains(.shift), isEditingText: isEditingText)
        }
        guard !isEditingText, flags.subtracting(.shift).isEmpty else { return nil }
        if deleteKeyCodes.contains(keyCode) { return .delete }
        guard key.count == 1, let char = key.first, let item = EditorToolItem.item(forShortcut: char) else { return nil }
        return .tool(item.tool)
    }

    private static func commandShortcut(key: String, keyCode: UInt16, shift: Bool, isEditingText: Bool) -> EditorKeyCommand? {
        switch key {
        case "w": return .close
        case "s": return .save
        case "=", "+": return .zoomIn
        case "-": return .zoomOut
        case "0": return .actualSize
        case "9": return .zoomToFit
        case "\\": return .toggleSidebar
        case "c": return isEditingText ? nil : .copy
        case "z": return isEditingText ? nil : (shift ? .redo : .undo)
        default: return returnKeyCodes.contains(keyCode) ? .done : nil
        }
    }
}
