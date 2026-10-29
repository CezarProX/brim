import Carbon.HIToolbox
import Foundation

/// Display helpers for Carbon modifier masks, shared by the Droplets shortcut fields.
enum HotkeyFormat {
  static func modifierSymbols(_ carbon: Int) -> String {
    let flags = UInt32(truncatingIfNeeded: carbon)
    var text = ""
    if flags & UInt32(controlKey) != 0 { text += "⌃" }
    if flags & UInt32(optionKey) != 0 { text += "⌥" }
    if flags & UInt32(shiftKey) != 0 { text += "⇧" }
    if flags & UInt32(cmdKey) != 0 { text += "⌘" }
    return text
  }
}
