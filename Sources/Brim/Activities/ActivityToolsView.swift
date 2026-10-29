import AppKit
import SwiftUI

@MainActor
struct ActivityToolsView: View {
  static let primaryActivities: [IslandActivity] = [
    .focus, .calendar, .devices, .dictation, .recorder, .keepAwake,
    .notes, .stats, .camera, .transfer, .agent, .workspace,
  ]

  @ObservedObject var center: ActivityCenter
  @Binding var selection: IslandActivity?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(center: ActivityCenter, selection: Binding<IslandActivity?>) {
    self.center = center
    _selection = selection
  }

  var body: some View {
    Group {
      if let selection {
        VStack(alignment: .leading, spacing: IslandSpace.m) {
          Button {
            select(nil)
          } label: {
            Label("Tools", systemImage: "chevron.left")
          }
          .buttonStyle(IslandPillStyle(compact: true))
          ScrollView {
            ExtendedActivityView(activity: selection, center: center)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .scrollIndicators(.hidden)
        }
        .transition(.islandContent)
      } else {
        toolGrid.transition(.islandContent)
      }
    }
  }

  private var toolGrid: some View {
    ScrollView {
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: IslandSpace.s), count: 3),
        spacing: IslandSpace.s
      ) {
        ForEach(Self.primaryActivities, id: \.self) { activity in
          ToolTile(
            title: launcherTitle(activity), detail: detail(for: activity),
            symbol: activity.symbol, tint: IslandTint.color(for: activity), active: isRunning(activity)
          ) { select(activity) }
        }
      }
    }
    .scrollIndicators(.hidden)
  }

  /// Running tools light up like an enabled Control Center toggle.
  private func isRunning(_ activity: IslandActivity) -> Bool {
    switch activity {
    case .focus: center.focus.isActive
    case .dictation: center.dictation.isRecording
    case .recorder: VoiceRecorderModel.shared.isRecording
    case .keepAwake: KeepAwakeModel.shared.isActive
    case .agent: center.coding.session?.isLive() == true || center.agent.active != nil
    default: center.activeKinds.contains(activity)
    }
  }

  private func select(_ activity: IslandActivity?) {
    withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { selection = activity }
  }

  private func launcherTitle(_ activity: IslandActivity) -> String {
    switch activity {
    case .focus: "Timer"
    case .calendar: "Calendar"
    case .transfer: "Share"
    case .agent: "Agents"
    case .workspace: "Front App"
    case .recorder: "Memos"
    case .keepAwake: "Awake"
    case .stats: "Stats"
    case .camera: "Mirror"
    default: activity.title
    }
  }

  /// Live state when the tool is running, otherwise a short description.
  private func detail(for activity: IslandActivity) -> String {
    let live = center.activeKinds.contains(activity) ? center.compactValue(activity) : ""
    if !live.isEmpty { return live }
    switch activity {
    case .focus: return "Pomodoro"
    case .calendar: return center.calendar.meeting == nil ? "Agenda" : center.compactValue(.calendar)
    case .devices: return center.batteries.devices.first.map { "\($0.percent)%" } ?? "Devices"
    case .dictation: return "On-device"
    case .recorder: return VoiceRecorderModel.shared.isRecording ? "Recording" : "Record"
    case .keepAwake: return KeepAwakeModel.shared.isActive ? "On" : "Off"
    case .notes:
      let count = NotesModel.shared.notes.count
      return count == 1 ? "1 note" : "\(count) notes"
    case .stats: return "CPU · RAM"
    case .camera: return "Camera"
    case .transfer: return "QR · AirDrop"
    case .agent: return center.agent.active == nil ? "Status file" : center.compactValue(.agent)
    case .workspace: return center.workspace.appName.isEmpty ? "Front app" : center.workspace.appName
    default: return ""
    }
  }
}

/// Control Center-style tile: tinted glyph, title and live detail.
private struct ToolTile: View {
  let title: String
  let detail: String
  let symbol: String
  let tint: Color
  var active = false
  let action: () -> Void
  @State private var hovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: symbol)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(active ? .white : tint)
          .frame(width: 28, height: 28)
          .background(active ? tint : tint.opacity(0.18), in: Circle())
          .symbolEffect(.pulse, isActive: active && !reduceMotion)
        VStack(alignment: .leading, spacing: 1) {
          Text(title).font(IslandFont.headline).foregroundStyle(IslandInk.primary).lineLimit(1)
          Text(detail).font(IslandFont.caption).foregroundStyle(IslandInk.tertiary)
            .monospacedDigit().lineLimit(1).contentTransition(.numericText())
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 10)
      .frame(maxWidth: .infinity, minHeight: 50)
      .background(
        hovered ? IslandFill.raised : IslandFill.subtle,
        in: RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous)
      )
      .contentShape(RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous))
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.96))
    .onHover { hovered = $0 }
    .animation(NotchMotion.feedback(reduceMotion: reduceMotion), value: hovered)
    .accessibilityLabel(title)
    .accessibilityValue(active ? "On" : "")
  }
}

@MainActor
struct ExtendedActivityView: View {
  let activity: IslandActivity
  @ObservedObject var center: ActivityCenter
  var body: some View {
    Group {
      switch activity {
      case .focus: FocusActivityView(model: center.focus)
      case .calendar: CalendarActivityView(model: center.calendar)
      case .devices: DevicesAppView(model: center.batteries)
      case .dictation: DictationActivityView(model: center.dictation)
      case .transfer: SharingActivityView(model: center.sharing)
      case .workspace: FrontAppView(model: .shared, workspace: center.workspace)
      case .agent:
        AgentsHubView(coding: center.coding, status: center.agent)
      case .browser: BrowserSkinView(model: center.browser)
      case .recorder: VoiceMemosView(model: .shared)
      case .keepAwake: KeepAwakeAppView(model: .shared)
      case .notes: NotesView(model: .shared)
      case .stats: StatsAppView(model: .shared)
      case .camera: CameraMirrorView(model: .shared)
      case .build: XcodeBuildCard(model: center.builds)
      case .download:
        if let snapshot = center.downloads.active { DownloadActivityCard(snapshot: snapshot) }
      case .system:
        if let flash = center.flashes.current {
          VStack(spacing: IslandSpace.l) {
            Image(systemName: flash.symbol).font(.system(size: 28, weight: .medium))
              .foregroundStyle(flash.tint)
              .contentTransition(.symbolEffect(.replace))
            Text(flash.title).font(IslandFont.title)
            if let value = flash.value { ProgressView(value: value).tint(flash.tint) }
          }
          .padding(IslandSpace.xl).frame(maxWidth: .infinity)
        }
      default: EmptyView()
      }
    }
  }
}

struct FocusActivityView: View {
  @ObservedObject var model: FocusTimerModel
  @State private var selectedMinutes = 25
  @State private var pomodoro = false
  @Namespace private var durationSelection
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: IslandSpace.l) {
      if model.isActive { running } else { idle }
    }
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: model.isActive)
  }

  /// The Clock app's running timer: the time inside a large ring, controls beside it, the pair
  /// centered in whatever area shows it (the island's activity page, the widget, the tools list).
  private var running: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let remaining = model.remaining(at: context.date)
      HStack(spacing: 28) {
        ZStack {
          IslandRing(progress: remaining / max(1, model.duration), tint: IslandTint.timer, lineWidth: 8)
            .padding(4)
          VStack(spacing: 2) {
            Text(model.completed ? "Done" : CompactTimerReadout.format(remaining))
              .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
              .foregroundStyle(IslandTint.timer)
              .contentTransition(.numericText(countsDown: true))
            Text(runningCaption).font(IslandFont.caption).foregroundStyle(IslandInk.tertiary)
          }
        }
        .frame(width: 156, height: 156)
        VStack(alignment: .leading, spacing: IslandSpace.l) {
          if !model.completed && !model.isPaused {
            Label("Ends \(context.date.addingTimeInterval(remaining).formatted(date: .omitted, time: .shortened))",
                  systemImage: "bell.fill")
              .font(IslandFont.label).foregroundStyle(IslandInk.secondary)
          }
          HStack(spacing: IslandSpace.l) {
            if !model.completed {
              IslandControlButton(
                title: model.isPaused ? "Resume" : "Pause",
                symbol: model.isPaused ? "play.fill" : "pause.fill", role: .tinted(IslandTint.timer), diameter: 52
              ) {
                if model.isPaused { model.resume() } else { model.pause() }
              }
            }
            IslandControlButton(title: "Restart", symbol: "arrow.counterclockwise", diameter: 52) {
              model.start(minutes: Int(model.duration / 60))
            }
            IslandControlButton(
              title: model.completed ? "Done" : "Stop", symbol: model.completed ? "checkmark" : "xmark",
              diameter: 52, action: model.stop)
          }
        }
      }
      // Every container wraps this in a ScrollView; fill its visible area and center within it.
      .containerRelativeFrame([.horizontal, .vertical], alignment: .center)
    }
    .transition(.islandContent)
  }

  private var runningCaption: String {
    if model.completed { return "Session complete" }
    if model.isPaused { return "Paused" }
    guard model.isPomodoro else { return "Timer" }
    return model.phase == .focus ? "Focus · session \(model.completedSessions + 1)" : "Break"
  }

  private var idle: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 2) {
        modeChip("Timer", pomodoro: false)
        modeChip("Pomodoro", pomodoro: true)
        Spacer(minLength: 0)
        if pomodoro {
          Text("\(selectedMinutes) min focus · 5 min break")
            .font(IslandFont.caption).foregroundStyle(IslandInk.tertiary)
            .transition(.opacity)
        }
      }
      TimerDial(minutes: $selectedMinutes, range: pomodoro ? 5...180 : 1...FocusTimerModel.maximumMinutes)
      HStack(alignment: .center) {
        Button {
          if pomodoro {
            model.startPomodoro(focusMinutes: selectedMinutes)
          } else {
            model.start(minutes: selectedMinutes)
          }
        } label: {
          Label(pomodoro ? "Start focus" : "Start timer", systemImage: "play.fill")
        }
        .buttonStyle(IslandPillStyle(prominent: true, tint: IslandTint.timer))
        Spacer(minLength: 0)
        Text(TimerDialMath.label(minutes: selectedMinutes))
          .font(IslandFont.display).monospacedDigit()
          .foregroundStyle(IslandTint.timer)
          .contentTransition(.numericText())
          .animation(NotchMotion.press(reduceMotion: reduceMotion), value: selectedMinutes)
      }
    }
    .transition(.islandContent)
  }

  private func modeChip(_ title: String, pomodoro value: Bool) -> some View {
    Button {
      withAnimation(NotchMotion.press(reduceMotion: reduceMotion)) {
        pomodoro = value
        if value { selectedMinutes = min(180, max(5, selectedMinutes)) }
      }
    } label: {
      Text(title)
        .font(IslandFont.label.weight(.semibold))
        .foregroundStyle(pomodoro == value ? IslandInk.primary : IslandInk.tertiary)
        .padding(.horizontal, 10).frame(height: 24)
        .background {
          if pomodoro == value {
            Capsule().fill(IslandFill.raised)
              .matchedGeometryEffect(id: "timer-mode", in: durationSelection)
          }
        }
        .contentShape(Capsule())
    }
    .buttonStyle(IslandPressStyle())
    .accessibilityAddTraits(pomodoro == value ? .isSelected : [])
  }
}

/// The app in front, and the two island behaviors it controls, as an Apple settings group.
struct WorkspaceActivityView: View {
  @ObservedObject var model: WorkspaceActivityModel

  var body: some View {
    VStack(alignment: .leading, spacing: IslandSpace.l) {
      HStack(spacing: IslandSpace.m) {
        Group {
          if let icon = model.appIcon {
            Image(nsImage: icon).resizable()
          } else {
            Image(systemName: "app.dashed").resizable().foregroundStyle(IslandInk.tertiary)
          }
        }
        .frame(width: 54, height: 54)
        VStack(alignment: .leading, spacing: 2) {
          Text(model.appName.isEmpty ? "No app in front" : model.appName).font(.system(size: 17, weight: .semibold))
            .lineLimit(1)
          Text("In front now").font(IslandFont.label).foregroundStyle(IslandInk.tertiary)
        }
      }
      VStack(spacing: 0) {
        settingRow(symbol: "app.badge", tint: .blue, title: "Show the app in front when idle",
                   isOn: Binding(get: { model.workspaceEnabled }, set: model.setWorkspaceEnabled))
        Divider().overlay(IslandFill.hairline).padding(.leading, 44)
        settingRow(symbol: "capslock.fill", tint: .green, title: "Show Caps Lock changes",
                   isOn: Binding(get: { model.systemEnabled }, set: model.setSystemEnabled))
      }
      .glassCard(radius: IslandRadius.medium)
    }
  }

  private func settingRow(symbol: String, tint: Color, title: String, isOn: Binding<Bool>) -> some View {
    HStack(spacing: IslandSpace.m) {
      Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
        .frame(width: 22, height: 22).background(tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
      Text(title).font(IslandFont.body)
      Spacer(minLength: IslandSpace.s)
      Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(.green)
    }
    .padding(.horizontal, IslandSpace.m).frame(height: 40)
  }
}
