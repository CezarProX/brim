import SwiftUI

/// One glance for a wing of the closed island. Empty (and zero-sized content) when it has nothing to show.
@MainActor
struct IslandGlanceView: View {
  let slot: GlanceSlot
  @ObservedObject var model: IslandGlanceModel = .shared

  var body: some View {
    // The first glance sits next to the camera: on the left wing that is the trailing one.
    let shown = slot == .left ? model.visible(for: slot).reversed() : model.visible(for: slot)
    HStack(spacing: IslandGlanceModel.glanceSpacing) {
      ForEach(Array(shown), id: \.self) { glance in
        IslandGlanceContent(glance: glance, model: model)
          .frame(width: IslandGlanceModel.width(of: glance), alignment: slot == .left ? .trailing : .leading)
          .transition(.opacity.combined(with: .scale(scale: 0.85)))
      }
    }
    .frame(width: model.reservedWidth(slot), height: 22, alignment: slot == .left ? .leading : .trailing)
    .animation(.spring(duration: 0.3, bounce: 0), value: model.visible(for: slot))
  }
}

/// The glance itself, separate so renders and previews can show it without the model's gating.
@MainActor
struct IslandGlanceContent: View {
  let glance: IslandGlance
  @ObservedObject var model: IslandGlanceModel = .shared
  var unit: WeatherUnit = AppSettings.shared.weatherUnit
  /// Replaces the live forecast, for renders.
  var weather: WeatherSnapshot?
  /// Replaces the live next event, for renders.
  var event: CalendarMeeting?

  var body: some View {
    HStack(spacing: 4) {
      switch glance {
      case .none:
        EmptyView()
      case .clock:
        TimelineView(.everyMinute) { context in
          readout(nil, GlanceFormat.clock(context.date))
        }
      case .battery:
        let percent = model.batteryPercent ?? 0
        readout(
          GlanceFormat.batterySymbol(percent: percent, charging: model.batteryCharging),
          GlanceFormat.battery(percent: percent),
          tint: model.batteryCharging ? .green : (percent <= 20 ? .red : nil))
      case .timer:
        TimelineView(.periodic(from: .now, by: 1)) { context in
          readout("timer", GlanceFormat.timer(FocusTimerModel.shared.remaining(at: context.date)), tint: IslandTint.timer)
        }
      case .weather:
        if let snapshot = weather ?? WeatherStore.shared.snapshot {
          readout(snapshot.symbol, unit.format(celsius: snapshot.celsius), multicolor: true)
        }
      case .cpu:
        readout("cpu", GlanceFormat.cpu(SystemStatsModel.shared.cpu), tint: .teal)
      case .event:
        if let meeting = event ?? CalendarActivityModel.shared.meeting {
          TimelineView(.everyMinute) { context in
            readout("calendar", GlanceFormat.event(title: meeting.title, startsAt: meeting.startsAt, now: context.date),
                    tint: IslandTint.color(for: .calendar))
          }
        }
      }
    }
    .lineLimit(1)
    .fixedSize()
  }

  private func readout(_ symbol: String?, _ text: String, tint: Color? = nil, multicolor: Bool = false) -> some View {
    HStack(spacing: 4) {
      if let symbol {
        Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
          .symbolRenderingMode(multicolor ? .multicolor : .monochrome)
          .foregroundStyle(tint ?? .white)
      }
      Text(text).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
        .foregroundStyle(tint ?? .white).contentTransition(.numericText())
    }
  }
}
