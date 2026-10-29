import SwiftUI

/// The island's open silhouette: flat top that flares into shoulders, rounded bottom corners.
struct TourIslandShape: Shape {
  var radius: CGFloat = 36
  var shoulder: CGFloat = 14

  var animatableData: AnimatablePair<CGFloat, CGFloat> {
    get { AnimatablePair(radius, shoulder) }
    set { (radius, shoulder) = (newValue.first, newValue.second) }
  }

  func path(in rect: CGRect) -> Path {
    let radius = min(radius, rect.height / 2), shoulder = min(shoulder, rect.width / 4)
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addQuadCurve(to: CGPoint(x: rect.maxX - shoulder, y: rect.minY + shoulder), control: CGPoint(x: rect.maxX - shoulder, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - shoulder, y: rect.maxY - radius))
    path.addQuadCurve(to: CGPoint(x: rect.maxX - shoulder - radius, y: rect.maxY), control: CGPoint(x: rect.maxX - shoulder, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX + shoulder + radius, y: rect.maxY))
    path.addQuadCurve(to: CGPoint(x: rect.minX + shoulder, y: rect.maxY - radius), control: CGPoint(x: rect.minX + shoulder, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX + shoulder, y: rect.minY + shoulder))
    path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: rect.minX + shoulder, y: rect.minY))
    path.closeSubpath()
    return path
  }
}

/// The real island surface (black or the user's glass) in the open shape, with a camera dot.
struct TourIsland<Content: View>: View {
  var size: CGSize
  /// Force a glass surface even if the user's island is plain black (the Liquid Glass page).
  var glass = false
  var radius: CGFloat = 36
  @ViewBuilder var content: Content
  @ObservedObject private var theme = IslandTheme.shared

  private var style: IslandSurfaceStyle {
    if glass { return theme.surface.usesGlass ? theme.surface : .dynamicGlass }
    return theme.effectiveSurface
  }

  var body: some View {
    let shape = TourIslandShape(radius: radius)
    // The shoulders flare outside the content, so the content keeps its own side inset.
    let shoulder = shape.shoulder
    ZStack(alignment: .top) {
      surface.clipShape(shape)
      Circle().fill(Color(white: 0.13)).frame(width: 9, height: 9).padding(.top, 12)
      content.frame(width: size.width).frame(maxHeight: .infinity, alignment: .top)
    }
    .frame(width: size.width + 2 * shoulder, height: size.height)
    .shadow(color: .black.opacity(0.38), radius: 24, y: 12)
  }

  /// Solid black like the real open island, with a faint night tint at the bottom edge.
  /// Only the Liquid Glass page shows glass, so the scene never bleeds through the content.
  @ViewBuilder private var surface: some View {
    if glass {
      DynamicGlassShellBackdrop(
        style: style, level: theme.glassLevel, tinted: theme.tinted, expanded: true, solidHeight: 36, clarity: theme.clarity)
    } else {
      LinearGradient(
        stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7),
                .init(color: Color(red: 0.05, green: 0.06, blue: 0.2), location: 1)],
        startPoint: .top, endPoint: .bottom)
    }
  }
}

/// The round back and close buttons at the window's top corners.
struct TourCircleButton: View {
  let symbol: String
  let label: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
        .frame(width: 32, height: 32)
        .background(Circle().fill(Color(red: 0.16, green: 0.2, blue: 0.55).opacity(0.78)))
        .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.75))
        .contentShape(Circle())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.9))
    .accessibilityLabel(label)
  }
}

/// Page dots: the current page is a long capsule.
struct TourDots: View {
  let count: Int
  let current: Int
  var select: (Int) -> Void = { _ in }

  var body: some View {
    HStack(spacing: 7) {
      ForEach(0..<count, id: \.self) { index in
        Capsule().fill(Color.white.opacity(index == current ? 0.95 : 0.4))
          .frame(width: index == current ? 24 : 8, height: 8)
          .contentShape(Rectangle().inset(by: -4)).onTapGesture { select(index) }
      }
    }
    .animation(.spring(duration: 0.4, bounce: 0.2), value: current)
    .accessibilityElement(children: .ignore).accessibilityLabel("Page \(current + 1) of \(count)")
  }
}

/// The big blue pill.
struct TourContinueButton: View {
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
        .frame(width: OnboardingMetrics.buttonSize.width, height: OnboardingMetrics.buttonSize.height)
        .background(Capsule().fill(LinearGradient(
          colors: [Color(red: 0.31, green: 0.58, blue: 1), Color(red: 0.2, green: 0.43, blue: 0.95)], startPoint: .top, endPoint: .bottom)))
        .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8))
        .shadow(color: Color(red: 0.2, green: 0.4, blue: 0.95).opacity(0.45), radius: 14, y: 6)
        .contentShape(Capsule())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.97))
    .keyboardShortcut(.defaultAction)
  }
}

/// A glassy capsule row: icon, label, and a trailing control.
struct TourRow<Trailing: View>: View {
  let symbol: String
  let title: String
  @ViewBuilder var trailing: Trailing

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(.white.opacity(0.95))
        .frame(width: 26)
      Text(title).font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
      Spacer(minLength: 8)
      trailing
    }
    .padding(.horizontal, 22)
    .frame(width: OnboardingMetrics.rowWidth, height: OnboardingMetrics.rowHeight)
    .background(Capsule().fill(Color.white.opacity(0.1)))
    .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.75))
  }
}

/// A choice row with a round check, as in a single-choice list.
struct TourChoiceRow: View {
  let symbol: String
  let title: String
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      TourRow(symbol: symbol, title: title) {
        ZStack {
          Circle().fill(selected ? Color.white : Color.white.opacity(0.32)).frame(width: 18, height: 18)
          if selected {
            Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Color(red: 0.12, green: 0.18, blue: 0.7))
          }
        }
        .animation(.spring(duration: 0.3, bounce: 0.3), value: selected)
      }
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.985))
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// A MacBook display seen from the front, notch and all; content is clipped to the screen.
struct TourScreen<Content: View>: View {
  var size = CGSize(width: 704, height: 420)
  @ViewBuilder var content: Content

  var body: some View {
    let bezel: CGFloat = 9
    ZStack(alignment: .top) {
      RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(white: 0.04))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
      ZStack(alignment: .top) {
        content.frame(width: size.width - bezel * 2, height: size.height - bezel * 2)
        TourIslandShape(radius: 10, shoulder: 8).fill(Color.black).frame(width: 164, height: 26)
        Circle().fill(Color(white: 0.16)).frame(width: 7, height: 7).padding(.top, 9)
      }
      .frame(width: size.width - bezel * 2, height: size.height - bezel * 2)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .padding(.top, bezel)
    }
    .frame(width: size.width, height: size.height)
    .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
  }
}
