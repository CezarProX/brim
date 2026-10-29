// GlassSurface.swift
// Brim
//
// The views every glass surface is drawn with, all reading `GlassStyle`:
// - `GlassSurface`: a surface that blurs what is behind it (Liquid Glass on macOS 26, an AppKit
//   material before), darkened by the readability tint, with a sheen, a hairline rim and a shadow.
// - `GlassCardBackground`: a card layered on glass that is already there (Home widgets, app pages).
// - `GlassWindowBackdrop`: a whole window's frosted background (Settings, Notes, dialogs).
// Each falls back to a solid fill under Reduce Transparency and strengthens its rim under Increase
// Contrast.

import AppKit
import SwiftUI

/// Resolves the preferences a surface paints with: the override (renders), else the island theme,
/// plus the accessibility settings in force.
private struct GlassPreferencesReader<Content: View>: View {
  @ViewBuilder let content: (GlassPreferences) -> Content
  @ObservedObject private var theme = IslandTheme.shared
  @Environment(\.glassPreferencesOverride) private var override
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View { content(preferences) }

  private var preferences: GlassPreferences {
    var prefs = override ?? GlassPreferences(tinted: theme.tinted, clarity: theme.clarity)
    if reduceTransparency { prefs.reduceTransparency = true }
    if contrast == .increased { prefs.increaseContrast = true }
    return prefs
  }
}

/// A glass surface that blurs what lies behind it. Use as a `.background`.
struct GlassSurface<S: Shape>: View {
  let role: GlassRole
  let shape: S
  /// A colour wash over the glass, e.g. an activity tint. Kept faint so text stays readable.
  var wash: Color?
  /// Shadow under the surface; panels in their own window draw it here.
  var showsShadow = true
  @Environment(\.islandBackdropSnapshot) private var snapshot
  @Environment(\.glassBlendsWithinWindow) private var withinWindow

  var body: some View {
    GlassPreferencesReader { prefs in
      let tokens = GlassTokens.of(role)
      let stroke = prefs.stroke(for: role)
      ZStack {
        if prefs.reduceTransparency {
          shape.fill(Color(white: tokens.solid))
        } else {
          backdrop(tokens: tokens, prefs: prefs)
          shape.fill(Color.black.opacity(prefs.veil(for: role, materialGray: materialGray(prefs))))
          if let wash { shape.fill(wash.opacity(0.12)) }
          shape.fill(
            LinearGradient(
              colors: [.white.opacity(tokens.sheen), .white.opacity(0)], startPoint: .top, endPoint: .center))
        }
      }
      .clipShape(shape)
      .overlay {
        shape.stroke(
          LinearGradient(
            colors: [.white.opacity(stroke.top), .white.opacity(stroke.bottom)], startPoint: .top, endPoint: .bottom),
          lineWidth: stroke.width * 2
        )
        .clipShape(shape)
      }
      .shadow(color: .black.opacity(showsShadow ? tokens.shadow : 0), radius: tokens.shadowRadius, y: tokens.shadowRadius / 3)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private var usesLiquid: Bool { snapshot == nil && GlassSupport.hasLiquidGlass }

  private func materialGray(_ prefs: GlassPreferences) -> Double {
    prefs.materialGray(for: role, liquid: usesLiquid)
  }

  @ViewBuilder
  private func backdrop(tokens: GlassTokens, prefs: GlassPreferences) -> some View {
    if let snapshot {
      SnapshotBlur(snapshot: snapshot, radius: GlassClarity(prefs.clarity).blurRadius(base: 22)).clipShape(shape)
    } else if #available(macOS 26.0, *) {
      ZStack {
        LiquidGlassFill(shape: shape, clear: tokens.liquidClear)
        // The capsule fades with the island; an AppKit material would ignore that fade.
        if role != .capsule {
          GlassMaterialView(material: tokens.material, withinWindow: withinWindow, dark: true)
            .opacity(prefs.frost)
            .clipShape(shape)
        }
      }
    } else {
      GlassMaterialView(material: tokens.material, withinWindow: withinWindow, dark: true).clipShape(shape)
    }
  }
}

/// SwiftUI's Liquid Glass filling `shape`.
@available(macOS 26.0, *)
struct LiquidGlassFill<S: Shape>: View {
  let shape: S
  var clear = false

  var body: some View {
    Color.clear.glassEffect(clear ? .clear : .regular, in: shape)
  }
}

/// A card layered on glass that is already there: a faint white
/// fill, a sheen at the top and a hairline rim that catches the light, without blurring again.
struct GlassCardBackground<S: Shape>: View {
  let shape: S
  /// Overrides the role's fill, e.g. a brighter one while hovered or selected.
  var fill: Color?

  var body: some View {
    GlassPreferencesReader { prefs in
      let tokens = GlassTokens.of(.card)
      let stroke = prefs.stroke(for: .card)
      ZStack {
        if prefs.reduceTransparency {
          shape.fill(Color(white: tokens.solid))
        }
        shape.fill(fill ?? Color.white.opacity(tokens.cardFill))
        shape.fill(
          LinearGradient(colors: [.white.opacity(tokens.sheen), .white.opacity(0)], startPoint: .top, endPoint: .center))
      }
      .clipShape(shape)
      .overlay {
        shape.stroke(
          LinearGradient(
            colors: [.white.opacity(stroke.top), .white.opacity(stroke.bottom)], startPoint: .top, endPoint: .bottom),
          lineWidth: stroke.width * 2
        )
        .clipShape(shape)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

extension View {
  /// Sits this content on a layered glass card (inside the island or another glass surface).
  func glassCard(radius: CGFloat = IslandRadius.medium, fill: Color? = nil) -> some View {
    background { GlassCardBackground(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), fill: fill) }
  }

  /// Sits this content on a floating glass panel that blurs the desktop behind it.
  func glassPanel(radius: CGFloat, role: GlassRole = .panel, wash: Color? = nil, shadow: Bool = true) -> some View {
    background {
      GlassSurface(
        role: role, shape: RoundedRectangle(cornerRadius: radius, style: .continuous), wash: wash, showsShadow: shadow)
    }
  }
}

// MARK: - Windows

/// A window's frosted background: the desktop blurred behind the window, under an appearance-aware
/// veil (the window colour) thick enough for labels to stay readable. Ignore the safe area so it
/// reaches under a transparent title bar.
struct GlassWindowBackdrop: View {
  /// Follow the system appearance (Settings) or stay dark (island-styled windows).
  var forcesDark = false
  @Environment(\.glassRenderBackdrop) private var renderBackdrop

  var body: some View {
    GlassPreferencesReader { prefs in
      let tokens = GlassTokens.of(.window)
      ZStack {
        if prefs.reduceTransparency {
          Color(nsColor: .windowBackgroundColor)
        } else {
          if let renderBackdrop {
            Image(nsImage: renderBackdrop).resizable()
          }
          GlassMaterialView(material: tokens.material, withinWindow: renderBackdrop != nil, dark: forcesDark)
          veil(prefs, tokens: tokens)
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private func veil(_ prefs: GlassPreferences, tokens: GlassTokens) -> some View {
    let amount = prefs.veil(for: .window, materialGray: GlassMaterialGray.of(tokens.material))
    if forcesDark {
      Color.black.opacity(amount)
    } else {
      // The window colour darkens in Dark mode and lightens in Light mode, so labels keep contrast.
      Color(nsColor: .windowBackgroundColor).opacity(amount)
    }
  }
}

private struct GlassRenderBackdropKey: EnvironmentKey {
  static let defaultValue: NSImage? = nil
}

extension EnvironmentValues {
  /// Render tests only: a wallpaper drawn inside the window for its glass to blur.
  var glassRenderBackdrop: NSImage? {
    get { self[GlassRenderBackdropKey.self] }
    set { self[GlassRenderBackdropKey.self] = newValue }
  }
}

/// An `NSVisualEffectView` that always looks active, even in a window that is not key.
struct GlassMaterialView: NSViewRepresentable {
  let material: NSVisualEffectView.Material
  var withinWindow = false
  /// Dark appearance regardless of the system (island-styled surfaces); false follows the window.
  var dark = false

  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = PassiveEffectView()
    view.state = .active
    view.setAccessibilityElement(false)
    update(view)
    return view
  }

  func updateNSView(_ view: NSVisualEffectView, context: Context) { update(view) }

  private func update(_ view: NSVisualEffectView) {
    view.material = material
    view.blendingMode = withinWindow ? .withinWindow : .behindWindow
    view.appearance = dark ? NSAppearance(named: .darkAqua) : nil
  }
}

/// Lets clicks fall through to the content above.
private final class PassiveEffectView: NSVisualEffectView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Window chrome for glass windows: content under a transparent title bar, the window itself clear
/// so the glass background shows through edge to edge.
enum GlassWindowChrome {
  static func apply(to window: NSWindow) {
    window.styleMask.insert(.fullSizeContentView)
    window.titlebarAppearsTransparent = true
    window.isOpaque = false
    window.backgroundColor = .clear
  }
}
