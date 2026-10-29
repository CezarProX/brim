import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A click-to-record shortcut field. Reports (keyCode, carbonModifiers, key label).
struct ShortcutField: NSViewRepresentable {
  let display: String
  let onRecord: (Int, Int, String) -> Void

  func makeNSView(context: Context) -> RecorderView {
    let view = RecorderView()
    view.onRecord = onRecord
    return view
  }

  func updateNSView(_ view: RecorderView, context: Context) {
    view.onRecord = onRecord
    view.display = display
  }

  final class RecorderView: NSView {
    var onRecord: ((Int, Int, String) -> Void)?
    var display = "" { didSet { needsDisplay = true } }
    private var recording = false { didSet { needsDisplay = true } }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 130, height: 24) }

    override func mouseDown(with event: NSEvent) {
      recording = true
      window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
      recording = false
      return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
      guard recording else { return super.keyDown(with: event) }
      if event.keyCode == UInt16(kVK_Escape) {
        recording = false
        return
      }
      let mods = Int(Self.carbon(event.modifierFlags))
      guard mods != 0, let label = event.charactersIgnoringModifiers?.uppercased(), !label.isEmpty else {
        NSSound.beep()
        return
      }
      recording = false
      onRecord?(Int(event.keyCode), mods, label == " " ? "Space" : label)
    }

    override func draw(_ dirtyRect: NSRect) {
      let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
      (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
      path.fill()
      (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
      path.stroke()
      let text = recording ? "Type shortcut…" : (display.isEmpty ? "Click to set" : display)
      let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor,
      ]
      let size = text.size(withAttributes: attributes)
      text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }

    static func carbon(_ flags: NSEvent.ModifierFlags) -> UInt32 {
      var mask: UInt32 = 0
      if flags.contains(.command) { mask |= UInt32(cmdKey) }
      if flags.contains(.option) { mask |= UInt32(optionKey) }
      if flags.contains(.control) { mask |= UInt32(controlKey) }
      if flags.contains(.shift) { mask |= UInt32(shiftKey) }
      return mask
    }
  }
}
