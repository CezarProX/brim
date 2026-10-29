import SwiftUI

/// Weather as an opened island widget: first-run setup right here (search a city or use this
/// Mac's location), then the forecast like the system Weather app — now, next hours, next days.
@MainActor
struct WeatherAppView: View {
  @ObservedObject var store: WeatherStore = .shared
  @State private var changing = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var needsSetup: Bool {
    switch store.status {
    case .off, .needsLocation: true
    default: store.locationDenied && store.snapshot == nil
    }
  }

  var body: some View {
    Group {
      if changing || needsSetup {
        WeatherSetupView(
          denied: store.locationDenied, current: store.snapshot?.place,
          choose: { place in changing = false; store.choose(place) },
          useLocation: { changing = false; store.useCurrentLocation() },
          search: { try await store.search($0) },
          cancel: needsSetup ? nil : { changing = false })
      } else if let snapshot = store.snapshot {
        WeatherForecastView(
          snapshot: snapshot, unit: store.unit, followsMac: store.usesCurrentLocation,
          setUnit: store.setUnit, changePlace: { changing = true }, refresh: store.refresh)
      } else if case .failed(let message) = store.status {
        WeatherMessageCard(
          symbol: "wifi.exclamationmark", title: "Couldn’t load the forecast", detail: message,
          primary: ("Try again", store.refresh), secondary: ("Change city", { changing = true }))
      } else {
        WeatherMessageCard(symbol: "cloud.sun.fill", title: "Loading forecast…", detail: nil, spinner: true)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: changing)
  }
}

/// A centered symbol, title, optional detail and up to two actions (loading and error states).
struct WeatherMessageCard: View {
  let symbol: String
  let title: LocalizedStringKey
  let detail: String?
  var spinner = false
  var primary: (LocalizedStringKey, () -> Void)?
  var secondary: (LocalizedStringKey, () -> Void)?

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: symbol).symbolRenderingMode(.multicolor).font(.system(size: 28))
      Text(title).font(IslandFont.title).foregroundStyle(IslandInk.primary)
      if let detail {
        Text(detail).font(.system(size: 12)).foregroundStyle(IslandInk.secondary)
          .multilineTextAlignment(.center).lineLimit(3).frame(maxWidth: 320)
      }
      if spinner { ProgressView().controlSize(.small) }
      HStack(spacing: 8) {
        if let primary {
          Button(action: primary.1) { Text(primary.0) }.buttonStyle(IslandPillStyle(prominent: true))
        }
        if let secondary {
          Button(action: secondary.1) { Text(secondary.0) }.buttonStyle(IslandPillStyle())
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .glassCard(radius: IslandRadius.large)
  }
}

/// The forecast itself, pure drawing so renders and tests don't need the store.
struct WeatherForecastView: View {
  let snapshot: WeatherSnapshot
  let unit: WeatherUnit
  var followsMac = false
  var now = Date.now
  var setUnit: (WeatherUnit) -> Void = { _ in }
  var changePlace: () -> Void = {}
  var refresh: () -> Void = {}

  var body: some View {
    HStack(alignment: .top, spacing: IslandSpace.m) {
      WeatherNowCard(snapshot: snapshot, unit: unit, followsMac: followsMac)
        .frame(width: 184)
      VStack(alignment: .leading, spacing: 8) {
        toolbar
        hourly
        Rectangle().fill(IslandFill.hairline).frame(height: 1)
        daily
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
  }

  private var toolbar: some View {
    HStack(spacing: 6) {
      Text("Updated \(snapshot.fetched.formatted(.relative(presentation: .named)))")
        .font(.system(size: 12)).foregroundStyle(IslandInk.tertiary).lineLimit(1)
      Spacer(minLength: 0)
      unitToggle
      toolbarButton("mappin.and.ellipse", "Change city", changePlace)
      toolbarButton("arrow.clockwise", "Refresh", refresh)
    }
    .frame(height: 28)
  }

  private var unitToggle: some View {
    let resolved = unit.resolved()
    return HStack(spacing: 0) {
      ForEach([WeatherUnit.celsius, .fahrenheit], id: \.self) { option in
        Button { setUnit(option) } label: {
          Text(option == .celsius ? "°C" : "°F").font(.system(size: 12, weight: .semibold))
            .foregroundStyle(resolved == option ? Color.black : IslandInk.secondary)
            .frame(width: 34, height: 26)
            .background(resolved == option ? Color.white : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(IslandPressStyle())
        .accessibilityLabel(option == .celsius ? "Celsius" : "Fahrenheit")
        .accessibilityAddTraits(resolved == option ? .isSelected : [])
      }
    }
    .padding(1).background(IslandFill.subtle, in: Capsule())
  }

  private func toolbarButton(_ symbol: String, _ label: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(IslandInk.primary)
        .frame(width: 28, height: 28).background(IslandFill.raised, in: Circle()).contentShape(Circle())
    }
    .buttonStyle(IslandPressStyle()).help(label).accessibilityLabel(label)
  }

  private var hourly: some View {
    HStack(spacing: 0) {
      ForEach(Array(snapshot.hours.prefix(6).enumerated()), id: \.element.id) { index, hour in
        VStack(spacing: 4) {
          Text(index == 0 ? "Now" : hour.date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated))))
            .font(.system(size: 12)).foregroundStyle(IslandInk.secondary).lineLimit(1)
          Image(systemName: WeatherCondition(code: hour.code).symbol(isNight: !hour.isDay))
            .symbolRenderingMode(.multicolor).font(.system(size: 17)).frame(height: 20)
          Text(unit.format(celsius: hour.celsius)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
            .foregroundStyle(IslandInk.primary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
      }
    }
  }

  @ViewBuilder private var daily: some View {
    let days = Array((snapshot.days ?? []).prefix(5))
    if days.isEmpty {
      Text("Refresh to see the next days.").font(.system(size: 12)).foregroundStyle(IslandInk.tertiary)
    } else {
      let low = days.map(\.lowCelsius).min() ?? 0
      let high = days.map(\.highCelsius).max() ?? 1
      VStack(spacing: 1) {
        ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
          WeatherDayRow(day: day, unit: unit, isToday: index == 0, scale: low...max(high, low + 1))
        }
      }
    }
  }
}

/// One day: name, sky, chance of rain, and the low-to-high range drawn against the week's range.
struct WeatherDayRow: View {
  let day: WeatherDay
  let unit: WeatherUnit
  let isToday: Bool
  let scale: ClosedRange<Double>

  var body: some View {
    HStack(spacing: 8) {
      Text(isToday ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated)))
        .font(.system(size: 13, weight: .medium)).foregroundStyle(IslandInk.primary)
        .frame(width: 52, alignment: .leading)
      Image(systemName: WeatherCondition(code: day.code).symbol(isNight: false))
        .symbolRenderingMode(.multicolor).font(.system(size: 14)).frame(width: 22)
      Text(rain).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.cyan).frame(width: 34, alignment: .leading)
      Text(unit.format(celsius: day.lowCelsius)).font(.system(size: 13)).monospacedDigit()
        .foregroundStyle(IslandInk.secondary).frame(width: 34, alignment: .trailing)
      range.frame(maxWidth: .infinity).frame(height: 5)
      Text(unit.format(celsius: day.highCelsius)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
        .foregroundStyle(IslandInk.primary).frame(width: 34, alignment: .leading)
    }
    .frame(height: 24)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(isToday ? "Today" : day.date.formatted(.dateTime.weekday(.wide))), \(WeatherCondition(code: day.code).label), \(unit.format(celsius: day.lowCelsius)) to \(unit.format(celsius: day.highCelsius))"
    )
  }

  private var rain: String {
    guard let percent = day.rainPercent, percent >= 20 else { return "" }
    return "\(percent)%"
  }

  private var range: some View {
    GeometryReader { proxy in
      let span = max(0.001, scale.upperBound - scale.lowerBound)
      let start = (day.lowCelsius - scale.lowerBound) / span
      let end = (day.highCelsius - scale.lowerBound) / span
      ZStack(alignment: .leading) {
        Capsule().fill(IslandFill.raised)
        Capsule()
          .fill(LinearGradient(colors: [.cyan, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
          .frame(width: max(5, proxy.size.width * (end - start)))
          .offset(x: proxy.size.width * start)
      }
    }
  }
}

/// The sky-colored "right now" card: place, big temperature, condition, today's range and details.
struct WeatherNowCard: View {
  let snapshot: WeatherSnapshot
  let unit: WeatherUnit
  var followsMac = false

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 4) {
        if followsMac { Image(systemName: "location.fill").font(.system(size: 10, weight: .bold)) }
        Text(snapshot.place).font(.system(size: 14, weight: .semibold)).lineLimit(1)
      }
      HStack(alignment: .firstTextBaseline) {
        Text(unit.format(celsius: snapshot.celsius))
          .font(.system(size: 54, weight: .thin, design: .rounded)).monospacedDigit()
          .contentTransition(.numericText()).minimumScaleFactor(0.7).lineLimit(1)
        Spacer(minLength: 0)
        Image(systemName: snapshot.symbol).symbolRenderingMode(.multicolor).font(.system(size: 26))
      }
      Text(snapshot.condition.label).font(.system(size: 14, weight: .semibold)).lineLimit(1)
      Text("H:\(unit.format(celsius: snapshot.highCelsius))  L:\(unit.format(celsius: snapshot.lowCelsius))")
        .font(.system(size: 13)).monospacedDigit().opacity(0.85)
      Spacer(minLength: 4)
      VStack(alignment: .leading, spacing: 2) {
        if let feels = snapshot.feelsLikeCelsius { detail("Feels like", unit.format(celsius: feels)) }
        if let humidity = snapshot.humidityPercent { detail("Humidity", "\(humidity)%") }
        if let wind = snapshot.windKmh { detail("Wind", Self.wind(kmh: wind, unit: unit)) }
      }
    }
    .foregroundStyle(.white)
    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(
      LinearGradient(
        colors: snapshot.condition.gradient(isNight: !snapshot.isDay), startPoint: .topLeading, endPoint: .bottomTrailing),
      in: RoundedRectangle(cornerRadius: IslandRadius.large, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: IslandRadius.large, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.75)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(snapshot.place), \(unit.format(celsius: snapshot.celsius)), \(snapshot.condition.label)")
  }

  private func detail(_ name: LocalizedStringKey, _ value: String) -> some View {
    HStack {
      Text(name).opacity(0.8)
      Spacer(minLength: 4)
      Text(value).fontWeight(.semibold).monospacedDigit()
    }
    .font(.system(size: 12))
  }

  /// Wind in km/h, or mph where the temperature unit is Fahrenheit.
  static func wind(kmh: Double, unit: WeatherUnit) -> String {
    unit.resolved() == .fahrenheit ? "\(Int((kmh * 0.621371).rounded())) mph" : "\(Int(kmh.rounded())) km/h"
  }
}
