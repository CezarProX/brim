import AppKit
import SwiftUI

/// The pages whose hero is not the open island: the HUD morph, the lock screen and glances on a
/// MacBook display, the permission list and the Command Center.
struct OnboardingPanelContent: View {
  let page: OnboardingPage
  @ObservedObject var fixtures: OnboardingFixtures
  @ObservedObject var permissions: PermissionsModel
  /// Pins the HUD page to one step (renders and tests); nil lets it cycle.
  var hudStep: Int?

  var body: some View {
    switch page {
    case .huds: TourHUDHero(step: hudStep)
    case .lockScreen: lockScreen
    case .glances: glances
    case .permissions: TourPermissionList(permissions: permissions)
    case .finish: commandCenter
    default: EmptyView()
    }
  }

  /// The tour's own night scene, cropped to a screen, standing in for a wallpaper.
  private func wallpaper(progress: Double) -> some View {
    Color.clear.overlay {
      if let image = OnboardingArt.shared.composite(progress: progress) {
        Image(nsImage: image).resizable().interpolation(.none).scaledToFill()
      }
    }
    .clipped()
  }

  // MARK: Lock screen

  private var lockScreen: some View {
    TourScreen {
      ZStack(alignment: .top) {
        wallpaper(progress: 0.45).overlay(Color.black.opacity(0.12))
        VStack(spacing: 2) {
          Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
            .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
          Text(Date.now, format: .dateTime.hour().minute())
            .font(.system(size: 84, weight: .thin, design: .rounded)).foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        .padding(.top, 54)
        if let track = fixtures.sample?.track {
          LockMediaCard(info: LockMediaInfo(track: track), look: .liquid, actions: LockCardActions())
            .frame(width: 330).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 34)
        }
      }
    }
    .padding(.top, 44)
  }

  // MARK: Glances

  private var glances: some View {
    VStack(spacing: 22) {
      TourScreen(size: CGSize(width: 704, height: 300)) {
        ZStack(alignment: .top) {
          wallpaper(progress: 0.8)
          closedIsland
        }
      }
      HStack(spacing: 10) {
        ForEach([IslandGlance.clock, .battery, .timer, .weather, .cpu, .event], id: \.self) { glance in
          IslandGlanceContent(glance: glance, model: fixtures.glances, weather: OnboardingSamples.weather(), event: OnboardingSamples.meeting())
            .padding(.horizontal, 12).frame(height: 30)
            .background(Color.black, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.75))
        }
      }
      .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
    }
    .padding(.top, 44)
    .allowsHitTesting(false)
  }

  /// The closed island with a glance on each wing, over the screen's notch.
  private var closedIsland: some View {
    ZStack {
      TourIslandShape(radius: 12, shoulder: 8).fill(Color.black)
      HStack(spacing: 0) {
        IslandGlanceContent(glance: .clock, model: fixtures.glances).frame(width: 90, alignment: .trailing)
        Spacer(minLength: 150)
        IslandGlanceContent(glance: .battery, model: fixtures.glances).frame(width: 90, alignment: .leading)
      }
      .padding(.horizontal, 6)
    }
    .frame(width: 360, height: 30)
  }

  // MARK: Command Center

  private var commandCenter: some View {
    CommandCenterView(
      store: fixtures.commandCenter, pager: CommandCenterPageState(),
      models: CommandCenterModels(playing: fixtures.sample ?? .shared, upcomingOverride: OnboardingSamples.upcoming())
    )
    .scaleEffect(0.86, anchor: .top)
    .frame(width: CommandCenterView.size.width * 0.86, height: CommandCenterView.size.height * 0.86, alignment: .top)
    .shadow(color: .black.opacity(0.4), radius: 26, y: 14)
    .padding(.top, 54)
    .allowsHitTesting(false)
  }
}

/// A closed island that grows into a HUD card and back, cycling volume, brightness and charging.
struct TourHUDHero: View {
  var step: Int?
  @State private var tick = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let metrics = HUDMetrics(notchWidth: 150, closedHeight: 34)
  private static let steps: [(flash: IslandFlash, expanded: Bool)] = {
    func flash(_ title: String, _ symbol: String, _ tint: Color, _ value: Double) -> IslandFlash {
      IslandFlash(title: title, symbol: symbol, tint: tint, value: value, until: .distantFuture)
    }
    return [
      (flash("Volume", "speaker.wave.2.fill", .white, 0.3), false),
      (flash("Volume", "speaker.wave.3.fill", .white, 0.72), false),
      (flash("Brightness", "sun.max.fill", .yellow, 0.82), true),
      (flash("Charging", "bolt.fill", .green, 0.9), true),
      (flash("Volume", "speaker.wave.3.fill", .white, 0.95), false),
    ]
  }()

  var body: some View {
    let current = Self.steps[(step ?? tick) % Self.steps.count]
    let size = Self.metrics.size(for: current.flash, expanded: current.expanded)
    ZStack(alignment: .top) {
      TourIslandShape(radius: current.expanded ? 34 : 16, shoulder: current.expanded ? 14 : 9).fill(Color.black)
      HUDMorphView(flash: current.flash, metrics: Self.metrics, expanded: current.expanded)
    }
    .frame(width: size.width, height: size.height, alignment: .top)
    .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
    .animation(reduceMotion ? nil : NotchMotion.expansion(current.expanded, reduceMotion: false), value: current.expanded)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .task(id: step == nil) {
      guard step == nil, !reduceMotion else { return }
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1.9))
        withAnimation(NotchMotion.layout(reduceMotion: false)) { tick += 1 }
      }
    }
  }
}

/// The five permissions with their state and a Grant or Open Settings button.
struct TourPermissionList: View {
  @ObservedObject var permissions: PermissionsModel

  var body: some View {
    VStack(spacing: 8) {
      ForEach(PermissionKind.allCases) { kind in
        TourPermissionRow(
          kind: kind, state: permissions.state(kind),
          needsRelaunch: kind == .screenRecording && permissions.asked.contains(kind) && permissions.state(kind) != .granted
        ) { permissions.grant(kind) }
      }
    }
    .padding(10)
    .frame(width: 540)
    .background(Color(red: 0.04, green: 0.05, blue: 0.16).opacity(0.84), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.75))
    .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
    .padding(.top, 70)
  }
}

private struct TourPermissionRow: View {
  let kind: PermissionKind
  let state: PermissionState
  /// Screen Recording reports a new grant only after Brim restarts.
  var needsRelaunch = false
  let grant: () -> Void

  private var tint: Color {
    switch kind {
    case .accessibility: .blue
    case .screenRecording: .red
    case .calendar: .orange
    case .notifications: .pink
    case .automation: .gray
    }
  }

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: kind.symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
        .frame(width: 38, height: 38)
        .background(tint.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.75))
      VStack(alignment: .leading, spacing: 2) {
        Text(kind.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
        if needsRelaunch {
          Text("Allowed it? Quit and reopen Brim to finish.").font(.system(size: 12)).foregroundStyle(.orange)
        } else {
          Text(kind.reason).font(.system(size: 12)).foregroundStyle(.white.opacity(0.62))
        }
      }
      Spacer(minLength: 8)
      trailing
    }
    .padding(.horizontal, 14).frame(height: 56)
    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  @ViewBuilder
  private var trailing: some View {
    switch state {
    case .granted:
      Label("Granted", systemImage: "checkmark.circle.fill").font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color(red: 0.4, green: 0.92, blue: 0.55))
    case .unknown:
      Button("Grant", action: grant).buttonStyle(IslandPillStyle(prominent: true, tint: Color(red: 0.25, green: 0.5, blue: 1)))
    case .notGranted:
      Button("Open Settings", action: grant).buttonStyle(IslandPillStyle())
    }
  }
}
