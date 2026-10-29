import AppKit
import SwiftUI
import UniformTypeIdentifiers

// The small (one-unit, square) layouts of Home widgets whose medium layout lives elsewhere.
// Each is designed for the square, not squeezed from the wide card.

/// Small Captures: the newest screenshot fills the card, with the count on a chip.
@MainActor
struct HomeCapturesSmallWidget: View {
  @ObservedObject var store: ShelfStore

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: IslandRadius.large, style: .continuous)
    Group {
      if let entry = store.entries.first {
        Button { NotchShelfController.shared.edit(entry) } label: {
          ZStack(alignment: .bottomLeading) {
            Color.white.opacity(0.08)
            if let thumbnail = store.thumbnail(for: entry) {
              Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            HStack(spacing: 4) {
              Image(systemName: "camera.viewfinder").font(.system(size: 10, weight: .semibold))
              Text(entry.date, style: .time).font(IslandFont.caption.weight(.semibold)).lineLimit(1)
              Spacer(minLength: 0)
              if store.entries.count > 1 {
                Text("\(store.entries.count)").font(IslandFont.caption.weight(.bold)).monospacedDigit()
                  .padding(.horizontal, 6).padding(.vertical, 2).background(.black.opacity(0.45), in: Capsule())
              }
            }
            .foregroundStyle(IslandInk.primary)
            .padding(10)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .clipShape(shape)
        }
        .buttonStyle(IslandPressStyle(pressedScale: 0.97))
        .help("Edit screenshot from \(entry.date.formatted())")
        .onDrag {
          (try? Data(contentsOf: store.fileURL(for: entry))).map {
            ImageDragExport.provider(for: $0, date: entry.date)
              ?? NSItemProvider(item: $0 as NSData, typeIdentifier: UTType.png.identifier)
          } ?? NSItemProvider()
        }
      } else {
        HomeWidgetCard {
          Button { CaptureCoordinator.shared.startCapture() } label: {
            VStack(alignment: .leading, spacing: 0) {
              HomeWidgetHeader(title: "Captures", symbol: "camera.viewfinder")
              Spacer(minLength: 0)
              Image(systemName: "plus.viewfinder").font(.system(size: 26, weight: .medium))
                .foregroundStyle(IslandInk.secondary)
              Spacer(minLength: 6)
              Text("Take a screenshot").font(IslandFont.label).foregroundStyle(IslandInk.secondary)
                .lineLimit(2).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(IslandPressStyle(pressedScale: 0.97))
        }
      }
    }
    .overlay { shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 0.75) }
  }
}

/// Small Timer, laid out like Apple's Timer widget: what it is at the top, the time big and
/// left-aligned, a progress bar while it runs, and the controls along the bottom with the main
/// action as a filled orange button on the right. Idle, − and + set the length in five-minute steps.
@MainActor
struct HomeTimerSmallWidget: View {
  @ObservedObject var model: FocusTimerModel
  @State private var minutes = 25

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let remaining = model.remaining(at: context.date)
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 5) {
          Image(systemName: "timer").font(.system(size: 11, weight: .bold))
          Text(model.isActive ? (model.isPaused ? "Paused" : "Focus") : "Timer")
            .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(IslandTint.timer)
        Spacer(minLength: 2)
        Text(model.isActive ? CompactTimerReadout.format(remaining) : TimerDialMath.label(minutes: minutes))
          .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
          .foregroundStyle(model.isActive && !model.isPaused ? IslandTint.timer : IslandInk.primary)
          .lineLimit(1).minimumScaleFactor(0.6)
          .contentTransition(.numericText(countsDown: model.isActive))
        progress(model.isActive ? 1 - remaining / max(1, model.duration) : 0)
          .opacity(model.isActive ? 1 : 0)
          .padding(.top, 4)
        Spacer(minLength: 6)
        controls
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    .animation(.spring(duration: 0.3, bounce: 0.1), value: model.isActive)
    .animation(.spring(duration: 0.3, bounce: 0.1), value: model.isPaused)
  }

  private func progress(_ fraction: Double) -> some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(IslandFill.raised)
        Capsule().fill(IslandTint.timer).frame(width: max(4, proxy.size.width * min(1, max(0, fraction))))
      }
    }
    .frame(height: 4)
    .accessibilityHidden(true)
  }

  private var controls: some View {
    HStack(spacing: 6) {
      if model.isActive {
        control("xmark", label: "Stop") { model.stop() }
      } else {
        control("minus", label: "Shorter") { minutes = max(5, minutes - 5) }
          .disabled(minutes <= 5)
        control("plus", label: "Longer") { minutes = min(FocusTimerModel.maximumMinutes, minutes + 5) }
          .disabled(minutes >= FocusTimerModel.maximumMinutes)
      }
      Spacer(minLength: 0)
      Button {
        if !model.isActive { model.start(minutes: minutes) }
        else if model.isPaused { model.resume() } else { model.pause() }
      } label: {
        Image(systemName: model.isActive && !model.isPaused ? "pause.fill" : "play.fill")
          .font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
          .frame(width: 36, height: 36).background(IslandTint.timer, in: Circle())
          .contentTransition(.symbolEffect(.replace))
      }
      .buttonStyle(IslandPressStyle(pressedScale: 0.88))
      .accessibilityLabel(model.isActive ? (model.isPaused ? "Resume" : "Pause") : "Start")
    }
  }

  private func control(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 11, weight: .bold))
        .foregroundStyle(IslandInk.primary)
        .frame(width: 28, height: 28)
        .background(IslandFill.raised, in: Circle())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.88))
    .accessibilityLabel(label)
  }
}

/// Small Notes: the newest note's title and first lines; a click opens it in the Notes window.
@MainActor
struct HomeNotesSmallWidget: View {
  @ObservedObject var model: NotesModel

  var body: some View {
    let note = model.selected ?? model.notes.first
    Button { open(note) } label: {
      VStack(alignment: .leading, spacing: 4) {
        HomeWidgetHeader(title: "Notes", symbol: "note.text", tint: .yellow)
        if let note {
          Text(note.title).font(IslandFont.headline).foregroundStyle(IslandInk.primary).lineLimit(2)
          Text(Self.preview(note.text)).font(IslandFont.label).foregroundStyle(IslandInk.secondary)
            .lineLimit(3)
          Spacer(minLength: 0)
          Text(note.edited, format: .dateTime.hour().minute())
            .font(IslandFont.caption).foregroundStyle(IslandInk.tertiary)
        } else {
          Spacer(minLength: 0)
          Image(systemName: "square.and.pencil").font(.system(size: 22, weight: .medium))
            .foregroundStyle(.yellow)
          Text("New note").font(IslandFont.label.weight(.semibold)).foregroundStyle(IslandInk.secondary)
        }
      }
      .multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .contentShape(Rectangle())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.97))
    .accessibilityLabel(note == nil ? "New note" : "Open in window")
  }

  /// The note after its title line, without Markdown markers, on one flowing line.
  nonisolated static func preview(_ text: String) -> String {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true).dropFirst()
    let marks = CharacterSet(charactersIn: "#*-_>`[] ")
    return lines.map { $0.trimmingCharacters(in: marks) }.filter { !$0.isEmpty }.joined(separator: " ")
  }

  private func open(_ note: IslandNote?) {
    let target = note ?? model.create()
    NotesWindowController.shared.show(noteID: target.id)
    NotchShelfController.shared.dismissShelf()
  }
}

/// Small Stats: the two chosen readings as rings side by side.
@MainActor
struct HomeStatsSmallWidget: View {
  @ObservedObject var stats: SystemStatsModel
  var left: StatsCard = AppSettings.shared.statsLeftCard
  var right: StatsCard = AppSettings.shared.statsRightCard

  var body: some View {
    let input = StatsCardReading.Input(
      cpu: stats.cpu, memoryUsed: stats.memoryUsed, memoryTotal: stats.memoryTotal, gpu: stats.gpu,
      diskFree: stats.diskFree, diskTotal: stats.diskTotal, networkDown: stats.networkDown,
      networkUp: stats.networkUp, batteryPercent: stats.batteryPercent,
      batteryCharging: stats.batteryCharging, thermal: stats.thermalState)
    VStack(alignment: .leading, spacing: 0) {
      HomeWidgetHeader(title: "Stats", symbol: "gauge.with.dots.needle.33percent", tint: .teal)
      Spacer(minLength: 0)
      HStack(spacing: 10) {
        gauge(.make(left, input))
        gauge(.make(right, input))
      }
      Spacer(minLength: 0)
    }
    .onAppear { stats.attach() }
    .onDisappear { stats.detach() }
  }

  private func gauge(_ reading: StatsCardReading) -> some View {
    VStack(spacing: 5) {
      ZStack {
        IslandRing(progress: reading.level ?? 0, tint: reading.tint, lineWidth: 4.5)
          .opacity(reading.level == nil ? 0.35 : 1)
        Text(reading.center).font(.system(size: reading.center.count > 4 ? 10 : 13, weight: .semibold, design: .rounded))
          .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 6)
          .contentTransition(.numericText())
      }
      .frame(width: 50, height: 50)
      Text(reading.card.title).font(IslandFont.caption.weight(.semibold)).foregroundStyle(IslandInk.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(reading.card.title) \(reading.center)")
  }
}

/// Small Weather: place, temperature, the sky's glyph and today's range, on the sky's colors.
@MainActor
struct HomeWeatherSmallWidget: View {
  @ObservedObject var store: WeatherStore = .shared

  var body: some View {
    if let snapshot = store.snapshot, store.status != .off {
      HomeWeatherSmallCard(snapshot: snapshot, unit: store.unit)
    } else {
      // The opt-in and error states are the medium widget's, which read fine in a square.
      WeatherWidgetView(store: store)
    }
  }
}

struct HomeWeatherSmallCard: View {
  let snapshot: WeatherSnapshot
  let unit: WeatherUnit

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
    VStack(alignment: .leading, spacing: 0) {
      Text(snapshot.place).font(IslandFont.label.weight(.semibold)).lineLimit(1)
      Text(unit.format(celsius: snapshot.celsius))
        .font(.system(size: 38, weight: .light, design: .rounded)).monospacedDigit().lineLimit(1)
        .minimumScaleFactor(0.7).contentTransition(.numericText())
      Spacer(minLength: 0)
      Image(systemName: snapshot.symbol).symbolRenderingMode(.multicolor).font(.system(size: 17)).frame(height: 20)
      Text(snapshot.condition.label).font(IslandFont.label.weight(.semibold)).lineLimit(1)
      Text("H:\(unit.format(celsius: snapshot.highCelsius))  L:\(unit.format(celsius: snapshot.lowCelsius))")
        .font(IslandFont.caption).monospacedDigit().opacity(0.8).lineLimit(1)
    }
    .foregroundStyle(.white)
    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(
      LinearGradient(colors: snapshot.condition.gradient(isNight: !snapshot.isDay),
                     startPoint: .topLeading, endPoint: .bottomTrailing), in: shape)
    .overlay { shape.strokeBorder(.white.opacity(0.14), lineWidth: 0.75) }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(snapshot.place), \(unit.format(celsius: snapshot.celsius)), \(snapshot.condition.label)")
  }
}
