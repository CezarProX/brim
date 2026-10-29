// OverlayController+Keyboard.swift
// Brim
//
// Keyboard shortcuts for the capture overlay. Routed from
// `OverlayWindow.performKeyEquivalent(with:)` rather than `keyDown(with:)`:
// AppKit calls `performKeyEquivalent` for every key-down event delivered to
// the key window *before* normal responder-chain dispatch, so this works
// reliably even while an `AnnotationCanvasView` text field is first
// responder (which a plain `keyDown` override on the window would not
// intercept, since the event would be consumed lower in the chain first).

import AppKit

private let kVKEscape = 53
private let kVKReturn = 36
private let kVKKeypadEnter = 76
private let kVKDeleteBackspace = 51
private let kVKForwardDelete = 117

extension OverlayController {

    /// Returns `true` if the event was handled (and should not propagate
    /// further).
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }

        switch Int(event.keyCode) {
        case kVKEscape:
            // Esc is the one shortcut that acts even with no selection.
            if session?.isEditingText == true {
                session?.endTextEditing()
            } else {
                cancelAll()
            }
            return true

        case kVKReturn, kVKKeypadEnter:
            guard selectionRect != nil else { return false }
            if session?.isEditingText == true {
                session?.endTextEditing()
            } else {
                performAction(.confirm)
            }
            return true

        case kVKDeleteBackspace, kVKForwardDelete:
            guard selectionRect != nil else { return false }
            session?.deleteSelected()
            return true

        default:
            break
        }

        guard selectionRect != nil, event.modifierFlags.contains(.command),
              let character = event.charactersIgnoringModifiers?.lowercased().first else {
            return false
        }

        switch character {
        case "c":
            performAction(.copy)
            return true
        case "s":
            performAction(.save)
            return true
        case "u":
            performAction(.upload)
            return true
        case "p":
            performAction(.print)
            return true
        case "z":
            if event.modifierFlags.contains(.shift) {
                session?.redo()
            } else {
                session?.undo()
            }
            return true
        default:
            return false
        }
    }
}
