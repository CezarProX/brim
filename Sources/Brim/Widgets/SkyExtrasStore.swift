// SkyExtrasStore.swift
// Brim

import Foundation

/// Fetches sunrise / sunset and air quality for the Weather location, only while a lock-screen
/// chip that needs them is switched on. Fails quietly and keeps the last good result.
@MainActor
final class SkyExtrasStore: ObservableObject {
  static let shared = SkyExtrasStore()
  @Published private(set) var extras: SkyExtras?
  private var timer: Timer?
  private var task: Task<Void, Never>?
  private let session: URLSession = WeatherService.makeSession()
  private static let interval: TimeInterval = 30 * 60

  var isWanted: Bool {
    AppSettings.shared.lockSunChipEnabled || AppSettings.shared.lockAirQualityChipEnabled
  }

  /// Call at launch and when either chip toggle changes.
  func settingsChanged() {
    timer?.invalidate()
    timer = nil
    task?.cancel()
    guard isWanted else { return }
    timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
    refresh()
  }

  func refresh() {
    guard isWanted, let place = WeatherStore.shared.currentCoordinate else { return }
    let wantSun = AppSettings.shared.lockSunChipEnabled
    let wantAir = AppSettings.shared.lockAirQualityChipEnabled
    task?.cancel()
    task = Task { [session] in
      var next = self.extras ?? SkyExtras()
      if wantSun, let url = SkyRules.sunURL(latitude: place.latitude, longitude: place.longitude),
         let data = await Self.load(url, session: session), let sun = SkyRules.decodeSun(data) {
        next.sunrises = sun.sunrises
        next.sunsets = sun.sunsets
        next.fetchedAt = .now
      }
      if wantAir, let url = SkyRules.airQualityURL(latitude: place.latitude, longitude: place.longitude),
         let data = await Self.load(url, session: session), let aqi = SkyRules.decodeAQI(data) {
        next.usAQI = aqi
        next.fetchedAt = .now
      }
      guard !Task.isCancelled else { return }
      self.extras = next
    }
  }

  private static func load(_ url: URL, session: URLSession) async -> Data? {
    guard let (data, response) = try? await session.data(from: url),
          (response as? HTTPURLResponse)?.statusCode == 200, data.count < 200_000 else { return nil }
    return data
  }
}
