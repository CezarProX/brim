import Foundation
import Testing
@testable import Brim

@Suite("Shelf keyboard shortcuts")
struct ShelfKeyboardShortcutsTests {
  private let a = UUID(), b = UUID(), c = UUID()

  @Test func selectAllTargetsEveryItem() {
    #expect(ShelfShortcut.targets(for: .selectAll, selection: [], items: [a, b, c]) == [a, b, c])
  }

  @Test func deleteNeverFallsBackToTheWholeTray() {
    #expect(ShelfShortcut.targets(for: .remove, selection: [], items: [a, b]).isEmpty)
    #expect(ShelfShortcut.targets(for: .remove, selection: [b], items: [a, b]) == [b])
  }

  @Test func staleSelectionIsIgnored() {
    #expect(ShelfShortcut.targets(for: .copy, selection: [c], items: [a, b]).isEmpty)
  }

  @Test func shortcutsAreDisabledWhenThereIsNothingToDo() {
    let empty = handlers(items: [a, b], selection: [])
    #expect(empty.isEnabled(.selectAll))
    #expect(!empty.isEnabled(.deselect))
    #expect(!empty.isEnabled(.remove))
    let picked = handlers(items: [a, b], selection: [a])
    #expect(picked.isEnabled(.deselect) && picked.isEnabled(.remove) && picked.isEnabled(.copy))
    #expect(!handlers(items: [], selection: []).isEnabled(.selectAll))
  }

  @Test func performRoutesToTheRightHandler() {
    var removed: Set<UUID> = []
    var copied: Set<UUID> = []
    var all: Set<UUID> = []
    let h = ShelfShortcutHandlers(
      items: [a, b], selection: [b], selectAll: { all = $0 }, deselect: {},
      remove: { removed = $0 }, copy: { copied = $0 }, open: { _ in })
    h.perform(.remove); h.perform(.copy); h.perform(.selectAll)
    #expect(removed == [b] && copied == [b] && all == [a, b])
  }

  @Test func keysMatchTheDocumentedBindings() {
    #expect(ShelfShortcut.selectAll.modifiers == .command)
    #expect(ShelfShortcut.copy.modifiers == .command)
    #expect(ShelfShortcut.remove.modifiers.isEmpty)
  }

  private func handlers(items: [UUID], selection: Set<UUID>) -> ShelfShortcutHandlers {
    ShelfShortcutHandlers(
      items: items, selection: selection, selectAll: { _ in }, deselect: {},
      remove: { _ in }, copy: { _ in }, open: { _ in })
  }
}
