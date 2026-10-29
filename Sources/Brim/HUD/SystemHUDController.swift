import AudioToolbox
import AppKit
import CoreAudio
import SwiftUI

/// Owns the event tap that replaces the macOS volume / brightness / keyboard-backlight
/// pop-ups and the ⌘Q guard, and the CoreAudio listener that shows volume changes made elsewhere.
@MainActor
final class SystemHUDController: ObservableObject {
  static let shared = SystemHUDController()
  @Published private(set) var accessibilityTrusted = MediaKeyTap.isTrusted
  @Published private(set) var tapRunning = false

  private var tap: MediaKeyTap?
  private var trustTimer: Timer?
  private var consumedKeys: Set<Int> = []
  private var quitGuard = QuitGuardPolicy()
  private var volumeListener: VolumeChangeListener?
  private var lastVolumeShown: SystemVolumeControl.State?
  private var lastOwnVolumeChange = Date.distantPast
  private let flashes = IslandFlashCenter.shared

  private var settings: AppSettings { .shared }
  /// The tap is needed whenever any key-swallowing feature is on.
  var wantsTap: Bool {
    settings.hudReplaceVolume || settings.hudReplaceBrightness || settings.hudReplaceKeyboardBacklight
      || settings.hudQuitGuard
  }

  /// Call at launch and whenever a HUD setting changes.
  func refresh() {
    accessibilityTrusted = MediaKeyTap.isTrusted
    if wantsTap {
      if tap == nil { tap = MediaKeyTap { [weak self] type, event in self?.handle(type, event) ?? false } }
      tapRunning = tap?.start(includingKeyDown: settings.hudQuitGuard) ?? false
    } else {
      tap?.stop()
      tapRunning = false
    }
    updateTrustPolling()
    updateVolumeListener()
  }

  /// Opens the Accessibility prompt; the tap starts by itself once trust is granted.
  func requestAccessibility() {
    MediaKeyTap.requestTrust()
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
    }
    refresh()
  }

  func stop() {
    tap?.stop()
    tapRunning = false
    trustTimer?.invalidate()
    trustTimer = nil
    volumeListener = nil
  }

  private func updateTrustPolling() {
    let needsPolling = wantsTap && !tapRunning
    if needsPolling, trustTimer == nil {
      trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
        Task { @MainActor in self?.refresh() }
      }
    } else if !needsPolling {
      trustTimer?.invalidate()
      trustTimer = nil
    }
  }

  // MARK: Event routing

  private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
    if type == .keyDown { return handleQuit(event) }
    guard type.rawValue == MediaKeyEvent.systemDefinedType, let ns = NSEvent(cgEvent: event),
      let key = MediaKeyEvent.decode(ns)
    else { return false }
    return handleMedia(key)
  }

  private func handleMedia(_ event: MediaKeyEvent) -> Bool {
    guard enabled(event.key.kind) else { return false }
    if !event.isDown { return consumedKeys.remove(event.key.rawValue) != nil }
    let handled: Bool
    switch event.key.kind {
    case .volume: handled = adjustVolume(event)
    case .brightness: handled = adjustBrightness(event)
    case .keyboard: handled = adjustKeyboard(event)
    }
    if handled { consumedKeys.insert(event.key.rawValue) }
    return handled
  }

  private func enabled(_ kind: MediaKey.Kind) -> Bool {
    switch kind {
    case .volume: return settings.hudReplaceVolume
    case .brightness: return settings.hudReplaceBrightness
    case .keyboard: return settings.hudReplaceKeyboardBacklight
    }
  }

  private func adjustVolume(_ event: MediaKeyEvent) -> Bool {
    guard !(event.key == .mute && event.isRepeat),
      let state = SystemVolumeControl.handle(event.key, fine: event.isFine)
    else { return event.key == .mute && event.isRepeat }
    lastOwnVolumeChange = .now
    showVolume(state)
    return true
  }

  private func adjustBrightness(_ event: MediaKeyEvent) -> Bool {
    guard let level = DisplayBrightnessControl.shared.step(direction: event.key.direction, fine: event.isFine)
    else { return false }
    if EdgeSliderController.shared.show(.brightness, level: level) { return true }
    flashes.show(
      "Display", symbol: HUDSymbol.brightness(level: level), tint: HUDTint.color(hex: settings.hudBrightnessTintHex),
      value: level, duration: 1.6, kind: .brightness)
    return true
  }

  private func adjustKeyboard(_ event: MediaKeyEvent) -> Bool {
    guard let level = KeyboardBacklightControl.shared.step(direction: event.key.direction, fine: event.isFine)
    else { return false }
    flashes.show(
      "Keyboard", symbol: HUDSymbol.keyboard(level: level), tint: HUDTint.color(hex: settings.hudBrightnessTintHex),
      value: level, duration: 1.6, kind: .keyboard)
    return true
  }

  private func showVolume(_ state: SystemVolumeControl.State) {
    lastVolumeShown = state
    if EdgeSliderController.shared.show(.volume, level: state.level, muted: state.muted) { return }
    flashes.show(
      state.muted ? "Muted" : "Volume", symbol: HUDSymbol.volume(level: state.level, muted: state.muted),
      tint: state.muted ? .red : HUDTint.color(hex: settings.hudVolumeTintHex), value: state.muted ? 0 : state.level,
      duration: 1.6, kind: .volume)
  }

  // MARK: ⌘Q guard

  private static let quitKeyCode: Int64 = 12

  private func handleQuit(_ event: CGEvent) -> Bool {
    guard settings.hudQuitGuard, event.getIntegerValueField(.keyboardEventKeycode) == Self.quitKeyCode else {
      return false
    }
    let flags = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
    guard flags == .maskCommand, let app = NSWorkspace.shared.frontmostApplication,
      app.bundleIdentifier != Bundle.main.bundleIdentifier, app.bundleIdentifier != "com.apple.finder"
    else { return false }
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    switch quitGuard.decide(now: .now, bundleID: app.bundleIdentifier, isRepeat: isRepeat) {
    case .allow: return false
    case .swallow: return true
    case .announce:
      let name = app.localizedName ?? "this app"
      flashes.show(
        "Press ⌘Q again to quit \(name)", symbol: "command", tint: .orange, duration: QuitGuardPolicy.confirmWindow,
        kind: .quitGuard, shortTitle: "Quit \(name)?")
      return true
    }
  }

  // MARK: Volume changes made elsewhere

  private func updateVolumeListener() {
    let want = settings.hudReplaceVolume && settings.hudObserveVolume
    if want, volumeListener == nil {
      volumeListener = VolumeChangeListener { [weak self] in self?.externalVolumeChanged() }
    } else if !want {
      volumeListener = nil
    }
  }

  private func externalVolumeChanged() {
    guard Date.now.timeIntervalSince(lastOwnVolumeChange) > 0.3, let state = SystemVolumeControl.read(),
      state != lastVolumeShown
    else { return }
    showVolume(state)
  }
}

/// Calls back on the main queue when the default output device's volume or mute changes, or
/// when the default device itself changes.
final class VolumeChangeListener {
  private let onChange: @MainActor () -> Void
  private var device: AudioDeviceID?
  private var deviceBlock: AudioObjectPropertyListenerBlock?
  private var systemBlock: AudioObjectPropertyListenerBlock?

  private static var defaultDeviceAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
  private static let selectors: [AudioObjectPropertySelector] = [
    kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute,
  ]

  init(onChange: @escaping @MainActor () -> Void) {
    self.onChange = onChange
    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      DispatchQueue.main.async { self?.rebind(); self?.fire() }
    }
    systemBlock = block
    var address = Self.defaultDeviceAddress
    AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
    rebind()
  }

  deinit {
    var address = Self.defaultDeviceAddress
    if let systemBlock {
      AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, systemBlock)
    }
    unbind()
  }

  private func fire() { MainActor.assumeIsolated { onChange() } }

  private func rebind() {
    guard let current = SystemVolumeControl.defaultOutputDevice(), current != device else { return }
    unbind()
    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.fire() }
    for selector in Self.selectors {
      var address = AudioObjectPropertyAddress(
        mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
      AudioObjectAddPropertyListenerBlock(current, &address, .main, block)
    }
    device = current
    deviceBlock = block
  }

  private func unbind() {
    guard let device, let deviceBlock else { return }
    for selector in Self.selectors {
      var address = AudioObjectPropertyAddress(
        mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
      AudioObjectRemovePropertyListenerBlock(device, &address, .main, deviceBlock)
    }
    self.device = nil
    self.deviceBlock = nil
  }
}
