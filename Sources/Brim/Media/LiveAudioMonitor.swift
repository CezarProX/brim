import Foundation

/// Owns the process tap while the live visualizer is wanted, smooths its levels with
/// springs at ~30 Hz and hands them to layer-backed bar views (never through SwiftUI state,
/// so the notch hosting view is not re-laid out for every frame).
@MainActor
final class LiveAudioMonitor {
  static let shared = LiveAudioMonitor()
  enum Status: Equatable { case off, starting, live, silent, unavailable }

  private(set) var status: Status = .off
  /// True once real audio has been seen recently; views fall back to the synthetic wave otherwise.
  var isLive: Bool { status == .live }
  private var observers: [UUID: ([Float]?) -> Void] = [:]
  private var timer: Timer?
  private var tapBox: Any?
  private var values = [Float](repeating: 0, count: 6)
  private var velocities = [Float](repeating: 0, count: 6)
  private var lastLoud = Date.distantPast
  private var activeBundle: String?
  private var retryAt = Date.distantPast
  private let silenceGrace: TimeInterval = 2.5

  /// Call whenever the playing source, play state or the setting changes.
  func update(bundleID: String?, isPlaying: Bool, enabled: Bool) {
    guard enabled, isPlaying, let bundleID, #available(macOS 14.2, *) else { return stop() }
    if activeBundle == bundleID, timer != nil { return }
    guard Date() >= retryAt else { return }
    startTap(bundleID: bundleID)
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    if #available(macOS 14.2, *) { (tapBox as? LiveAudioTap)?.stop() }
    tapBox = nil
    activeBundle = nil
    let wasLive = status != .off
    status = .off
    values = values.map { _ in 0 }
    velocities = velocities.map { _ in 0 }
    if wasLive { notify(nil) }
  }

  func addObserver(_ handler: @escaping ([Float]?) -> Void) -> UUID {
    let id = UUID()
    observers[id] = handler
    return id
  }

  func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }

  private func notify(_ levels: [Float]?) { observers.values.forEach { $0(levels) } }

  private func startTap(bundleID: String) {
    guard #available(macOS 14.2, *) else { return }
    stop()
    status = .starting
    let tap = LiveAudioTap()
    guard tap.start(bundleID: bundleID) else {
      status = .unavailable
      retryAt = Date().addingTimeInterval(20)   // app may not be producing audio yet, or access is denied
      return
    }
    tapBox = tap
    activeBundle = bundleID
    lastLoud = Date()
    let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  private func tick() {
    guard #available(macOS 14.2, *), let tap = tapBox as? LiveAudioTap else { return }
    let raw = tap.levels
    if (raw.max() ?? 0) > 0.03 { lastLoud = Date() }
    let loud = Date().timeIntervalSince(lastLoud) < silenceGrace
    let next: Status = loud ? .live : .silent
    if next != status {
      status = next
      if next == .silent { notify(nil); return }
    }
    guard status == .live else { return }
    for index in values.indices {
      let target = index < raw.count ? raw[index] : 0
      (values[index], velocities[index]) = VisualizerMath.springStep(
        value: values[index], velocity: velocities[index], target: target, dt: 1.0 / 30)
    }
    notify(values)
  }
}
