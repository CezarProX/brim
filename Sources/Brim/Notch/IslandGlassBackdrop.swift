import AppKit
import SwiftUI

/// This uses the window server's backdrop, without capturing or persisting screen pixels.
struct IslandGlassMaterial: NSViewRepresentable {
  /// Pale frosted glass (macOS Light mode) instead of the dark HUD material.
  var light = false
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.shellGlassMask) private var shellMask
  @Environment(\.glassBlendsWithinWindow) private var withinWindow

  func makeNSView(context: Context) -> GlassBackdropView {
    let view = GlassBackdropView(reduceTransparency: reduceTransparency, light: light)
    view.setWithinWindow(withinWindow)
    return view
  }

  func updateNSView(_ view: GlassBackdropView, context: Context) {
    view.setReduceTransparency(reduceTransparency)
    view.setLight(light)
    view.setWithinWindow(withinWindow)
    view.shellMask = shellMask
  }
}

final class GlassBackdropView: ShellMaskedHost {
  private let effect = NSVisualEffectView()

  init(reduceTransparency: Bool, light: Bool = false) {
    super.init(frame: .zero)
    wantsLayer = true
    effect.material = .hudWindow
    effect.blendingMode = .behindWindow
    effect.state = .active
    effect.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
    effect.autoresizingMask = [.width, .height]
    addSubview(effect)
    setAccessibilityElement(false)
    setReduceTransparency(reduceTransparency)
  }

  required init?(coder: NSCoder) { nil }

  /// Render tests blur a wallpaper inside the window instead of the desktop.
  func setWithinWindow(_ within: Bool) {
    effect.blendingMode = within ? .withinWindow : .behindWindow
  }

  func setLight(_ light: Bool) {
    effect.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
  }

  func setReduceTransparency(_ reduceTransparency: Bool) {
    effect.isHidden = reduceTransparency
    layer?.backgroundColor =
      reduceTransparency
      ? NSColor(calibratedWhite: 0.08, alpha: 1).cgColor : NSColor.clear.cgColor
  }
}
