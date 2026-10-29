import AppKit
import Foundation
import Testing

@testable import Brim

struct MediaKeyDecodeTests {
  private func data1(_ code: Int, state: Int, repeats: Bool = false) -> Int {
    (code << 16) | (state << 8) | (repeats ? 1 : 0)
  }

  @Test func decodesKeyStateAndRepeat() {
    let down = MediaKeyEvent.decode(subtype: 8, data1: data1(0, state: 0xA), modifiers: [])
    #expect(down == MediaKeyEvent(key: .soundUp, isDown: true, isRepeat: false, isFine: false))
    let up = MediaKeyEvent.decode(subtype: 8, data1: data1(1, state: 0xB), modifiers: [])
    #expect(up == MediaKeyEvent(key: .soundDown, isDown: false, isRepeat: false, isFine: false))
    let held = MediaKeyEvent.decode(subtype: 8, data1: data1(3, state: 0xA, repeats: true), modifiers: [])
    #expect(held?.key == .brightnessDown && held?.isRepeat == true)
  }

  @Test func decodesEveryHandledKeyAndItsKind() {
    let table: [(Int, MediaKey, MediaKey.Kind, Int)] = [
      (0, .soundUp, .volume, 1), (1, .soundDown, .volume, -1), (7, .mute, .volume, 0),
      (2, .brightnessUp, .brightness, 1), (3, .brightnessDown, .brightness, -1),
      (21, .illuminationUp, .keyboard, 1), (22, .illuminationDown, .keyboard, -1),
    ]
    for (code, key, kind, direction) in table {
      let event = MediaKeyEvent.decode(subtype: 8, data1: data1(code, state: 0xA), modifiers: [])
      #expect(event?.key == key && key.kind == kind && key.direction == direction)
    }
  }

  @Test func shiftOptionMeansFineSteps() {
    let both = MediaKeyEvent.decode(subtype: 8, data1: data1(0, state: 0xA), modifiers: [.shift, .option])
    #expect(both?.isFine == true)
    let one = MediaKeyEvent.decode(subtype: 8, data1: data1(0, state: 0xA), modifiers: [.shift])
    #expect(one?.isFine == false)
  }

  @Test func ignoresOtherSubtypesKeysAndStates() {
    #expect(MediaKeyEvent.decode(subtype: 7, data1: data1(0, state: 0xA), modifiers: []) == nil)
    #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(16, state: 0xA), modifiers: []) == nil)  // play/pause
    #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(0, state: 0x5), modifiers: []) == nil)
  }
}

struct HUDLevelMathTests {
  @Test func normalStepsAreSixteenths() {
    #expect(HUDLevelMath.next(from: 0.5, direction: 1, fine: false) == 0.5625)
    #expect(HUDLevelMath.next(from: 0.5, direction: -1, fine: false) == 0.4375)
  }

  @Test func fineStepsAreQuarterOfThat() {
    let up = HUDLevelMath.next(from: 0.5, direction: 1, fine: true)
    #expect(abs(up - (0.5 + 1.0 / 64)) < 1e-9)
    #expect(HUDLevelMath.stepSize(fine: true) * 4 == HUDLevelMath.stepSize(fine: false))
  }

  @Test func clampsAtBothEnds() {
    #expect(HUDLevelMath.next(from: 1, direction: 1, fine: false) == 1)
    #expect(HUDLevelMath.next(from: 0, direction: -1, fine: false) == 0)
    #expect(HUDLevelMath.next(from: 0.99, direction: 1, fine: true) == 1)
    #expect(HUDLevelMath.clamp(.nan) == 0 && HUDLevelMath.clamp(7) == 1 && HUDLevelMath.clamp(-1) == 0)
  }

  @Test func offGridLevelsSnapToTheNextGridLine() {
    #expect(HUDLevelMath.next(from: 0.43, direction: 1, fine: false) == 0.4375)
    #expect(HUDLevelMath.next(from: 0.43, direction: -1, fine: false) == 0.375)
  }

  @Test func sixteenPressesCrossTheWholeRange() {
    var level = 0.0
    for _ in 0..<16 { level = HUDLevelMath.next(from: level, direction: 1, fine: false) }
    #expect(level == 1)
  }

  @Test func percentRounds() {
    #expect(HUDLevelMath.percent(0.5625) == 56 && HUDLevelMath.percent(2) == 100)
  }

  @Test func muteAndVolumeKeysInteract() {
    typealias S = SystemVolumeControl.State
    #expect(SystemVolumeControl.applying(.mute, fine: false, to: S(level: 0.5, muted: false)) == S(level: 0.5, muted: true))
    #expect(SystemVolumeControl.applying(.soundUp, fine: false, to: S(level: 0.5, muted: true)).muted == false)
    let floor = SystemVolumeControl.applying(.soundDown, fine: false, to: S(level: 1.0 / 16, muted: false))
    #expect(floor.level == 0)
  }
}

struct HUDSymbolTests {
  @Test func volumeSymbolFollowsLevel() {
    #expect(HUDSymbol.volume(level: 0.1, muted: false) == "speaker.wave.1.fill")
    #expect(HUDSymbol.volume(level: 0.5, muted: false) == "speaker.wave.2.fill")
    #expect(HUDSymbol.volume(level: 0.9, muted: false) == "speaker.wave.3.fill")
    #expect(HUDSymbol.volume(level: 0.9, muted: true) == "speaker.slash.fill")
    #expect(HUDSymbol.volume(level: 0, muted: false) == "speaker.slash.fill")
  }

  @Test func brightnessAndKeyboardSymbols() {
    #expect(HUDSymbol.brightness(level: 0.2) == "sun.min.fill")
    #expect(HUDSymbol.brightness(level: 0.8) == "sun.max.fill")
    #expect(HUDSymbol.keyboard(level: 0.2) == "light.min")
    #expect(HUDSymbol.keyboard(level: 0.8) == "light.max")
  }
}

struct HUDQueueTests {
  private let t0 = Date(timeIntervalSinceReferenceDate: 1000)

  private func flash(_ kind: HUDKind, _ title: String = "x", at now: Date, duration: TimeInterval = 2) -> IslandFlash {
    IslandFlash(
      title: title, symbol: "circle", tint: .white, value: kind.isLevel ? 0.5 : nil,
      until: now.addingTimeInterval(duration), kind: kind, duration: duration)
  }

  @Test func newestLevelReplacesSameKind() {
    var queue = HUDQueue()
    queue.offer(flash(.volume, "a", at: t0), now: t0)
    queue.offer(flash(.volume, "b", at: t0), now: t0)
    #expect(queue.current?.title == "b" && queue.pending.isEmpty)
  }

  @Test func otherKindsWaitBehindALevelHUD() {
    var queue = HUDQueue()
    queue.offer(flash(.volume, at: t0), now: t0)
    let shown = queue.offer(flash(.wifi, "net", at: t0), now: t0)
    #expect(!shown && queue.current?.kind == .volume && queue.pending.map(\.title) == ["net"])
  }

  @Test func queuedFlashShowsWithItsFullDurationAfterTheLevelExpires() {
    var queue = HUDQueue()
    queue.offer(flash(.volume, at: t0, duration: 1.6), now: t0)
    queue.offer(flash(.drive, "disk", at: t0, duration: 6), now: t0)
    let later = t0.addingTimeInterval(2)
    queue.advance(now: later)
    #expect(queue.current?.title == "disk")
    #expect(queue.current?.until == later.addingTimeInterval(6))
  }

  @Test func levelHUDInterruptsAFlashButItIsKept() {
    var queue = HUDQueue()
    queue.offer(flash(.vpn, "vpn", at: t0, duration: 5), now: t0)
    queue.offer(flash(.brightness, at: t0), now: t0)
    #expect(queue.current?.kind == .brightness && queue.pending.map(\.title) == ["vpn"])
  }

  @Test func almostFinishedFlashIsNotRequeued() {
    var queue = HUDQueue()
    queue.offer(flash(.vpn, at: t0, duration: 2), now: t0)
    queue.offer(flash(.volume, at: t0), now: t0.addingTimeInterval(1.5))
    #expect(queue.pending.isEmpty)
  }

  @Test func differentNonLevelKindsKeepNewestWins() {
    var queue = HUDQueue()
    queue.offer(flash(.general, "caps", at: t0), now: t0)
    queue.offer(flash(.wifi, "net", at: t0), now: t0)
    #expect(queue.current?.title == "net" && queue.pending.isEmpty)
  }

  @Test func pendingKeepsOnePerKindNewestAndIsBounded() {
    var queue = HUDQueue()
    queue.offer(flash(.volume, at: t0), now: t0)
    queue.offer(flash(.wifi, "old", at: t0), now: t0)
    queue.offer(flash(.wifi, "new", at: t0), now: t0)
    #expect(queue.pending.map(\.title) == ["new"])
    for kind in [HUDKind.vpn, .drive, .bluetooth, .focus, .offline] { queue.offer(flash(kind, at: t0), now: t0) }
    #expect(queue.pending.count == HUDQueue.pendingLimit)
  }

  @Test func expiredCurrentIsReplacedImmediately() {
    var queue = HUDQueue()
    queue.offer(flash(.volume, at: t0, duration: 1), now: t0)
    let shown = queue.offer(flash(.wifi, "net", at: t0.addingTimeInterval(5)), now: t0.addingTimeInterval(5))
    #expect(shown && queue.current?.title == "net")
  }
}

struct NetworkHUDRulesTests {
  typealias Snap = NetworkHUDRules.Snapshot

  @Test func vpnInterfacesAreRecognizedFromNames() {
    let interfaces = [
      NetworkInterfaceInfo(name: "en0", hasIPv4: true), NetworkInterfaceInfo(name: "lo0", hasIPv4: true),
      NetworkInterfaceInfo(name: "utun3", hasIPv4: true), NetworkInterfaceInfo(name: "utun0", hasIPv4: false),
      NetworkInterfaceInfo(name: "ipsec0", hasIPv4: false), NetworkInterfaceInfo(name: "awdl0", hasIPv4: false),
      NetworkInterfaceInfo(name: "ppp0", hasIPv4: true), NetworkInterfaceInfo(name: "bridge100", hasIPv4: true),
    ]
    #expect(VPNInterfaceDetector.tunnels(in: interfaces) == ["ipsec0", "ppp0", "utun3"])
  }

  @Test func lookalikeNamesAreNotTunnels() {
    #expect(!VPNInterfaceDetector.isTunnel(NetworkInterfaceInfo(name: "utunnel", hasIPv4: true)))
    #expect(!VPNInterfaceDetector.isTunnel(NetworkInterfaceInfo(name: "en1", hasIPv4: true)))
  }

  @Test func firstSnapshotNeverFlashes() {
    #expect(NetworkHUDRules.events(previous: nil, current: Snap(satisfied: true, usesWiFi: true, ssid: "Home", vpnName: nil)).isEmpty)
  }

  @Test func joiningWiFiAndChangingNetwork() {
    let off = Snap(satisfied: false, usesWiFi: false, ssid: nil, vpnName: nil)
    let home = Snap(satisfied: true, usesWiFi: true, ssid: "Home", vpnName: nil)
    let cafe = Snap(satisfied: true, usesWiFi: true, ssid: "Cafe", vpnName: nil)
    #expect(NetworkHUDRules.events(previous: off, current: home) == [.wifiJoined(ssid: "Home")])
    #expect(NetworkHUDRules.events(previous: home, current: cafe) == [.wifiJoined(ssid: "Cafe")])
    #expect(NetworkHUDRules.events(previous: home, current: home).isEmpty)
  }

  @Test func goingOfflineOnce() {
    let home = Snap(satisfied: true, usesWiFi: true, ssid: "Home", vpnName: nil)
    let off = Snap(satisfied: false, usesWiFi: false, ssid: nil, vpnName: nil)
    #expect(NetworkHUDRules.events(previous: home, current: off) == [.offline])
    #expect(NetworkHUDRules.events(previous: off, current: off).isEmpty)
  }

  @Test func vpnConnectAndDisconnect() {
    let plain = Snap(satisfied: true, usesWiFi: true, ssid: "Home", vpnName: nil)
    let tunneled = Snap(satisfied: true, usesWiFi: true, ssid: "Home", vpnName: "Work VPN")
    #expect(NetworkHUDRules.events(previous: plain, current: tunneled) == [.vpnConnected(name: "Work VPN")])
    #expect(NetworkHUDRules.events(previous: tunneled, current: plain) == [.vpnDisconnected(name: "Work VPN")])
  }

  @Test func shortDurations() {
    #expect(NetworkHUDRules.shortDuration(45) == "45s")
    #expect(NetworkHUDRules.shortDuration(720) == "12m")
    #expect(NetworkHUDRules.shortDuration(3900) == "1h 5m")
  }
}

struct QuitGuardPolicyTests {
  private let t0 = Date(timeIntervalSinceReferenceDate: 500)

  @Test func firstPressAnnouncesSecondWithinWindowPasses() {
    var policy = QuitGuardPolicy()
    #expect(policy.decide(now: t0, bundleID: "a", isRepeat: false) == .announce)
    #expect(policy.decide(now: t0.addingTimeInterval(1), bundleID: "a", isRepeat: false) == .allow)
  }

  @Test func lateSecondPressAnnouncesAgain() {
    var policy = QuitGuardPolicy()
    _ = policy.decide(now: t0, bundleID: "a", isRepeat: false)
    #expect(policy.decide(now: t0.addingTimeInterval(2), bundleID: "a", isRepeat: false) == .announce)
  }

  @Test func holdingPassesAfterTheThreshold() {
    var policy = QuitGuardPolicy()
    _ = policy.decide(now: t0, bundleID: "a", isRepeat: false)
    #expect(policy.decide(now: t0.addingTimeInterval(0.3), bundleID: "a", isRepeat: true) == .swallow)
    #expect(policy.decide(now: t0.addingTimeInterval(0.9), bundleID: "a", isRepeat: true) == .allow)
  }

  @Test func confirmationDoesNotCarryToAnotherApp() {
    var policy = QuitGuardPolicy()
    _ = policy.decide(now: t0, bundleID: "a", isRepeat: false)
    #expect(policy.decide(now: t0.addingTimeInterval(0.5), bundleID: "b", isRepeat: false) == .announce)
  }
}

struct DriveAndBluetoothRulesTests {
  @Test func onlyExternalLocalDisksAreAnnounced() {
    typealias V = DriveHUDRules.Volume
    #expect(DriveHUDRules.shouldAnnounce(V(isInternal: false, isLocal: true, isBrowsable: true, isEjectable: true, isRemovable: false, path: "/Volumes/T7")))
    #expect(!DriveHUDRules.shouldAnnounce(V(isInternal: true, isLocal: true, isBrowsable: true, isEjectable: false, isRemovable: false, path: "/")))
    #expect(!DriveHUDRules.shouldAnnounce(V(isInternal: nil, isLocal: false, isBrowsable: true, isEjectable: true, isRemovable: false, path: "/Volumes/share")))
    #expect(!DriveHUDRules.shouldAnnounce(V(isInternal: false, isLocal: true, isBrowsable: false, isEjectable: true, isRemovable: false, path: "/Volumes/hidden")))
  }

  @Test func bluetoothDiffReportsConnectDisconnectAndLowBattery() {
    typealias D = BluetoothHUDRules.Device
    let pods = D(id: "p", name: "Pods", percent: 50)
    let keys = D(id: "k", name: "Keys", percent: 80)
    #expect(BluetoothHUDRules.events(previous: nil, current: [pods]).isEmpty)
    #expect(BluetoothHUDRules.events(previous: [pods], current: [pods, keys]) == [.connected(name: "Keys", percent: 80)])
    #expect(BluetoothHUDRules.events(previous: [pods, keys], current: [keys]) == [.disconnected(name: "Pods")])
    let low = D(id: "p", name: "Pods", percent: 18)
    #expect(BluetoothHUDRules.events(previous: [pods], current: [low]) == [.lowBattery(name: "Pods", percent: 18)])
    #expect(BluetoothHUDRules.events(previous: [low], current: [low]).isEmpty)
  }
}

struct HUDSettingsTests {
  @Test func tintHexRoundTrips() {
    #expect(HUDTint.components(hex: "#FF8000")! == (1, Double(0x80) / 255, 0))
    #expect(HUDTint.components(hex: "nope") == nil)
    #expect(HUDTint.hex(from: HUDTint.color(hex: "#34C759")) == "#34C759")
  }

  @Test func defaultsAreSafe() {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "hud-tests-\(UUID().uuidString)")!)
    // The pop-up replacement is on by default; the key tap still needs Accessibility trust.
    #expect(settings.hudReplaceVolume && !settings.hudQuitGuard && settings.hudBluetooth)
    #expect(settings.hudPlacement == .besideNotch && settings.hudWiFi)
    settings.hudPlacement = .belowNotch
    #expect(settings.hudPlacement == .belowNotch)
  }
}

struct HUDPillCardWidthTests {
  @Test func airPodsCardInThePillFitsTheNameAndThreeRings() {
    let pods = AirPodsBatteries(name: "AirPods Pro", symbol: "airpodspro", left: 92, right: 88, caseLevel: 64)
    let flash = IslandFlash(title: pods.name, symbol: pods.symbol, tint: .white, value: nil, until: .distantFuture,
                            kind: .bluetooth, detail: "Connected", airPods: pods, shortTitle: "Connected")
    let pill = HUDMetrics(notchWidth: 190, closedHeight: 32, floating: true)
    let notch = HUDMetrics(notchWidth: 190, closedHeight: 32)
    #expect(pill.cardSize(for: flash).width >= notch.cardSize(for: flash).width - 50)
  }
}
