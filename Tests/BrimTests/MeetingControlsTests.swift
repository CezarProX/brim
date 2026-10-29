import Carbon.HIToolbox
import Foundation
import Testing

@testable import Brim

@MainActor
struct MeetingControlsTests {
  final class FakeInputs: AudioInputControlling {
    var muted: [UInt32: Bool?]
    var failing: Set<UInt32> = []
    init(_ muted: [UInt32: Bool?]) { self.muted = muted }
    func inputDevices() -> [UInt32] { muted.keys.sorted() }
    func isMuted(_ device: UInt32) -> Bool? { muted[device] ?? nil }
    func setMuted(_ device: UInt32, _ value: Bool) -> Bool {
      guard !failing.contains(device) else { return false }
      muted[device] = .some(value)
      return true
    }
  }

  @Test func toggleMutesEveryMicrophoneThenUnmutesThem() {
    let fake = FakeInputs([1: false, 2: false, 3: true])
    let controller = MicrophoneMuteController(inputs: fake)
    #expect(controller.isMuted == false)
    #expect(controller.toggle(announce: false) == true)
    #expect(fake.muted[1] == .some(true) && fake.muted[2] == .some(true) && fake.muted[3] == .some(true))
    #expect(controller.isMuted)
    #expect(controller.toggle(announce: false) == false)
    #expect(fake.muted.values.allSatisfy { $0 == .some(false) })
  }

  @Test func devicesWithoutMuteAreSkippedAndAnAllUnsupportedSetupReportsNil() {
    let mixed = FakeInputs([1: false, 2: .none])
    #expect(MicrophoneMuteController(inputs: mixed).toggle(announce: false) == true)
    #expect(mixed.muted[2] == .some(nil))
    let none = FakeInputs([5: .none])
    #expect(MicrophoneMuteController(inputs: none).toggle(announce: false) == nil)
    let failing = FakeInputs([9: false])
    failing.failing = [9]
    #expect(MicrophoneMuteController(inputs: failing).toggle(announce: false) == nil)
  }

  @Test func muteLogicPrefersMutingWhenAnyMicIsLive() {
    #expect(MicrophoneMuteLogic.target(states: [true, false]) == true)
    #expect(MicrophoneMuteLogic.target(states: [true, true]) == false)
    #expect(MicrophoneMuteLogic.target(states: [nil, nil]) == true)
    #expect(MicrophoneMuteLogic.isMuted(states: [true, nil]))
    #expect(!MicrophoneMuteLogic.isMuted(states: [true, false]))
    #expect(!MicrophoneMuteLogic.isMuted(states: []))
  }

  @Test func appShortcutsMatchEachProvider() {
    let shiftCmd = KeyChord.cmdShift
    #expect(MeetingShortcutMap.chord(.mute, for: .zoom) == KeyChord(keyCode: kVK_ANSI_A, flags: shiftCmd))
    #expect(MeetingShortcutMap.chord(.camera, for: .zoom) == KeyChord(keyCode: kVK_ANSI_V, flags: shiftCmd))
    #expect(MeetingShortcutMap.chord(.mute, for: .teams) == KeyChord(keyCode: kVK_ANSI_M, flags: shiftCmd))
    #expect(MeetingShortcutMap.chord(.camera, for: .teams) == KeyChord(keyCode: kVK_ANSI_O, flags: shiftCmd))
    #expect(MeetingShortcutMap.chord(.mute, for: .googleMeet) == KeyChord(keyCode: kVK_ANSI_D, flags: .maskCommand))
    #expect(MeetingShortcutMap.chord(.camera, for: .googleMeet) == KeyChord(keyCode: kVK_ANSI_E, flags: .maskCommand))
    #expect(MeetingShortcutMap.chord(.share, for: .googleMeet) == nil)
    #expect(MeetingShortcutMap.chord(.mute, for: .faceTime) == nil)
    #expect(MeetingShortcutMap.requiresFrontmost(.googleMeet))
    #expect(!MeetingShortcutMap.requiresFrontmost(.zoom))
  }

  @Test func leavingNeverMapsToAShortcut() {
    #expect(MeetingShortcutMap.action(for: .leave) == nil)
    #expect(MeetingShortcutMap.action(for: .mute) == .mute)
    #expect(MeetingShortcutMap.action(for: .screenShare) == .share)
    for app in CallApp.allCases { for action in MeetingAction.allCases { _ = MeetingShortcutMap.chord(action, for: app) } }
  }

  @Test func muteAllDefaultsDoNotCollideWithTheAppsOtherShortcuts() {
    let defaults = AppSettings(defaults: UserDefaults(suiteName: "meet-\(UUID().uuidString)")!)
    #expect(defaults.muteAllMicsKeyCode == kVK_ANSI_M)
    #expect(defaults.muteAllMicsModifiers == controlKey | optionKey)
    #expect(defaults.muteAllMicsKeyCode != defaults.hotkeyKeyCode)  // screenshot is Cmd+Shift+9
    #expect(!(defaults.muteAllMicsKeyCode == kVK_ANSI_R && defaults.muteAllMicsModifiers == optionKey | cmdKey))  // Ring
  }
}
