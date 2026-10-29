import AppKit
import SwiftUI

/// A progress ring that turns amber at 80% and red at 95%.
struct AgentUsageRing: View {
  let fraction: Double
  var tint: Color
  var lineWidth: CGFloat = 2

  static func color(fraction: Double, base: Color) -> Color {
    fraction >= 0.95 ? .red : fraction >= 0.80 ? .orange : base
  }

  var body: some View {
    ZStack {
      Circle().stroke(Color.white.opacity(0.14), lineWidth: lineWidth)
      Circle().trim(from: 0, to: max(0.02, min(1, fraction)))
        .stroke(Self.color(fraction: fraction, base: tint), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Usage \(Int((fraction * 100).rounded())) percent")
  }
}

/// An expanding ring that asks for attention. Core Animation drives it so SwiftUI isn't re-rendered per frame.
struct AgentAttentionPulse: NSViewRepresentable {
  var color: Color = .orange

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    view.wantsLayer = true
    let ring = CAShapeLayer()
    ring.fillColor = nil
    ring.lineWidth = 1.5
    ring.name = "ring"
    view.layer?.addSublayer(ring)
    return view
  }

  func updateNSView(_ view: NSView, context: Context) {
    guard let ring = view.layer?.sublayers?.first as? CAShapeLayer else { return }
    ring.frame = view.bounds
    ring.path = CGPath(ellipseIn: view.bounds.insetBy(dx: 2, dy: 2), transform: nil)
    ring.strokeColor = NSColor(color).cgColor
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      ring.opacity = 0.9
      return
    }
    guard ring.animation(forKey: "pulse") == nil else { return }
    let fade = CAKeyframeAnimation(keyPath: "opacity")
    fade.values = [0.95, 0.15, 0.95]
    fade.duration = 1.2
    fade.repeatCount = .infinity
    ring.add(fade, forKey: "pulse")
  }
}
