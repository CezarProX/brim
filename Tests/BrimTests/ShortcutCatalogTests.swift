import Carbon.HIToolbox
import Foundation
import Testing

@testable import Brim

@MainActor
struct ShortcutCatalogTests {
  private func isolated() -> AppSettings {
    let name = "shortcut-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return AppSettings(defaults: defaults)
  }

  @Test func defaultsAreUniqueAndValid() {
    let all = Dictionary(uniqueKeysWithValues: ShortcutID.allCases.map { ($0, ShortcutCatalog.defaultBinding($0)) })
    #expect(ShortcutCatalog.duplicates(in: all).isEmpty)
    for id in ShortcutID.allCases {
      #expect(ShortcutCatalog.problem(for: all[id]!, id: id, current: all) == nil, "\(id)")
    }
  }

  @Test func everyShortcutHasAGroupAndTitle() {
    for id in ShortcutID.allCases {
      #expect(!ShortcutCatalog.title(id).isEmpty)
      #expect(ShortcutCatalog.ids(in: ShortcutCatalog.group(id)).contains(id))
    }
  }

  @Test func needsAModifier() {
    let bare = DropletShortcut(keyCode: kVK_ANSI_K, modifiers: Int(shiftKey))
    #expect(ShortcutCatalog.problem(for: bare, id: .ring, current: [:]) == .needsModifier)
  }

  @Test func unsetMeansOffAndIsAlwaysFine() {
    #expect(ShortcutCatalog.problem(for: .none, id: .ring, current: [:]) == nil)
  }

  @Test func systemReservedCombosAreRefused() {
    let quit = DropletShortcut(keyCode: kVK_ANSI_Q, modifiers: Int(cmdKey))
    #expect(ShortcutCatalog.problem(for: quit, id: .ring, current: [:]) == .reservedBySystem("⌘Q"))
    let spotlight = DropletShortcut(keyCode: kVK_Space, modifiers: Int(cmdKey))
    #expect(ShortcutCatalog.reservedName(for: spotlight) == "⌘Space")
    // Extra modifiers make it a different combination.
    let other = DropletShortcut(keyCode: kVK_ANSI_Q, modifiers: Int(cmdKey | optionKey))
    #expect(ShortcutCatalog.reservedName(for: other) == nil)
  }

  @Test func detectsConflictWithAnotherShortcutButNotItself() {
    var current = Dictionary(uniqueKeysWithValues: ShortcutID.allCases.map { ($0, ShortcutCatalog.defaultBinding($0)) })
    let clipboard = current[.clipboard]!
    #expect(ShortcutCatalog.problem(for: clipboard, id: .emoji, current: current) == .usedBy(.clipboard))
    #expect(ShortcutCatalog.problem(for: clipboard, id: .clipboard, current: current) == nil)
    current[.ring] = clipboard
    #expect(ShortcutCatalog.duplicates(in: current).contains { $0.0 == .ring && $0.1 == .clipboard })
  }

  @Test func problemMessagesNameTheOtherFeature() {
    #expect(ShortcutCatalog.Problem.usedBy(.clipboard).message.contains("Clipboard library"))
  }

  @Test func storeRoundTripsFixedShortcutsAndResets() {
    let settings = isolated()
    #expect(ShortcutStore.binding(.ring, settings: settings) == ShortcutCatalog.defaultBinding(.ring))
    let new = DropletShortcut(keyCode: kVK_ANSI_J, modifiers: Int(cmdKey | controlKey))
    #expect(ShortcutStore.set(.ring, to: new, settings: settings, live: false) == nil)
    #expect(settings.ringShortcut == new)
    #expect(ShortcutStore.binding(.ring, settings: settings) == new)
    #expect(ShortcutStore.reset(.ring, settings: settings, live: false) == nil)
    #expect(settings.ringShortcut == ShortcutCatalog.defaultBinding(.ring))
  }

  @Test func storeRefusesConflictsAndDoesNotWrite() {
    let settings = isolated()
    let taken = ShortcutCatalog.defaultBinding(.islandToggle)
    let problem = ShortcutStore.set(.ring, to: taken, settings: settings, live: false)
    #expect(problem == .usedBy(.islandToggle))
    #expect(settings.ringShortcut == ShortcutCatalog.defaultBinding(.ring))
  }

  @Test func storeCanClearAShortcut() {
    let settings = isolated()
    #expect(ShortcutStore.set(.clipboard, to: .none, settings: settings, live: false) == nil)
    #expect(!ShortcutStore.binding(.clipboard, settings: settings).isSet)
  }

  @Test func captureAndEmojiAndMuteMapToTheirOwnKeys() {
    let settings = isolated()
    let capture = DropletShortcut(keyCode: kVK_ANSI_8, modifiers: Int(cmdKey | shiftKey))
    #expect(ShortcutStore.set(.capture, to: capture, settings: settings, live: false) == nil)
    #expect(settings.hotkeyKeyCode == kVK_ANSI_8)
    let emoji = DropletShortcut(keyCode: kVK_ANSI_Y, modifiers: Int(cmdKey | optionKey))
    _ = ShortcutStore.set(.emoji, to: emoji, settings: settings, live: false)
    #expect(settings.emojiHotkeyCode == kVK_ANSI_Y)
    let mute = DropletShortcut(keyCode: kVK_ANSI_U, modifiers: Int(controlKey | optionKey))
    _ = ShortcutStore.set(.muteMics, to: mute, settings: settings, live: false)
    #expect(settings.muteAllMicsKeyCode == kVK_ANSI_U)
  }
}
