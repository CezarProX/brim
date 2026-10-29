import AppKit
import Foundation
import Testing

@testable import Brim

// MARK: - Fakes

private struct FakeLister: AudioProcessListing {
  var list: [AudioProcessInfo]
  func processes() -> [AudioProcessInfo] { list }
}

private final class FakeDirectory: AudioDeviceListing, @unchecked Sendable {
  var all: [AudioDeviceRef]
  var defaultOut: String?
  var defaultIn: String?
  var switched: [(String, Bool)] = []
  init(_ all: [AudioDeviceRef], out: String? = nil, input: String? = nil) { self.all = all; defaultOut = out; defaultIn = input }
  func devices() -> [AudioDeviceRef] { all }
  func defaultDevice(input: Bool) -> AudioDeviceRef? {
    let uid = input ? defaultIn : defaultOut
    return all.first { $0.uid == uid }
  }
  func setDefault(_ device: AudioDeviceRef, input: Bool) -> Bool {
    switched.append((device.uid, input))
    if input { defaultIn = device.uid } else { defaultOut = device.uid }
    return true
  }
}

@MainActor
private final class FakeEngine: AppVolumeApplying {
  var applied: [String: (gain: Float, uid: String?, processes: [UInt32])] = [:]
  var released: [String] = []
  var failWith: Error?
  var activeAppIDs: Set<String> { Set(applied.keys) }
  func apply(appID: String, processes: [UInt32], gain: Float, outputUID: String?) throws {
    if let failWith { throw failWith }
    applied[appID] = (gain, outputUID, processes)
  }
  func release(appID: String) { applied[appID] = nil; released.append(appID) }
  func releaseAll() { applied = [:] }
  func defaultOutputChanged() {}
}

private func proc(_ id: UInt32, _ bundle: String, playing: Bool = true, input: Bool = false) -> AudioProcessInfo {
  AudioProcessInfo(objectID: id, pid: Int32(id), bundleID: bundle, isRunningOutput: playing, isRunningInput: input)
}

private func device(_ uid: String, name: String? = nil, output: Bool = true, input: Bool = false, airplay: Bool = false) -> AudioDeviceRef {
  AudioDeviceRef(id: UInt32(abs(uid.hashValue % 1000)), uid: uid, name: name ?? uid, isOutput: output, isInput: input,
                 isAirPlay: airplay, isBluetooth: false, isAggregate: false)
}

private func freshSettings() -> AppSettings {
  let suite = "audio-tests-\(UUID().uuidString)"
  return AppSettings(defaults: UserDefaults(suiteName: suite)!)
}

// MARK: - Process list parsing

struct AudioProcessGroupingTests {
  @Test func foldsChromeHelpersIntoOneRow() {
    let rows = AudioProcessGrouping.entries(
      from: [proc(1, "com.google.Chrome"), proc(2, "com.google.Chrome.helper"), proc(3, "com.google.Chrome.helper.Renderer", playing: false)],
      showPaused: false, includeSystemSounds: false, name: { $0 == "com.google.Chrome" ? "Google Chrome" : $0 })
    #expect(rows.count == 1)
    #expect(rows[0].name == "Google Chrome")
    #expect(rows[0].processObjectIDs == [1, 2, 3])
    #expect(rows[0].isPlaying)
  }

  @Test func helperDifferingOnlyInCaseJoinsItsApp() {
    let rows = AudioProcessGrouping.entries(
      from: [proc(1, "company.thebrowser.Browser"), proc(2, "company.thebrowser.browser.helper")],
      showPaused: false, includeSystemSounds: false, name: { $0 })
    #expect(rows.map(\.id) == ["company.thebrowser.Browser"])
    #expect(rows[0].processObjectIDs == [1, 2])
  }

  @Test func webKitHelpersBelongToSafari() {
    #expect(AudioProcessGrouping.appBundleID(for: "com.apple.WebKit.GPU") == "com.apple.Safari")
    #expect(AudioProcessGrouping.appBundleID(for: "com.spotify.client") == "com.spotify.client")
    #expect(AudioProcessGrouping.appBundleID(for: "com.spotify.client.helper") == "com.spotify.client")
  }

  @Test func pausedAppsHiddenUnlessAskedOrAdjusted() {
    let list = [proc(1, "com.a.Playing"), proc(2, "com.b.Idle", playing: false)]
    func ids(_ paused: Bool, keep: Set<String> = []) -> [String] {
      AudioProcessGrouping.entries(from: list, showPaused: paused, includeSystemSounds: false, alwaysInclude: keep, name: { $0 }).map(\.id)
    }
    #expect(ids(false) == ["com.a.Playing"])
    #expect(ids(true) == ["com.a.Playing", "com.b.Idle"])
    #expect(ids(false, keep: ["com.b.Idle"]) == ["com.a.Playing", "com.b.Idle"])
  }

  @Test func systemSoundsOnlyWhenIncluded() {
    let list = [proc(1, "com.apple.systemsoundserver"), proc(2, "com.x.App")]
    let off = AudioProcessGrouping.entries(from: list, showPaused: false, includeSystemSounds: false, name: { $0 })
    let on = AudioProcessGrouping.entries(from: list, showPaused: false, includeSystemSounds: true, name: { $0 })
    #expect(off.map(\.id) == ["com.x.App"])
    #expect(on.contains { $0.isSystemSounds && $0.name == "System Sounds" })
  }

  @Test func ownAppIsExcludedAndEmptyBundlesIgnored() {
    let list = [proc(1, "com.brim"), proc(2, "")]
    #expect(AudioProcessGrouping.entries(from: list, showPaused: true, includeSystemSounds: true, excluding: ["com.brim"], name: { $0 }).isEmpty)
  }

  @Test func liveListIsReadable() {
    // Read-only against the real Core Audio: must not crash and every row must carry a bundle id.
    let processes = CoreAudioProcessLister().processes()
    #expect(processes.allSatisfy { !$0.bundleID.isEmpty })
  }
}

// MARK: - Gain math

struct AudioGainMathTests {
  @Test func naturalCurveIsSquareLawAndHitsUnity() {
    #expect(AudioGainMath.gain(slider: 1, curve: .natural) == 1)
    #expect(abs(AudioGainMath.gain(slider: 0.5, curve: .natural) - 0.25) < 1e-6)
    #expect(AudioGainMath.gain(slider: 0.5, curve: .linear) == 0.5)
    #expect(AudioGainMath.gain(slider: 0, curve: .natural) == 0)
  }

  @Test func boostIsLinearUpToTwoTimes() {
    #expect(AudioGainMath.gain(slider: 1.5, curve: .natural) == 1.5)
    #expect(AudioGainMath.gain(slider: 2, curve: .linear) == 2)
    #expect(AudioGainMath.gain(slider: 9, curve: .linear) == 2, "clamped to 200%")
  }

  @Test func muteAndGarbageInput() {
    #expect(AudioGainMath.gain(slider: 1, curve: .linear, muted: true) == 0)
    #expect(AudioGainMath.clampSlider(.nan) == 1)
    #expect(AudioGainMath.clampSlider(-3) == 0)
  }

  @Test func sliderInvertsGain() {
    for s in stride(from: 0.0, through: 2.0, by: 0.25) {
      for curve in VolumeCurve.allCases {
        let g = Double(AudioGainMath.gain(slider: s, curve: curve))
        #expect(abs(AudioGainMath.slider(forGain: g, curve: curve) - s) < 1e-5)
      }
    }
  }

  @Test func neutralDetection() {
    #expect(AudioGainMath.isNeutral(slider: 1, muted: false))
    #expect(!AudioGainMath.isNeutral(slider: 1, muted: true))
    #expect(!AudioGainMath.isNeutral(slider: 0.9, muted: false))
  }

  @Test func softClipNeverExceedsOneAndPassesQuietAudio() {
    #expect(AudioGainMath.softClip(0.5) == 0.5)
    #expect(AudioGainMath.softClip(-0.2) == -0.2)
    for x in stride(from: Float(0.85), through: 8, by: 0.37) {
      #expect(AudioGainMath.softClip(x) <= 1)
      #expect(AudioGainMath.softClip(-x) >= -1)
    }
    #expect(AudioGainMath.softClip(1.2) > AudioGainMath.softClip(0.9))
  }

  @Test func smootherGlidesWithoutJumping() {
    var smoother = GainSmoother(initial: 1, step: 0.1)
    var last: Float = 1
    for _ in 0..<5 {
      let value = smoother.next(toward: 0)
      #expect(last - value <= 0.1001)
      last = value
    }
    #expect(abs(last - 0.5) < 1e-5)
    for _ in 0..<20 { _ = smoother.next(toward: 0) }
    #expect(smoother.current == 0)
  }
}

// MARK: - Preferred devices

struct PreferredDevicePolicyTests {
  private let speakers = device("spk", name: "MacBook Speakers", input: false)
  private let airpods = device("pods", name: "AirPods", input: true)
  private let dac = device("dac", name: "USB DAC")

  @Test func switchesWhenFavoriteConnects() {
    let target = PreferredDevicePolicy.target(preferred: ["pods"], available: [speakers, airpods], previous: ["spk"], currentUID: "spk", input: false)
    #expect(target?.uid == "pods")
  }

  @Test func ignoresFavoritesAlreadyPresentAtLastScan() {
    #expect(PreferredDevicePolicy.target(preferred: ["pods"], available: [speakers, airpods], previous: ["spk", "pods"], currentUID: "spk", input: false) == nil)
  }

  @Test func neverDemotesFromHigherRankedDevice() {
    #expect(PreferredDevicePolicy.target(preferred: ["dac", "pods"], available: [speakers, dac, airpods], previous: ["spk", "dac"], currentUID: "dac", input: false) == nil)
    let up = PreferredDevicePolicy.target(preferred: ["pods", "dac"], available: [speakers, dac, airpods], previous: ["spk", "dac"], currentUID: "dac", input: false)
    #expect(up?.uid == "pods")
  }

  @Test func picksBestOfSeveralArrivals() {
    let target = PreferredDevicePolicy.target(preferred: ["dac", "pods"], available: [speakers, dac, airpods], previous: ["spk"], currentUID: "spk", input: false)
    #expect(target?.uid == "dac")
  }

  @Test func inputDirectionOnlyConsidersInputs() {
    #expect(PreferredDevicePolicy.target(preferred: ["dac"], available: [speakers, dac], previous: ["spk"], currentUID: "spk", input: true) == nil)
    #expect(PreferredDevicePolicy.target(preferred: ["pods"], available: [airpods], previous: [], currentUID: nil, input: true)?.uid == "pods")
  }

  @Test @MainActor func monitorSkipsFirstScanThenSwitches() {
    let settings = freshSettings()
    settings.preferredDevicesEnabled = true
    settings.preferredOutputUIDs = ["pods"]
    let directory = FakeDirectory([speakers], out: "spk")
    let monitor = PreferredDeviceMonitor(directory: directory, settings: settings)
    monitor.evaluate()
    #expect(directory.switched.isEmpty)
    directory.all = [speakers, device("pods", name: "AirPods")]
    monitor.evaluate()
    #expect(directory.switched.first?.0 == "pods")
    #expect(directory.defaultOut == "pods")
  }

  @Test @MainActor func monitorDoesNothingWhenDisabled() {
    let settings = freshSettings()
    settings.preferredOutputUIDs = ["pods"]
    let directory = FakeDirectory([speakers], out: "spk")
    let monitor = PreferredDeviceMonitor(directory: directory, settings: settings)
    monitor.evaluate()
    directory.all.append(device("pods"))
    monitor.evaluate()
    #expect(directory.switched.isEmpty)
  }
}

// MARK: - Model

@MainActor
struct AudioControlModelTests {
  private func make(_ list: [AudioProcessInfo], settings: AppSettings? = nil) -> (AudioControlModel, FakeEngine, AppSettings) {
    let settings = settings ?? freshSettings()
    let engine = FakeEngine()
    let model = AudioControlModel(
      lister: FakeLister(list: list), directory: FakeDirectory([device("spk"), device("pods")], out: "spk"),
      engine: engine, settings: settings, appName: { $0 })
    return (model, engine, settings)
  }

  @Test func sliderDrivesEngineGainThroughCurve() {
    let (model, engine, _) = make([proc(7, "com.a.App")])
    model.refresh()
    model.setSlider("com.a.App", 0.5)
    #expect(abs((engine.applied["com.a.App"]?.gain ?? 0) - 0.25) < 1e-6)
    #expect(engine.applied["com.a.App"]?.processes == [7])
  }

  @Test func neutralSettingReleasesTapSoAudioIsUntouched() {
    let (model, engine, _) = make([proc(7, "com.a.App")])
    model.refresh()
    model.setSlider("com.a.App", 0.5)
    model.setSlider("com.a.App", 1)
    #expect(engine.applied["com.a.App"] == nil)
  }

  @Test func muteAppliesZeroGainAndUnmuteViaSliderClearsIt() {
    let (model, engine, _) = make([proc(7, "com.a.App")])
    model.refresh()
    model.toggleMute("com.a.App")
    #expect(engine.applied["com.a.App"]?.gain == 0)
    model.setSlider("com.a.App", 0.8)
    #expect(model.rows[0].muted == false)
  }

  @Test func boostIsClampedUnlessAllowed() {
    let (model, engine, settings) = make([proc(7, "com.a.App")])
    model.refresh()
    model.setSlider("com.a.App", 2)
    #expect(model.rows[0].slider == 1, "boost disabled: capped at 100%")
    #expect(engine.applied["com.a.App"] == nil)
    settings.audioAllowBoost = true
    model.setSlider("com.a.App", 2)
    #expect(engine.applied["com.a.App"]?.gain == 2)
  }

  @Test func outputPerAppRoutesTapEvenAtFullVolume() {
    let (model, engine, _) = make([proc(7, "com.a.App")])
    model.refresh()
    model.setOutput("com.a.App", uid: "pods")
    #expect(engine.applied["com.a.App"]?.uid == "pods")
    #expect(engine.applied["com.a.App"]?.gain == 1)
  }

  @Test func rememberedVolumesReapplyWhenAppReturns() {
    let settings = freshSettings()
    let (first, _, _) = make([proc(7, "com.a.App")], settings: settings)
    first.refresh()
    first.setSlider("com.a.App", 0.4)
    let (second, engine, _) = make([proc(9, "com.a.App")], settings: settings)
    second.refresh()
    #expect(abs((engine.applied["com.a.App"]?.gain ?? 0) - 0.16) < 1e-6)
    #expect(engine.applied["com.a.App"]?.processes == [9])
  }

  @Test func forgetsVolumesWhenRememberIsOff() {
    let settings = freshSettings()
    settings.audioRememberVolumes = false
    let (first, _, _) = make([proc(7, "com.a.App")], settings: settings)
    first.refresh()
    first.setSlider("com.a.App", 0.4)
    #expect(settings.audioSavedAppSettings.isEmpty)
  }

  @Test func engineFailureSurfacesOnTheRowAndIsNotRetriedEveryPoll() {
    let (model, engine, _) = make([proc(7, "com.a.App")])
    engine.failWith = AppVolumeTapError.noProcesses
    model.refresh()
    model.setSlider("com.a.App", 0.5)
    #expect(model.rows[0].error != nil)
    engine.failWith = nil
    model.refresh()
    #expect(engine.applied["com.a.App"] == nil, "same processes + prior error: wait for a change before retrying")
  }

  @Test func adjustedAppStaysListedWhileSilent() {
    let settings = freshSettings()
    let engine = FakeEngine()
    let lister = FakeLister(list: [proc(7, "com.a.App")])
    let model = AudioControlModel(lister: lister, directory: FakeDirectory([], out: nil), engine: engine, settings: settings, appName: { $0 })
    model.refresh()
    model.setSlider("com.a.App", 0.5)
    #expect(model.rows.count == 1)
  }
}

// MARK: - Misc

struct SystemVolumeStepperTests {
  @Test func stepsInSixteenths() {
    #expect(SystemVolumeStepper.next(level: 0.5, up: true) == 0.5625)
    #expect(SystemVolumeStepper.next(level: 0.51, up: false) == 0.4375)
    #expect(SystemVolumeStepper.next(level: 1, up: true) == 1)
    #expect(SystemVolumeStepper.next(level: 0, up: false) == 0)
  }
}
