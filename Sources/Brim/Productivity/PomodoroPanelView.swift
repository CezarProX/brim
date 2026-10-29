import SwiftUI

/// The Pomodoro droplet: one duration tape for Focus and Break, presets, session color,
/// end/ambient sound, and the momentum streak. Running state shows a ring with controls.
@MainActor
struct PomodoroPanelView: View {
  @ObservedObject var model: FocusTimerModel
  @ObservedObject var store: FocusSessionStore
  @State private var editing: FocusTimerModel.Phase = .focus
  @State private var focusMinutes: Int
  @State private var breakMinutes: Int
  @State private var color = SessionColor.current
  @State private var endSound = PomodoroEndSound.current
  @State private var ambient = AmbientSound.current
  @State private var focusHint = AppSettings.shared.pomodoroFocusModeHint
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Tile for the Widgets page.
  static let tile = (title: "Pomodoro", symbol: "timer", tint: Color.orange)

  init(model: FocusTimerModel? = nil, store: FocusSessionStore? = nil) {
    _model = ObservedObject(wrappedValue: model ?? .shared)
    _store = ObservedObject(wrappedValue: store ?? .shared)
    _focusMinutes = State(initialValue: min(480, max(1, AppSettings.shared.pomodoroFocusMinutes)))
    _breakMinutes = State(initialValue: min(480, max(1, AppSettings.shared.pomodoroBreakMinutes)))
  }

  private var tint: Color { color.color }
  private var editingMinutes: Binding<Int> { editing == .focus ? $focusMinutes : $breakMinutes }
  private var detents: [Int] { editing == .focus ? PomodoroTapeMath.focusDetents : PomodoroTapeMath.breakDetents }

  var body: some View {
    Group { if model.isActive { running } else { idle } }
      .frame(maxHeight: .infinity, alignment: .center)
      .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: model.isActive)
  }

  // MARK: Idle

  private var idle: some View {
    HStack(alignment: .top, spacing: IslandSpace.l) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 4) {
          sectionChip("Focus", .focus)
          sectionChip("Break", .rest)
          Spacer(minLength: 6)
          ForEach(detents, id: \.self) { preset in
            Button("\(preset)") { setEditing(preset) }
              .buttonStyle(PresetChipStyle(selected: editingMinutes.wrappedValue == preset, tint: tint))
          }
        }
        PomodoroTapeView(minutes: editingMinutes, detents: detents, tint: tint)
          .onChange(of: focusMinutes) { _, value in AppSettings.shared.pomodoroFocusMinutes = value }
          .onChange(of: breakMinutes) { _, value in AppSettings.shared.pomodoroBreakMinutes = value }
        optionsRow
      }
      VStack(alignment: .trailing, spacing: 8) {
        Text(PomodoroTapeMath.label(minutes: editingMinutes.wrappedValue))
          .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tint)
          .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.7)
        Text(editing == .focus ? "Focus · break \(breakMinutes) min" : "Break · focus \(focusMinutes) min")
          .font(IslandFont.body).foregroundStyle(IslandInk.tertiary)
        Button {
          model.startPomodoro(focusMinutes: focusMinutes, breakMinutes: breakMinutes)
        } label: { Label("Start focus", systemImage: "play.fill") }
        .buttonStyle(IslandPillStyle(prominent: true, tint: tint))
        streakChip
      }
      .frame(width: 150)
    }
    .transition(.islandContent)
  }

  private func setEditing(_ minutes: Int) {
    withAnimation(NotchMotion.press(reduceMotion: reduceMotion)) { editingMinutes.wrappedValue = minutes }
  }

  private func sectionChip(_ title: String, _ phase: FocusTimerModel.Phase) -> some View {
    Button { withAnimation(NotchMotion.press(reduceMotion: reduceMotion)) { editing = phase } } label: {
      Text(title).font(.system(size: 13, weight: .semibold))
        .foregroundStyle(editing == phase ? IslandInk.primary : IslandInk.tertiary)
        .padding(.horizontal, 12).frame(height: 28)
        .background(editing == phase ? IslandFill.raised : .clear, in: Capsule())
        .contentShape(Capsule())
    }
    .buttonStyle(IslandPressStyle()).accessibilityAddTraits(editing == phase ? .isSelected : [])
  }

  private var optionsRow: some View {
    HStack(spacing: 6) {
      HStack(spacing: 4) {
        ForEach(SessionColor.allCases) { option in
          Button {
            color = option
            AppSettings.shared.pomodoroColorName = option.rawValue
          } label: {
            Circle().fill(option.color).frame(width: 11, height: 11)
              .overlay(Circle().strokeBorder(Color.white, lineWidth: option == color ? 1.5 : 0).padding(-2))
              .frame(width: 20, height: 28).contentShape(Rectangle())
          }
          .buttonStyle(IslandPressStyle(pressedScale: 0.8)).accessibilityLabel("\(option.rawValue) session color")
        }
      }
      Spacer(minLength: 0)
      soundMenu(symbol: "bell", title: endSound.title, label: "End sound") {
        ForEach(PomodoroEndSound.allCases) { sound in
          Button(sound.title) { endSound = sound; AppSettings.shared.pomodoroEndSoundName = sound.rawValue; sound.play() }
        }
      }
      soundMenu(symbol: "waveform", title: ambient.title, label: "Ambient sound") {
        ForEach(AmbientSound.allCases) { sound in
          Button(sound.title) { ambient = sound; AppSettings.shared.pomodoroAmbientName = sound.rawValue }
        }
      }
      Button {
        focusHint.toggle()
        AppSettings.shared.pomodoroFocusModeHint = focusHint
      } label: {
        Image(systemName: focusHint ? "moon.fill" : "moon").font(.system(size: 12, weight: .semibold))
          .foregroundStyle(focusHint ? tint : IslandInk.secondary).frame(width: 32, height: 28)
          .background(IslandFill.subtle, in: Capsule())
      }
      .buttonStyle(IslandPressStyle()).help("Remind me to turn on a Focus mode when a session starts")
      .accessibilityLabel("Focus mode reminder")
    }
  }

  private func soundMenu<Items: View>(symbol: String, title: String, label: String, @ViewBuilder items: () -> Items)
    -> some View
  {
    Menu(content: items) {
      HStack(spacing: 4) {
        Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
        Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
      }
      .foregroundStyle(IslandInk.secondary).padding(.horizontal, 10).frame(height: 28)
      .background(IslandFill.subtle, in: Capsule())
    }
    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().accessibilityLabel(label)
  }

  private var streakChip: some View {
    let streak = store.streak()
    return HStack(spacing: 4) {
      Image(systemName: "flame.fill").font(.system(size: 12)).foregroundStyle(streak > 0 ? tint : IslandInk.tertiary)
      Text(streak > 0 ? "\(streak) day streak" : "No streak yet").font(IslandFont.body)
        .foregroundStyle(streak > 0 ? IslandInk.primary : IslandInk.tertiary)
      Text("· \(store.sessionsToday()) today").font(IslandFont.body).foregroundStyle(IslandInk.tertiary)
    }
    .accessibilityElement(children: .combine)
  }

  // MARK: Running

  private var running: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let remaining = model.remaining(at: context.date)
      HStack(spacing: IslandSpace.xl) {
        ZStack {
          IslandRing(progress: remaining / max(1, model.duration), tint: model.phase == .rest ? .green : tint, lineWidth: 7)
            .padding(3.5)
          VStack(spacing: 1) {
            Text(model.completed ? "Done" : CompactTimerReadout.format(remaining))
              .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
              .foregroundStyle(model.phase == .rest ? Color.green : tint).contentTransition(.numericText(countsDown: true))
            Text(caption).font(.system(size: 12, weight: .medium)).foregroundStyle(IslandInk.secondary)
          }
        }
        .frame(width: 128, height: 128)
        VStack(alignment: .leading, spacing: IslandSpace.m) {
          streakChip
          if AppSettings.shared.pomodoroFocusModeHint, model.phase == .focus {
            Label("Turn on a Focus in Control Center", systemImage: "moon.fill")
              .font(IslandFont.body).foregroundStyle(IslandInk.secondary)
          }
          HStack(spacing: IslandSpace.l) {
            if !model.completed {
              IslandControlButton(
                title: model.isPaused ? "Resume" : "Pause", symbol: model.isPaused ? "play.fill" : "pause.fill",
                role: .tinted(tint), diameter: 48
              ) { if model.isPaused { model.resume() } else { model.pause() } }
            }
            IslandControlButton(title: "Stop", symbol: "xmark", diameter: 48, action: model.stop)
          }
        }
        Spacer(minLength: 0)
      }
    }
    .transition(.islandContent)
  }

  private var caption: String {
    if model.completed { return "Session complete" }
    if model.isPaused { return "Paused" }
    return model.phase == .focus ? "Focus · session \(model.completedSessions + 1)" : "Break"
  }
}

private struct PresetChipStyle: ButtonStyle {
  let selected: Bool
  let tint: Color
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 12, weight: .semibold).monospacedDigit())
      .foregroundStyle(selected ? Color.black : IslandInk.secondary)
      .frame(minWidth: 32).frame(height: 28)
      .background(selected ? tint : IslandFill.subtle, in: Capsule())
      .scaleEffect(configuration.isPressed ? 0.92 : 1)
  }
}

/// Compact island ring for a running Pomodoro (leading glyph + remaining time).
struct PomodoroCompactRing: View {
  @ObservedObject var model: FocusTimerModel
  /// Off when the island draws the time in its other wing.
  var showsTime = true
  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let remaining = model.remaining(at: context.date)
      HStack(spacing: 5) {
        IslandRing(progress: remaining / max(1, model.duration),
                   tint: model.phase == .rest ? .green : SessionColor.current.color, lineWidth: 2.5)
          .frame(width: 16, height: 16)
        if showsTime {
          Text(CompactTimerReadout.format(remaining)).font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit().foregroundStyle(model.phase == .rest ? Color.green : SessionColor.current.color)
        }
      }
    }
  }
}
