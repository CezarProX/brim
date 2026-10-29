import AppKit
import SwiftUI

/// The island's single type scale. Every text style in the notch comes from here.
enum IslandFont {
  /// Large countdowns and clocks.
  static let display = Font.system(size: 34, weight: .semibold, design: .rounded)
  static let title = Font.system(size: 15, weight: .semibold)
  static let headline = Font.system(size: 13, weight: .semibold)
  static let body = Font.system(size: 12)
  static let label = Font.system(size: 11, weight: .medium)
  static let caption = Font.system(size: 10, weight: .medium)
}

/// Three text levels on the black shell, instead of per-view opacity guesses.
enum IslandInk {
  static let primary = Color.white
  static let secondary = Color.white.opacity(0.62)
  static let tertiary = Color.white.opacity(0.4)
}

/// Surface fills layered on the black shell.
enum IslandFill {
  static let hairline = Color.white.opacity(0.08)
  static let subtle = Color.white.opacity(0.07)
  static let raised = Color.white.opacity(0.12)
  static let hover = Color.white.opacity(0.17)
  static let selected = Color.white.opacity(0.22)
}

enum IslandRadius {
  static let small: CGFloat = 8
  static let medium: CGFloat = 14
  static let large: CGFloat = 20
}

enum IslandSpace {
  static let xs: CGFloat = 4
  static let s: CGFloat = 8
  static let m: CGFloat = 12
  static let l: CGFloat = 16
  static let xl: CGFloat = 24
}

/// Accent colors per activity, following the system apps each one mirrors.
enum IslandTint {
  static let timer = Color.orange
  static let recording = Color(red: 1, green: 0.27, blue: 0.23)
  static let call = Color.green

  static func color(for activity: IslandActivity) -> Color {
    switch activity {
    case .focus, .timer: return .orange
    case .calendar, .recording: return recording
    case .devices, .call: return .green
    case .dictation, .transfer: return .blue
    case .agent: return .mint
    case .music: return .pink
    case .system, .workspace: return .gray
    case .recorder: return recording
    case .keepAwake: return .yellow
    case .notes: return .yellow
    case .stats: return .teal
    case .camera: return .green
    case .browser: return .blue
    case .download: return Color(red: 0.25, green: 0.55, blue: 1)
    case .build: return .blue
    case .privacy: return .green
    case .dnd: return .indigo
    case .hotspot: return .green
    }
  }
}

// MARK: - Buttons

/// Press feedback for any tappable island content: a quick springy squeeze.
struct IslandPressStyle: ButtonStyle {
  var pressedScale: CGFloat = 0.94

  func makeBody(configuration: Configuration) -> some View {
    IslandPressBody(configuration: configuration, pressedScale: pressedScale)
  }
}

private struct IslandPressBody: View {
  let configuration: ButtonStyleConfiguration
  let pressedScale: CGFloat
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
      .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.4)
      .animation(NotchMotion.press(reduceMotion: reduceMotion), value: configuration.isPressed)
  }
}

/// Capsule text button. Prominent buttons carry the activity tint; others sit on a raised fill.
struct IslandPillStyle: ButtonStyle {
  var prominent = false
  var tint: Color = .white
  var compact = false

  func makeBody(configuration: Configuration) -> some View {
    IslandPillBody(configuration: configuration, prominent: prominent, tint: tint, compact: compact)
  }
}

private struct IslandPillBody: View {
  let configuration: ButtonStyleConfiguration
  let prominent: Bool
  let tint: Color
  let compact: Bool
  @State private var hovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    configuration.label
      .font(compact ? IslandFont.label : IslandFont.headline)
      .lineLimit(1)
      .foregroundStyle(prominent ? (tint == .white ? Color.black : Color.white) : IslandInk.primary)
      .padding(.horizontal, compact ? 10 : 14)
      .frame(height: compact ? 26 : 30)
      .background(background, in: Capsule())
      .contentShape(Capsule())
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
      .opacity(isEnabled ? 1 : 0.4)
      .onHover { hovered = $0 }
      .animation(NotchMotion.feedback(reduceMotion: reduceMotion), value: hovered)
      .animation(NotchMotion.press(reduceMotion: reduceMotion), value: configuration.isPressed)
  }

  private var background: Color {
    if prominent { return tint.opacity(hovered && isEnabled ? 0.88 : 1) }
    return hovered && isEnabled ? IslandFill.hover : IslandFill.raised
  }
}

/// A round glyph control with a caption, like the call and timer controls on iPhone.
struct IslandControlButton: View {
  enum Role { case neutral, active, tinted(Color), destructive }

  let title: String
  let symbol: String
  var role: Role = .neutral
  var showsTitle = true
  var diameter: CGFloat = 44
  let action: () -> Void
  @State private var hovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    Button(action: action) {
      VStack(spacing: 6) {
        Image(systemName: symbol)
          .font(.system(size: diameter * 0.38, weight: .semibold))
          .foregroundStyle(glyph)
          .contentTransition(.symbolEffect(.replace))
          .frame(width: diameter, height: diameter)
          .background(fill, in: Circle())
          .brightness(hovered && isEnabled ? 0.08 : 0)
        if showsTitle {
          Text(title).font(IslandFont.caption).foregroundStyle(IslandInk.secondary).lineLimit(1)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.9))
    .onHover { hovered = $0 }
    .animation(NotchMotion.feedback(reduceMotion: reduceMotion), value: hovered)
    .help(title)
    .accessibilityLabel(title)
  }

  private var fill: Color {
    switch role {
    case .neutral: return IslandFill.raised
    case .active: return .white
    case .tinted(let color): return color.opacity(0.2)
    case .destructive: return IslandTint.recording
    }
  }

  private var glyph: Color {
    switch role {
    case .neutral, .destructive: return .white
    case .active: return .black
    case .tinted(let color): return color
    }
  }
}

/// Icon-only button that shows a soft circle on hover, like macOS toolbar glyphs.
struct IslandGlyphButton: View {
  let symbol: String
  let label: String
  var size: CGFloat = 26
  let action: () -> Void
  @State private var hovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: size * 0.5, weight: .semibold))
        .foregroundStyle(hovered ? IslandInk.primary : IslandInk.secondary)
        .frame(width: size, height: size)
        .background(hovered ? IslandFill.raised : .clear, in: Circle())
        .contentShape(Circle())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.88))
    .onHover { hovered = $0 }
    .animation(NotchMotion.feedback(reduceMotion: reduceMotion), value: hovered)
    .help(label)
    .accessibilityLabel(label)
  }
}

// MARK: - Layout pieces

/// The heading every activity page starts with: tinted symbol, title and an optional subtitle.
struct IslandHeader<Trailing: View>: View {
  let title: String
  let symbol: String
  var tint: Color = .white
  var subtitle: String?
  @ViewBuilder var trailing: () -> Trailing

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 26, height: 26)
        .background(tint.opacity(0.18), in: Circle())
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(IslandFont.title).foregroundStyle(IslandInk.primary).lineLimit(1)
        if let subtitle {
          Text(subtitle).font(IslandFont.caption).foregroundStyle(IslandInk.tertiary).lineLimit(1)
        }
      }
      Spacer(minLength: 8)
      trailing()
    }
  }
}

extension IslandHeader where Trailing == EmptyView {
  init(title: String, symbol: String, tint: Color = .white, subtitle: String? = nil) {
    self.init(title: title, symbol: symbol, tint: tint, subtitle: subtitle) { EmptyView() }
  }
}

/// Progress ring used by timers and battery levels.
struct IslandRing: View {
  let progress: Double
  var tint: Color = IslandTint.timer
  var lineWidth: CGFloat = 4
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      Circle().stroke(tint.opacity(0.22), lineWidth: lineWidth)
      Circle().trim(from: 0, to: max(0, min(1, progress.isFinite ? progress : 0)))
        .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)
    }
    .accessibilityHidden(true)
  }
}

// MARK: - Transitions

/// Content arrives the way Dynamic Island content does: it sharpens and settles into place.
private struct IslandReveal: ViewModifier {
  let progress: CGFloat
  var anchor: UnitPoint = .top

  func body(content: Content) -> some View {
    content
      .opacity(progress)
      .blur(radius: (1 - progress) * 10)
      .scaleEffect(0.94 + 0.06 * progress, anchor: anchor)
  }
}

extension AnyTransition {
  /// These transitions carry their own animation, so they must check Reduce Motion themselves.
  private static var reducesMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  /// Page and expanded-content changes: blur-in once the shell is about two-thirds open, quick fade out.
  /// Content keeps its final layout size, so arriving earlier lets the growing shell crop the cover.
  static var islandContent: AnyTransition {
    if reducesMotion { return .identity }
    return .asymmetric(
      insertion: .modifier(active: IslandReveal(progress: 0), identity: IslandReveal(progress: 1))
        .animation(.spring(duration: 0.38, bounce: 0.1).delay(0.14)),
      removal: .opacity.animation(.easeOut(duration: 0.1)))
  }

  /// Compact content reappears only once the shell has nearly closed around it.
  static var islandCompact: AnyTransition {
    if reducesMotion { return .identity }
    return .asymmetric(
      insertion: .modifier(
        active: IslandReveal(progress: 0, anchor: .center),
        identity: IslandReveal(progress: 1, anchor: .center)
      )
      // The close spring is ~85% shut by 0.22 s; earlier, the small cover lands on top of the big one.
      .animation(.spring(duration: 0.3, bounce: 0.1).delay(0.22)),
      removal: .opacity.animation(.easeOut(duration: 0.08)))
  }

  /// The blur halo around the open shell: it is inserted at the final size, so it waits until
  /// the shell has nearly reached it instead of flashing a full-size outline.
  static var islandHalo: AnyTransition {
    if reducesMotion { return .opacity }
    return .asymmetric(
      insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.18)),
      removal: .opacity.animation(.easeOut(duration: 0.06)))
  }

  /// Rows and drawers that grow out of the control above them.
  static var islandDrop: AnyTransition {
    if reducesMotion { return .identity }
    return .asymmetric(
      insertion: .modifier(active: IslandReveal(progress: 0), identity: IslandReveal(progress: 1))
        .combined(with: .offset(y: -8)),
      removal: .opacity.combined(with: .offset(y: -4)))
  }

  /// The navigation capsule drops out from under the island after it opens.
  static var islandCapsule: AnyTransition {
    if reducesMotion { return .identity }
    return .asymmetric(
      insertion: .modifier(active: IslandReveal(progress: 0), identity: IslandReveal(progress: 1))
        .combined(with: .offset(y: -14))
        .animation(.spring(duration: 0.46, bounce: 0.3).delay(0.12)),
      removal: .opacity.combined(with: .offset(y: -8)).animation(.easeOut(duration: 0.12)))
  }
}
