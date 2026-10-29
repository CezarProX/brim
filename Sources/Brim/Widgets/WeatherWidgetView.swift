import SwiftUI

/// The Home weather widget: a sky-colored card with the temperature, today's range and the next hours.
@MainActor
struct WeatherWidgetView: View {
  @ObservedObject var store: WeatherStore = .shared

  var body: some View {
    Group {
      if let snapshot = store.snapshot, store.status != .off {
        WeatherCard(snapshot: snapshot, unit: store.unit)
      } else {
        WeatherPlaceholder(status: store.status, store: store)
      }
    }
    .transition(.opacity)
  }
}

/// Pure drawing of a forecast, so renders and tests don't need the store.
struct WeatherCard: View {
  let snapshot: WeatherSnapshot
  let unit: WeatherUnit
  var hourCount = 5

  var body: some View {
    let night = !snapshot.isDay
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 0) {
          Text(snapshot.place).font(IslandFont.label.weight(.semibold)).lineLimit(1)
          Text(unit.format(celsius: snapshot.celsius))
            .font(.system(size: 38, weight: .light, design: .rounded)).monospacedDigit()
            .contentTransition(.numericText())
        }
        Spacer(minLength: 4)
        VStack(alignment: .trailing, spacing: 1) {
          Image(systemName: snapshot.symbol).symbolRenderingMode(.multicolor)
            .font(.system(size: 22)).frame(height: 26)
          Text(snapshot.condition.label).font(IslandFont.label.weight(.semibold)).lineLimit(1)
          Text("H:\(unit.format(celsius: snapshot.highCelsius))  L:\(unit.format(celsius: snapshot.lowCelsius))")
            .font(IslandFont.caption).monospacedDigit().opacity(0.8)
        }
      }
      Rectangle().fill(.white.opacity(0.22)).frame(height: 1)
      HStack(spacing: 0) {
        ForEach(Array(snapshot.hours.prefix(hourCount).enumerated()), id: \.element.id) { index, hour in
          VStack(spacing: 3) {
            Text(index == 0 ? "Now" : hour.date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated))))
              .font(.system(size: 9, weight: .medium)).opacity(0.75).lineLimit(1)
            Image(systemName: WeatherCondition(code: hour.code).symbol(isNight: !hour.isDay))
              .symbolRenderingMode(.multicolor).font(.system(size: 13)).frame(height: 15)
            Text(unit.format(celsius: hour.celsius)).font(IslandFont.label).monospacedDigit()
          }
          .frame(maxWidth: .infinity)
        }
      }
    }
    .foregroundStyle(.white)
    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
    .padding(.horizontal, 12).padding(.vertical, 10)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(
      LinearGradient(
        colors: snapshot.condition.gradient(isNight: night), startPoint: .topLeading, endPoint: .bottomTrailing),
      in: RoundedRectangle(cornerRadius: 18, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.75)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(snapshot.place), \(unit.format(celsius: snapshot.celsius)), \(snapshot.condition.label)")
  }
}

/// Opt-in and failure states, in the same card shape.
private struct WeatherPlaceholder: View {
  let status: WeatherStore.Status
  @ObservedObject var store: WeatherStore

  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: "cloud.sun.fill").symbolRenderingMode(.multicolor).font(.system(size: 24))
      switch status {
      case .off:
        Text("Weather").font(IslandFont.headline)
        Text("Fetches forecasts from open-meteo.com.").font(IslandFont.caption)
          .foregroundStyle(IslandInk.secondary).multilineTextAlignment(.center)
          .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        // Setup lives in the Weather widget itself (city search, "Use my location").
        Button("Set up Weather") { NotchShelfController.shared.presentWidget(.weather) }
          .buttonStyle(IslandPillStyle(prominent: true, compact: true))
      case .needsLocation:
        Text("Choose a city").font(IslandFont.headline)
        Button("Choose a city") { NotchShelfController.shared.presentWidget(.weather) }
          .buttonStyle(IslandPillStyle(prominent: true, compact: true))
      case .loading:
        ProgressView().controlSize(.small)
      case .failed(let message):
        Text(message).font(IslandFont.caption).foregroundStyle(IslandInk.secondary)
          .multilineTextAlignment(.center).lineLimit(3)
        Button("Try again") { store.refresh() }.buttonStyle(IslandPillStyle(compact: true))
      case .ready:
        EmptyView()
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .glassCard(radius: 18)
  }
}
