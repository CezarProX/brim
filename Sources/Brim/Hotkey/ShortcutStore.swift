// ShortcutStore.swift
// Brim
//
// Reads, writes and applies every global shortcut through one place so the unified Shortcuts page
// does not need to know where each feature keeps its binding or how it re-registers.

import Carbon.HIToolbox
import Foundation

@MainActor
enum ShortcutStore {
    static func binding(_ id: ShortcutID, settings: AppSettings = .shared) -> DropletShortcut {
        switch id {
        case .capture: return DropletShortcut(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)
        case .ring: return settings.ringShortcut
        case .islandToggle: return settings.islandToggleShortcut
        case .clipboard: return settings.clipboardShortcut
        case .emoji: return DropletShortcut(keyCode: settings.emojiHotkeyCode, modifiers: settings.emojiHotkeyModifiers)
        case .textCapture: return settings.textCaptureShortcut
        case .termiNotch: return settings.termiNotchShortcut
        case .teleprompter: return settings.teleprompterShortcut
        case .dropClip: return settings.dropClipShortcut
        case .muteMics: return DropletShortcut(keyCode: settings.muteAllMicsKeyCode, modifiers: settings.muteAllMicsModifiers)
        case .recordScreen: return settings.recordScreenShortcut
        case .showNotes: return settings.showNotesShortcut
        case .newNote: return settings.newNoteShortcut
        }
    }

    static func allBindings(settings: AppSettings = .shared) -> [ShortcutID: DropletShortcut] {
        Dictionary(uniqueKeysWithValues: ShortcutID.allCases.map { ($0, binding($0, settings: settings)) })
    }

    /// Validates, persists and live-registers a new binding. Returns the problem when it is refused.
    @discardableResult
    static func set(
        _ id: ShortcutID, to new: DropletShortcut, settings: AppSettings = .shared, live: Bool = true
    ) -> ShortcutCatalog.Problem? {
        if let problem = ShortcutCatalog.problem(for: new, id: id, current: allBindings(settings: settings)) {
            return problem
        }
        write(id, new, settings: settings)
        if live { apply(id) }
        return nil
    }

    static func reset(_ id: ShortcutID, settings: AppSettings = .shared, live: Bool = true) -> ShortcutCatalog.Problem? {
        set(id, to: ShortcutCatalog.defaultBinding(id), settings: settings, live: live)
    }

    /// Resets every shortcut. Writes all defaults first (defaults never clash with each other), then applies.
    static func resetAll(settings: AppSettings = .shared) {
        for id in ShortcutID.allCases { write(id, ShortcutCatalog.defaultBinding(id), settings: settings) }
        for id in ShortcutID.allCases { apply(id) }
    }

    private static func write(_ id: ShortcutID, _ new: DropletShortcut, settings: AppSettings) {
        switch id {
        case .capture:
            settings.hotkeyKeyCode = new.keyCode
            settings.hotkeyModifiers = new.modifiers
        case .ring: settings.ringShortcut = new
        case .islandToggle: settings.islandToggleShortcut = new
        case .clipboard: settings.clipboardShortcut = new
        case .emoji:
            settings.emojiHotkeyCode = new.keyCode
            settings.emojiHotkeyModifiers = new.modifiers
            settings.emojiHotkeyLabel = new.isSet ? ShortcutRecorderView.keyString(for: new.keyCode) : ""
        case .textCapture: settings.textCaptureShortcut = new
        case .termiNotch: settings.termiNotchShortcut = new
        case .teleprompter: settings.teleprompterShortcut = new
        case .dropClip: settings.dropClipShortcut = new
        case .muteMics:
            settings.muteAllMicsKeyCode = new.keyCode
            settings.muteAllMicsModifiers = new.modifiers
        case .recordScreen: settings.recordScreenShortcut = new
        case .showNotes: settings.showNotesShortcut = new
        case .newNote: settings.newNoteShortcut = new
        }
    }

    /// Re-registers the feature that owns `id` so the change takes effect immediately.
    private static func apply(_ id: ShortcutID) {
        switch id {
        case .capture: HotkeyManager.shared.reregister()
        case .ring: HotkeyManager.shared.reregisterRing()
        case .islandToggle:
            ShellHotkey.shared.unregister()
            NotchShelfController.shared.settingsChanged()
        case .clipboard:
            ClipboardHotkey.shared.unregister()
            ClipboardFeature.shared.applySettings()
        case .emoji: EmojiPickerController.shared.start()
        case .textCapture: TextCaptureController.shared.settingsChanged()
        case .termiNotch: TermiNotchController.shared.settingsChanged()
        case .teleprompter: TeleprompterController.shared.settingsChanged()
        case .dropClip: DropClipController.shared.settingsChanged()
        case .muteMics: MeetingHotkey.shared.register()
        case .recordScreen: RecordingController.shared.registerHotkey()
        case .showNotes, .newNote: NotesHotkeys.shared.settingsChanged()
        }
    }
}
