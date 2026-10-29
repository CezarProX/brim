import AppKit
import SwiftUI

/// The open island's surface: pure black around the camera housing, melting into blurred, tinted
/// glass toward the lower edge ("Dynamic Glass"), or all glass, or plain black.
struct DynamicGlassShellBackdrop: View {
  let style: IslandSurfaceStyle
  let level: Double
  let tinted: Bool
  let expanded: Bool
  /// Height of the band that stays black, measured from the top edge.
  let solidHeight: CGFloat
  var clarity: Double = 0.5
  /// Pale frosted glass for macOS Light mode.
  var light = false
  var windowTint: Color?
  /// Keeps the blur mounted through the close, under the black, instead of only while open.
  @State private var blurHeld = false
  @State private var blurRelease: Task<Void, Never>?

  /// The close spring has settled well within this; the blur leaves once the black has hidden it.
  static let blurHoldAfterClose: Duration = .milliseconds(600)

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .top) {
        if style.usesGlass {
          // The blur is never swapped out mid-transition. Removed while the island closed, it froze
          // at the open outline and trailed the shrinking shell as a translucent slab; faded in on
          // open, the shell was see-through. It joins at the start of the open and leaves only
          // after the close, both times beneath the black.
          if expanded || blurHeld {
            IslandBackdropBlur(liquid: style == .liquidGlass, tinted: tinted, clarity: clarity, light: light)
          }
          if let windowTint {
            windowTint.opacity(0.28).blendMode(.plusLighter).opacity(expanded ? 1 : 0)
          }
          LinearGradient(
            gradient: DynamicGlassMelt(
              style: style, height: proxy.size.height, solidHeight: solidHeight, level: level,
              lightness: light ? 1 : 0
            ).gradient,
            startPoint: .top, endPoint: .bottom)
          // Closed, the island is solid black like the hardware notch. Over the glass, so the shell
          // is never see-through: it thins out as the island opens and goes black at once on close,
          // because the AppKit blur only covers the closed frame while the shell shrinks around it.
          // The fade is scoped to opacity: on the whole view it also drove the frame, so the black
          // snapped to the pill's size as a square-cornered slab inside the closing shell. Closing
          // has no fade: any see-through frame shows the blur already shrunk to the closed size.
          Color.black
            .animation(expanded ? .easeInOut(duration: 0.3) : nil) {
              $0.opacity(expanded ? 0 : 1)
            }
        } else {
          Color.black
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .onChange(of: expanded, initial: true) { _, open in holdBlur(open) }
  }

  private func holdBlur(_ open: Bool) {
    blurRelease?.cancel()
    guard !open else {
      blurHeld = true
      return
    }
    blurRelease = Task { @MainActor in
      try? await Task.sleep(for: Self.blurHoldAfterClose)
      guard !Task.isCancelled else { return }
      blurHeld = false
    }
  }
}

/// The small floating surfaces around the island (navigation capsule, back buttons): mostly black
/// glass with a hairline rim, so they read as pieces of the same shell.
struct DynamicGlassCapsuleSurface<S: Shape>: View {
  let shape: S
  var glass = true

  var body: some View {
    if glass {
      // Real Liquid Glass on macOS 26 (an AppKit material before), with the capsule's dark tint.
      GlassSurface(role: .capsule, shape: shape)
    } else {
      Color.black
        .clipShape(shape)
        .overlay { shape.stroke(.white.opacity(0.1), lineWidth: 0.75) }
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
  }
}

/// Blurred backdrop: the live desktop through the window server, or a wallpaper snapshot in renders.
struct IslandBackdropBlur: View {
  var liquid = false
  var tinted = true
  var clarity = 0.5
  var light = false
  @Environment(\.islandBackdropSnapshot) private var snapshot
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    let density = GlassClarity(clarity)
    ZStack {
      if let snapshot {
        SnapshotBlur(snapshot: snapshot, radius: density.blurRadius(base: liquid ? 14 : 26))
      } else if liquid {
        LiquidGlassMaterial(clarity: clarity)
      } else {
        IslandGlassMaterial(light: light)
      }
      // Tinted glass darkens what shows through; clear glass lets the wallpaper colour lead.
      // Light glass swaps the black veil for a pale one, keeping white text legible.
      if light {
        Color(white: 0.34).opacity(density.veilOpacity(tinted: tinted) + 0.14)
      } else {
        Color.black.opacity(darkVeil)
      }
    }
  }

  /// The clarity-scaled tint, never lighter than `GlassStyle`'s readability floor for this glass.
  private var darkVeil: Double {
    let prefs = GlassPreferences(tinted: tinted, clarity: clarity, increaseContrast: contrast == .increased)
    let gray = prefs.materialGray(for: .shell, liquid: liquid && snapshot == nil && GlassSupport.hasLiquidGlass)
    return prefs.veil(for: .shell, materialGray: gray)
  }
}

/// Draws the snapshot wallpaper under this view's position on the render canvas, blurred.
struct SnapshotBlur: View {
  let snapshot: IslandBackdropSnapshot
  let radius: CGFloat

  var body: some View {
    GeometryReader { proxy in
      let frame = proxy.frame(in: .named(IslandBackdropSnapshot.coordinateSpace))
      Image(nsImage: snapshot.image).resizable()
        .frame(width: snapshot.canvasSize.width, height: snapshot.canvasSize.height)
        .blur(radius: radius, opaque: true)
        .saturation(1.25)
        .offset(x: -frame.minX, y: -frame.minY)
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        .clipped()
    }
  }
}

/// macOS 26's Liquid Glass where available, the frosted HUD material elsewhere. A
/// frosted material lies over the clear glass, thinning to nothing at full clarity.
struct LiquidGlassMaterial: NSViewRepresentable {
  var clarity = 0.5
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.shellGlassMask) private var shellMask
  @Environment(\.glassBlendsWithinWindow) private var withinWindow

  func makeNSView(context: Context) -> ShellMaskedHost {
    if #available(macOS 26.0, *), !reduceTransparency {
      return LiquidShellHost(frostAlpha: GlassPreferences(clarity: clarity).frost)
    }
    return GlassBackdropView(reduceTransparency: reduceTransparency)
  }

  func updateNSView(_ view: ShellMaskedHost, context: Context) {
    (view as? GlassBackdropView)?.setReduceTransparency(reduceTransparency)
    (view as? GlassBackdropView)?.setWithinWindow(withinWindow)
    if let liquid = view as? LiquidShellHost {
      liquid.frost.alphaValue = GlassPreferences(clarity: clarity).frost
      liquid.frost.blendingMode = withinWindow ? .withinWindow : .behindWindow
    }
    view.shellMask = shellMask
  }
}

/// Clear Liquid Glass with a frost material over it, both cut to the shell's outline.
private final class LiquidShellHost: ShellMaskedHost {
  let frost = NSVisualEffectView()

  @available(macOS 26.0, *)
  init(frostAlpha: Double) {
    super.init(frame: .zero)
    frost.alphaValue = frostAlpha
    let glass = NSGlassEffectView()
    glass.style = .clear
    glass.cornerRadius = 0
    frost.material = GlassTokens.of(.shell).material
    frost.blendingMode = .behindWindow
    frost.state = .active
    frost.appearance = NSAppearance(named: .darkAqua)
    for view in [glass, frost] as [NSView] {
      view.frame = bounds
      view.autoresizingMask = [.width, .height]
      addSubview(view)
    }
    setAccessibilityElement(false)
  }

  required init?(coder: NSCoder) { nil }
}
