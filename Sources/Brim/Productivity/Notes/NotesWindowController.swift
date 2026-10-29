import AppKit
import SwiftUI
import os

/// Owns the floating Notes window. It shows the same `NotesModel` as the island, so a note edited in
/// one place is the note in the other.
@MainActor
final class NotesWindowController: NSObject, NSWindowDelegate {
  static let shared = NotesWindowController()
  static let frameName = "BrimNotesWindow"
  private static let log = Logger(subsystem: "Brim", category: "NotesWindow")

  private var window: NSWindow?
  private let notes: NotesModel
  private override init() { notes = .shared }

  var isVisible: Bool { window?.isVisible == true }

  func show(noteID: UUID? = nil) {
    if let noteID, notes.notes.contains(where: { $0.id == noteID }) { notes.selectedID = noteID }
    if notes.notes.isEmpty { notes.create() }
    let window = self.window ?? makeWindow()
    self.window = window
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func toggle() {
    if let window, window.isVisible, window.isKeyWindow { window.close() } else { show() }
  }

  /// Starts an empty note and puts the caret in it.
  func newNote() {
    notes.create()
    show()
  }

  /// Hands the note back to the island, opened on the Notes widget.
  func sendToNotch(_ id: UUID) {
    notes.selectedID = id
    window?.close()
    NotchShelfController.shared.presentWidget(.notes)
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 780, height: 520),
      styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window.standardWindowButton(.zoomButton)?.isHidden = true
    window.appearance = NSAppearance(named: .darkAqua)
    window.backgroundColor = NSColor(white: 0.105, alpha: 1)
    GlassWindowChrome.apply(to: window)
    window.isMovableByWindowBackground = false
    window.level = .floating
    window.hidesOnDeactivate = false
    window.isReleasedWhenClosed = false
    window.contentMinSize = NSSize(width: 520, height: 340)
    window.title = "Notes"
    window.delegate = self
    window.contentView = NSHostingView(
      rootView: NotesWindowView(notes: notes, sendToNotch: { [weak self] in self?.sendToNotch($0) }))
    if !window.setFrameUsingName(Self.frameName) { window.center() }
    window.setFrameAutosaveName(Self.frameName)
    Self.log.debug("created the Notes window")
    return window
  }

  func windowWillClose(_ notification: Notification) {
    window?.saveFrame(usingName: Self.frameName)
  }
}
