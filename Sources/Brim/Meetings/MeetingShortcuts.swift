import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// A keyboard shortcut to send to a call app.
struct KeyChord: Equatable {
  let keyCode: Int
  let flags: CGEventFlags

  static let cmdShift: CGEventFlags = [.maskCommand, .maskShift]
}

enum MeetingAction: CaseIterable { case mute, camera, share }

/// The call apps' own keyboard shortcuts, used when a control can't be pressed through Accessibility.
/// Leaving is deliberately absent: it only goes through the confirmed, gated leave flow.
enum MeetingShortcutMap {
  static func chord(_ action: MeetingAction, for app: CallApp) -> KeyChord? {
    switch (app, action) {
    case (.zoom, .mute): KeyChord(keyCode: kVK_ANSI_A, flags: KeyChord.cmdShift)
    case (.zoom, .camera): KeyChord(keyCode: kVK_ANSI_V, flags: KeyChord.cmdShift)
    case (.zoom, .share): KeyChord(keyCode: kVK_ANSI_S, flags: KeyChord.cmdShift)
    case (.teams, .mute): KeyChord(keyCode: kVK_ANSI_M, flags: KeyChord.cmdShift)
    case (.teams, .camera): KeyChord(keyCode: kVK_ANSI_O, flags: KeyChord.cmdShift)
    case (.teams, .share): KeyChord(keyCode: kVK_ANSI_E, flags: KeyChord.cmdShift)
    case (.googleMeet, .mute): KeyChord(keyCode: kVK_ANSI_D, flags: .maskCommand)
    case (.googleMeet, .camera): KeyChord(keyCode: kVK_ANSI_E, flags: .maskCommand)
    default: nil
    }
  }

  /// Browser shortcuts only reach the Meet tab when that browser is in front.
  static func requiresFrontmost(_ app: CallApp) -> Bool { app == .googleMeet }

  static func action(for call: CallAction) -> MeetingAction? {
    switch call {
    case .mute: .mute
    case .camera: .camera
    case .screenShare: .share
    case .leave: nil
    }
  }
}

/// Posts a key chord to a process. Needs Accessibility, which call detection already requires.
enum MeetingShortcutSender {
  @discardableResult
  static func send(_ chord: KeyChord, toPID pid: pid_t) -> Bool {
    guard AXIsProcessTrusted() else { return false }
    let source = CGEventSource(stateID: .combinedSessionState)
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(chord.keyCode), keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(chord.keyCode), keyDown: false)
    else { return false }
    down.flags = chord.flags
    up.flags = chord.flags
    down.postToPid(pid)
    up.postToPid(pid)
    return true
  }
}
