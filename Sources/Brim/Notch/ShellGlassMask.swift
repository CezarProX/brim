import AppKit
import SwiftUI

/// The shell outline the open island's blur is cut to, in the transition's in-flight values.
///
/// AppKit blur views snap to their final frame when the island opens, and SwiftUI clips them with
/// the final shape rather than the animating one, so the glass showed as a full-size slab that the
/// growing shell only caught up with at the end. The blur cuts itself to this outline every frame.
struct ShellGlassMask: Equatable {
  var size: CGSize
  var expansion: CGFloat
  var floating: Bool
  var closedHeight: CGFloat

  /// The outline in a view of `bounds`: top-anchored and centred like the shell's frame.
  func path(in bounds: CGRect, flipped: Bool) -> CGPath {
    let rect = CGRect(x: bounds.midX - size.width / 2, y: 0, width: size.width, height: size.height)
    let path = NotchSurfaceShape(expansion: expansion, floating: floating, closedHeight: closedHeight).path(in: rect)
    guard !flipped else { return path.cgPath }
    return path.applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.height)).cgPath
  }
}

private struct ShellGlassMaskKey: EnvironmentKey {
  static let defaultValue: ShellGlassMask? = nil
}

extension EnvironmentValues {
  var shellGlassMask: ShellGlassMask? {
    get { self[ShellGlassMaskKey.self] }
    set { self[ShellGlassMaskKey.self] = newValue }
  }
}

/// Re-evaluated on every animation frame, so the blur below receives the shell's in-flight outline.
struct ShellGlassMasking: ViewModifier, Animatable {
  var mask: ShellGlassMask

  var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
    get { AnimatablePair(mask.expansion, AnimatablePair(mask.size.width, mask.size.height)) }
    set {
      mask.expansion = newValue.first
      mask.size = CGSize(width: newValue.second.first, height: newValue.second.second)
    }
  }

  func body(content: Content) -> some View {
    content.environment(\.shellGlassMask, mask)
  }
}

/// Hosts a blur view and applies `shellMask` to it; nil leaves the blur unmasked.
class ShellMaskedHost: NSView {
  var shellMask: ShellGlassMask? {
    didSet { if shellMask != oldValue { applyShellMask() } }
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func layout() {
    super.layout()
    applyShellMask()
  }

  private func applyShellMask() {
    guard let shellMask else {
      layer?.mask = nil
      return
    }
    wantsLayer = true
    let shape = (layer?.mask as? CAShapeLayer) ?? CAShapeLayer()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    shape.frame = bounds
    shape.path = shellMask.path(in: bounds, flipped: isFlipped)
    layer?.mask = shape
    CATransaction.commit()
  }
}
