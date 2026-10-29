import AppKit
import IOKit.pwr_mgt
import IOKit.ps
import SwiftUI

/// Stay Awake beyond the basic toggle: display or system only, power-adapter and schedule
/// triggers, and lid-closed operation on power. The display-on case reuses `KeepAwakeModel`, so
/// the island's Keep Awake tile stays in sync; system-only uses its own assertion.
@MainActor
final class StayAwakeController: ObservableObject {
  static let shared = StayAwakeController()
  @Published private(set) var isActive = false
  @Published private(set) var lidClosedActive = false
  @Published private(set) var lastError: String?
  private var manual = false
  private var engaged = false
  private var ownAssertion: IOPMAssertionID = 0
  private var timer: Timer?
  private var powerSource: CFRunLoopSource?
  private let settings = AppSettings.shared
  private var lidGate = LidClosedGate()

  /// Starts watching triggers. Call at launch and after settings change.
  func start() {
    stop()
    lidGate.userChangedSettings()
    timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.reconcile() }
    }
    let context = Unmanaged.passUnretained(self).toOpaque()
    if let source = IOPSNotificationCreateRunLoopSource({ ctx in
      guard let ctx else { return }
      let controller = Unmanaged<StayAwakeController>.fromOpaque(ctx).takeUnretainedValue()
      Task { @MainActor in controller.reconcile() }
    }, context)?.takeRetainedValue() {
      powerSource = source
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }
    if settings.defaults.bool(forKey: "stayAwakeLidActive"), !lidClosedActive {
      IslandFlashCenter.shared.show(
        "Lid-closed Stay Awake may still be on", symbol: "exclamationmark.triangle.fill", tint: .orange,
        detail: "Turn it off in Settings > Home & Widgets > Stay Awake")
    }
    reconcile()
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
    powerSource = nil
  }

  /// Releases everything, including lid-closed mode. Call when the app quits.
  func shutdown() {
    stop()
    manual = false
    disengage()
  }

  /// Quitting while lid-closed mode is on must turn it off first, or the Mac would ignore the lid on
  /// battery after Brim is gone. Calls `completion` once the prompt is answered (or at once).
  func releaseLidBeforeQuit(completion: @escaping @MainActor () -> Void) {
    guard lidClosedActive else { return completion() }
    Task {
      await setLidClosed(false)
      completion()
    }
  }

  func toggle() {
    manual.toggle()
    reconcile()
  }

  /// Applies the current options and triggers; safe to call often.
  func reconcile(now: Date = .now) {
    let options = settings.stayAwakeOptions
    let adapter = Self.onAdapter()
    let wanted = manual || StayAwakePolicy.triggerWantsAwake(options, onAdapter: adapter, now: now)
    if wanted && !engaged { engage(options) } else if !wanted && engaged { disengage() }
    let lid = StayAwakePolicy.lidClosedWanted(options, awake: engaged, onAdapter: adapter)
    if lidGate.shouldChange(wanted: lid, active: lidClosedActive) { Task { await setLidClosed(lid) } }
  }

  // MARK: Engage

  private func engage(_ options: StayAwakeOptions) {
    if options.keepDisplayOn {
      let model = KeepAwakeModel.shared
      guard !model.isActive else { engaged = true; isActive = true; return }
      model.start(minutes: nil)
      engaged = model.isActive
    } else {
      var id: IOPMAssertionID = 0
      let result = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
        "Brim Stay Awake (system)" as CFString, &id)
      guard result == kIOReturnSuccess else {
        lastError = "Couldn’t keep the Mac awake."
        return
      }
      ownAssertion = id
      engaged = true
      IslandFlashCenter.shared.show("Awake", symbol: "cup.and.saucer.fill", tint: .yellow, detail: "Display may sleep")
    }
    isActive = engaged
  }

  private func disengage() {
    if ownAssertion != 0 {
      IOPMAssertionRelease(ownAssertion)
      ownAssertion = 0
      IslandFlashCenter.shared.show("Sleep allowed", symbol: "moon.zzz.fill", tint: .white)
    } else if engaged, KeepAwakeModel.shared.isActive {
      KeepAwakeModel.shared.stop()
    }
    engaged = false
    isActive = false
  }

  // MARK: Lid closed

  /// Runs `pmset -a disablesleep` after the system's administrator prompt.
  func setLidClosed(_ on: Bool) async {
    lidGate.inFlight = true
    let script = StayAwakePolicy.lidClosedScript(enable: on)
    let result = await DropletProcess.run("/usr/bin/osascript", ["-e", script], timeout: 120)
    let succeeded = result?.status == 0
    lidGate.finished(turningOn: on, succeeded: succeeded)
    guard succeeded else {
      lastError = on ? "Couldn’t turn on lid-closed mode. An administrator password is required." : "Couldn’t turn off lid-closed mode."
      if on { settings.stayAwakeLidClosedOnPower = false }
      return
    }
    lastError = nil
    lidClosedActive = on
    settings.defaults.set(on, forKey: "stayAwakeLidActive")
    IslandFlashCenter.shared.show(on ? "Lid-closed mode on" : "Lid-closed mode off", symbol: "laptopcomputer", tint: on ? .yellow : .white)
  }

  static func onAdapter() -> Bool {
    guard let type = IOPSGetProvidingPowerSourceType(nil)?.takeRetainedValue() as String? else { return true }
    return type == kIOPMACPowerKey
  }
}

/// Keeps lid-closed changes to one administrator prompt at a time, and stops re-asking every 30 s
/// after the user cancels turning it off (Settings or the next launch offer it again).
struct LidClosedGate {
  var inFlight = false
  private(set) var declinedOff = false

  func shouldChange(wanted: Bool, active: Bool) -> Bool {
    guard !inFlight, wanted != active else { return false }
    return wanted || !declinedOff
  }

  mutating func finished(turningOn: Bool, succeeded: Bool) {
    inFlight = false
    if succeeded { declinedOff = false } else if !turningOn { declinedOff = true }
  }

  mutating func userChangedSettings() { declinedOff = false }
}
