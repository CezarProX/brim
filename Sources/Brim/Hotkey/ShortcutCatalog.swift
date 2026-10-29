// ShortcutCatalog.swift
// Brim
//
// Pure description of every global shortcut in the app plus validation (needs a modifier, not a
// system-reserved combo) and conflict detection between our own shortcuts. No Carbon calls here.

import Carbon.HIToolbox
import Foundation

enum ShortcutID: String, CaseIterable, Identifiable, Sendable {
    case capture, ring, islandToggle, clipboard, emoji
    case textCapture, termiNotch, teleprompter, dropClip, muteMics
    case recordScreen
    case showNotes, newNote

    var id: String { rawValue }
}

enum ShortcutGroup: String, CaseIterable, Sendable {
    case capture = "Capture"
    case island = "Island"
    case tools = "Tools"
}

enum ShortcutCatalog {
    static func title(_ id: ShortcutID) -> String {
        switch id {
        case .capture: return "Take a screenshot"
        case .ring: return "Action Ring"
        case .islandToggle: return "Toggle the island"
        case .clipboard: return "Clipboard library"
        case .emoji: return "Emoji picker"
        case .textCapture: return "Text capture (OCR)"
        case .termiNotch: return "Termi-Notch terminal"
        case .teleprompter: return "Teleprompter"
        case .dropClip: return "DropClip"
        case .muteMics: return "Mute all microphones"
        case .recordScreen: return "Record the screen"
        case .showNotes: return "Show notes"
        case .newNote: return "New note"
        }
    }

    static func symbol(_ id: ShortcutID) -> String {
        switch id {
        case .capture: return "camera.viewfinder"
        case .ring: return "circle.dashed"
        case .islandToggle: return "capsule.fill"
        case .clipboard: return "doc.on.clipboard"
        case .emoji: return "face.smiling"
        case .textCapture: return "text.viewfinder"
        case .termiNotch: return "terminal"
        case .teleprompter: return "text.alignleft"
        case .dropClip: return "paperclip"
        case .muteMics: return "mic.slash"
        case .recordScreen: return "record.circle"
        case .showNotes: return "note.text"
        case .newNote: return "square.and.pencil"
        }
    }

    static func group(_ id: ShortcutID) -> ShortcutGroup {
        switch id {
        case .capture, .ring, .textCapture, .recordScreen: return .capture
        case .islandToggle, .clipboard: return .island
        case .emoji, .termiNotch, .teleprompter, .dropClip, .muteMics, .showNotes, .newNote: return .tools
        }
    }

    static func ids(in group: ShortcutGroup) -> [ShortcutID] {
        ShortcutID.allCases.filter { Self.group($0) == group }
    }

    /// Factory binding for each shortcut (matches the values the features shipped with).
    static func defaultBinding(_ id: ShortcutID) -> DropletShortcut {
        let cmd = Int(cmdKey), opt = Int(optionKey), shift = Int(shiftKey), ctrl = Int(controlKey)
        switch id {
        case .capture: return DropletShortcut(keyCode: kVK_ANSI_9, modifiers: cmd | shift)
        case .ring: return DropletShortcut(keyCode: kVK_ANSI_R, modifiers: opt | cmd)
        case .islandToggle: return DropletShortcut(keyCode: kVK_ANSI_N, modifiers: opt | cmd)
        case .clipboard: return DropletShortcut(keyCode: kVK_Space, modifiers: opt | shift)
        case .emoji: return DropletShortcut(keyCode: kVK_ANSI_E, modifiers: opt | cmd)
        case .textCapture: return DropletShortcut(keyCode: 17, modifiers: opt | ctrl)
        case .termiNotch: return DropletShortcut(keyCode: 50, modifiers: ctrl)
        case .teleprompter: return DropletShortcut(keyCode: 35, modifiers: opt | ctrl)
        case .dropClip: return DropletShortcut(keyCode: 2, modifiers: opt | ctrl)
        case .muteMics: return DropletShortcut(keyCode: 46, modifiers: opt | ctrl)
        case .recordScreen: return AppSettings.defaultRecordScreenShortcut
        case .showNotes, .newNote: return .none  // unassigned until the user picks a key
        }
    }

    // MARK: Validation

    /// Why a binding cannot be used, or nil when it is acceptable.
    enum Problem: Equatable {
        case needsModifier
        case reservedBySystem(String)
        case usedBy(ShortcutID)

        var message: String {
            switch self {
            case .needsModifier: return "Include at least one of ⌘, ⌃ or ⌥."
            case .reservedBySystem(let name): return "\(name) is reserved by macOS."
            case .usedBy(let other): return "Already used by \(ShortcutCatalog.title(other))."
            }
        }
    }

    private static let primaryMask = Int(cmdKey | controlKey | optionKey)

    /// Combinations macOS or nearly every app owns; registering them globally would break typing.
    static func reservedName(for binding: DropletShortcut) -> String? {
        let mods = binding.modifiers & Int(cmdKey | controlKey | optionKey | shiftKey)
        let cmd = Int(cmdKey)
        let table: [(Int, Int, String)] = [
            (kVK_Space, cmd, "⌘Space"), (kVK_Tab, cmd, "⌘Tab"), (kVK_ANSI_Q, cmd, "⌘Q"),
            (kVK_ANSI_W, cmd, "⌘W"), (kVK_ANSI_H, cmd, "⌘H"), (kVK_ANSI_C, cmd, "⌘C"),
            (kVK_ANSI_V, cmd, "⌘V"), (kVK_ANSI_X, cmd, "⌘X"), (kVK_ANSI_Z, cmd, "⌘Z"),
            (kVK_ANSI_A, cmd, "⌘A"), (kVK_ANSI_S, cmd, "⌘S"),
            (kVK_Space, Int(cmdKey | optionKey), "⌥⌘Space"), (kVK_Escape, Int(cmdKey | optionKey), "⌥⌘⎋"),
            (kVK_ANSI_3, Int(cmdKey | shiftKey), "⌘⇧3"), (kVK_ANSI_4, Int(cmdKey | shiftKey), "⌘⇧4"),
            (kVK_ANSI_5, Int(cmdKey | shiftKey), "⌘⇧5"),
        ]
        return table.first { $0.0 == binding.keyCode && $0.1 == mods }?.2
    }

    /// Validates `binding` for shortcut `id` against the other current bindings.
    /// An unset binding (modifiers == 0) is always fine: it means "off".
    static func problem(
        for binding: DropletShortcut, id: ShortcutID, current: [ShortcutID: DropletShortcut]
    ) -> Problem? {
        guard binding.isSet else { return nil }
        if binding.modifiers & primaryMask == 0 { return .needsModifier }
        if let name = reservedName(for: binding) { return .reservedBySystem(name) }
        let clash = ShortcutID.allCases.first { other in
            guard other != id, let existing = current[other], existing.isSet else { return false }
            return existing.keyCode == binding.keyCode && existing.modifiers == binding.modifiers
        }
        return clash.map(Problem.usedBy)
    }

    /// Every pair of shortcuts that currently share the same binding (for a startup sanity check).
    static func duplicates(in current: [ShortcutID: DropletShortcut]) -> [(ShortcutID, ShortcutID)] {
        let ids = ShortcutID.allCases.filter { current[$0]?.isSet == true }
        var pairs: [(ShortcutID, ShortcutID)] = []
        for (i, a) in ids.enumerated() {
            for b in ids.dropFirst(i + 1) where current[a] == current[b] { pairs.append((a, b)) }
        }
        return pairs
    }
}
