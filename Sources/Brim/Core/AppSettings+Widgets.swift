import Foundation

/// How the Home page lays out more widgets than fit in one row.
enum WidgetScrollMode: String, CaseIterable, Identifiable, Sendable {
  case automatic, oneRow, twoRows
  var id: String { rawValue }
  var title: String {
    switch self {
    case .automatic: "Automatic"
    case .oneRow: "One row, scroll sideways"
    case .twoRows: "Two rows, scroll up and down"
    }
  }
}

enum WeatherLocationMode: String, CaseIterable, Identifiable, Sendable {
  case custom, automatic
  var id: String { rawValue }
  var title: String { self == .custom ? "Custom city" : "Automatic (this Mac)" }
}

enum WeatherUnit: String, CaseIterable, Identifiable, Sendable {
  case automatic, celsius, fahrenheit
  var id: String { rawValue }
  var title: String {
    switch self {
    case .automatic: "Automatic"
    case .celsius: "Celsius (°C)"
    case .fahrenheit: "Fahrenheit (°F)"
    }
  }
}

/// A System Stats card the user can put on the left or right of the stats widget.
enum StatsCard: String, CaseIterable, Identifiable, Sendable {
  case cpu, ram, gpu, disk, network, battery, thermal
  var id: String { rawValue }
  var title: String {
    switch self {
    case .cpu: "CPU"
    case .ram: "Memory"
    case .gpu: "GPU"
    case .disk: "Disk"
    case .network: "Network"
    case .battery: "Battery"
    case .thermal: "Temperature"
    }
  }
}

/// Settings for the Home widgets, weather, system stats and island glances.
extension AppSettings {
  private func enumValue<T: RawRepresentable>(_ key: String, default fallback: T) -> T
  where T.RawValue == String {
    defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
  }

  var widgetScrollMode: WidgetScrollMode {
    get { enumValue("widgetScrollMode", default: .automatic) }
    set { defaults.set(newValue.rawValue, forKey: "widgetScrollMode") }
  }

  // MARK: Weather (opt-in, network)

  var weatherEnabled: Bool {
    get { defaults.bool(forKey: "weatherEnabled") }
    set { defaults.set(newValue, forKey: "weatherEnabled") }
  }
  var weatherLocationMode: WeatherLocationMode {
    get { enumValue("weatherLocationMode", default: .custom) }
    set { defaults.set(newValue.rawValue, forKey: "weatherLocationMode") }
  }
  var weatherCityName: String {
    get { defaults.string(forKey: "weatherCityName") ?? "" }
    set { defaults.set(String(newValue.prefix(80)), forKey: "weatherCityName") }
  }
  var weatherLatitude: Double {
    get { defaults.double(forKey: "weatherLatitude") }
    set { defaults.set(newValue, forKey: "weatherLatitude") }
  }
  var weatherLongitude: Double {
    get { defaults.double(forKey: "weatherLongitude") }
    set { defaults.set(newValue, forKey: "weatherLongitude") }
  }
  var weatherUnit: WeatherUnit {
    get { enumValue("weatherUnit", default: .automatic) }
    set { defaults.set(newValue.rawValue, forKey: "weatherUnit") }
  }
  /// Minutes between refreshes; clamped to 5...180.
  var weatherRefreshMinutes: Int {
    get { min(180, max(5, defaults.object(forKey: "weatherRefreshMinutes") as? Int ?? 20)) }
    set { defaults.set(min(180, max(5, newValue)), forKey: "weatherRefreshMinutes") }
  }
  var weatherCache: Data? {
    get { defaults.data(forKey: "weatherCache") }
    set { defaults.set(newValue, forKey: "weatherCache") }
  }

  // MARK: System stats

  var statsLeftCard: StatsCard {
    get { enumValue("statsLeftCard", default: .cpu) }
    set { defaults.set(newValue.rawValue, forKey: "statsLeftCard") }
  }
  var statsRightCard: StatsCard {
    get { enumValue("statsRightCard", default: .ram) }
    set { defaults.set(newValue.rawValue, forKey: "statsRightCard") }
  }
  /// Seconds between samples; clamped to 1...10.
  var statsSampleSeconds: Int {
    get { min(10, max(1, defaults.object(forKey: "statsSampleSeconds") as? Int ?? 2)) }
    set { defaults.set(min(10, max(1, newValue)), forKey: "statsSampleSeconds") }
  }
  var statsAlertCPU: Bool {
    get { defaults.bool(forKey: "statsAlertCPU") }
    set { defaults.set(newValue, forKey: "statsAlertCPU") }
  }
  var statsAlertMemory: Bool {
    get { defaults.bool(forKey: "statsAlertMemory") }
    set { defaults.set(newValue, forKey: "statsAlertMemory") }
  }
  var statsAlertTemperature: Bool {
    get { defaults.bool(forKey: "statsAlertTemperature") }
    set { defaults.set(newValue, forKey: "statsAlertTemperature") }
  }
  var statsAlertDisk: Bool {
    get { defaults.bool(forKey: "statsAlertDisk") }
    set { defaults.set(newValue, forKey: "statsAlertDisk") }
  }

  // MARK: Island glances

  var glanceLeft: String {
    get { defaults.string(forKey: "glanceLeft") ?? "none" }
    set { defaults.set(newValue, forKey: "glanceLeft") }
  }
  var glanceRight: String {
    get { defaults.string(forKey: "glanceRight") ?? "none" }
    set { defaults.set(newValue, forKey: "glanceRight") }
  }
  /// The second glance on each side (the one nearer the screen edge).
  var glanceLeftSecond: String {
    get { defaults.string(forKey: "glanceLeftSecond") ?? "none" }
    set { defaults.set(newValue, forKey: "glanceLeftSecond") }
  }
  var glanceRightSecond: String {
    get { defaults.string(forKey: "glanceRightSecond") ?? "none" }
    set { defaults.set(newValue, forKey: "glanceRightSecond") }
  }

  // MARK: Pomodoro

  /// Start the next focus or break automatically; off waits for Play.
  var pomodoroAutoStart: Bool {
    get { defaults.object(forKey: "pomodoroAutoStart") as? Bool ?? true }
    set { defaults.set(newValue, forKey: "pomodoroAutoStart") }
  }
}
