import CoreLocation
import Foundation

/// Owns the current forecast: refreshes on the user's interval while Weather is on,
/// keeps the last good result (also on disk) and fails quietly when offline.
@MainActor
final class WeatherStore: NSObject, ObservableObject {
  enum Status: Equatable {
    case off, loading, ready, needsLocation, failed(String)
  }

  static let shared = WeatherStore()
  @Published private(set) var snapshot: WeatherSnapshot?
  @Published private(set) var status: Status = .off
  /// True once macOS has refused Location Services for Brim; the setup card then explains how to allow it.
  @Published private(set) var locationDenied = false
  /// Where the last forecast was fetched for (automatic mode); shared with the lock-screen sky chips.
  private var lastCoordinate: (latitude: Double, longitude: Double)?
  private let settings: AppSettings
  private let service: WeatherService
  private var timer: Timer?
  private var locationManager: CLLocationManager?
  private var task: Task<Void, Never>?

  init(settings: AppSettings = .shared, service: WeatherService = WeatherService(), snapshot: WeatherSnapshot? = nil) {
    self.settings = settings
    self.service = service
    super.init()
    self.snapshot = snapshot ?? settings.weatherCache.flatMap { try? JSONDecoder().decode(WeatherSnapshot.self, from: $0) }
    if self.snapshot != nil { status = settings.weatherEnabled ? .ready : .off }
  }

  var unit: WeatherUnit { settings.weatherUnit }

  /// The place the forecast is for, "My location" while following this Mac.
  var usesCurrentLocation: Bool { settings.weatherLocationMode == .automatic }

  /// The user picked a temperature unit in the widget itself.
  func setUnit(_ unit: WeatherUnit) {
    settings.weatherUnit = unit
    objectWillChange.send()
  }

  /// Picks a searched city: turns Weather on, remembers the place and fetches its forecast.
  func choose(_ place: GeocodingResponse.Place) {
    settings.weatherCityName = place.name
    settings.weatherLatitude = place.latitude
    settings.weatherLongitude = place.longitude
    settings.weatherLocationMode = .custom
    settings.weatherEnabled = true
    locationDenied = false
    // A new place must not keep showing the old one's forecast while it loads.
    snapshot = nil
    status = .loading
    settingsChanged()
  }

  /// "Use my location": turns Weather on and asks macOS for an approximate position.
  func useCurrentLocation() {
    settings.weatherLocationMode = .automatic
    settings.weatherEnabled = true
    snapshot = nil
    status = .loading
    settingsChanged()
  }

  /// Searches cities by name for the inline picker.
  func search(_ query: String) async throws -> [GeocodingResponse.Place] {
    try await service.search(query)
  }

  /// Call at launch and whenever a Weather setting changes.
  func settingsChanged() {
    timer?.invalidate()
    timer = nil
    task?.cancel()
    guard settings.weatherEnabled else {
      status = .off
      return
    }
    let interval = TimeInterval(settings.weatherRefreshMinutes * 60)
    timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
    refresh()
  }

  func refresh() {
    guard settings.weatherEnabled else { return }
    task?.cancel()
    switch settings.weatherLocationMode {
    case .custom:
      guard !settings.weatherCityName.isEmpty,
        (settings.weatherLatitude != 0 || settings.weatherLongitude != 0)
      else {
        status = .needsLocation
        return
      }
      fetch(latitude: settings.weatherLatitude, longitude: settings.weatherLongitude, place: settings.weatherCityName)
    case .automatic:
      requestLocation()
    }
  }

  /// The Weather location without asking for anything new: the chosen city, else the last automatic fix.
  var currentCoordinate: (latitude: Double, longitude: Double)? {
    if settings.weatherLocationMode == .custom {
      guard !settings.weatherCityName.isEmpty, settings.weatherLatitude != 0 || settings.weatherLongitude != 0
      else { return nil }
      return (settings.weatherLatitude, settings.weatherLongitude)
    }
    return settings.weatherEnabled ? lastCoordinate : nil
  }

  private func fetch(latitude: Double, longitude: Double, place: String) {
    lastCoordinate = (latitude, longitude)
    SkyExtrasStore.shared.refresh()
    if snapshot == nil { status = .loading }
    task = Task { [service] in
      do {
        let next = try await service.forecast(latitude: latitude, longitude: longitude, place: place)
        guard !Task.isCancelled else { return }
        self.snapshot = next
        self.status = .ready
        self.settings.weatherCache = try? JSONEncoder().encode(next)
      } catch is CancellationError {
        return
      } catch {
        // Keep showing the last result; only an empty widget needs to say why.
        if self.snapshot == nil { self.status = .failed(error.localizedDescription) }
      }
    }
  }

  // MARK: Location (asked for only when "Automatic" is chosen)

  private func requestLocation() {
    let manager = locationManager ?? CLLocationManager()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyReduced
    locationManager = manager
    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .denied, .restricted:
      locationDenied = true
      status = .failed("Location access is off. Allow it in System Settings, or choose a city.")
    default:
      locationDenied = false
      manager.requestLocation()
    }
  }
}

extension WeatherStore: CLLocationManagerDelegate {
  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in
      guard self.settings.weatherEnabled, self.settings.weatherLocationMode == .automatic else { return }
      switch manager.authorizationStatus {
      case .denied, .restricted: self.requestLocation()
      case .notDetermined: break
      default:
        self.locationDenied = false
        manager.requestLocation()
      }
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    Task { @MainActor in
      let place = await Self.placeName(for: location)
      self.fetch(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, place: place)
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    Task { @MainActor in
      if self.snapshot == nil { self.status = .failed("Couldn’t find your location.") }
    }
  }

  private static func placeName(for location: CLLocation) async -> String {
    let marks = try? await CLGeocoder().reverseGeocodeLocation(location)
    return marks?.first?.locality ?? marks?.first?.name ?? "Current location"
  }
}
