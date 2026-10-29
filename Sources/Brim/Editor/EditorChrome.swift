// EditorChrome.swift
// Brim
//
// Small shared visual helpers for the editor's floating chrome
// (`EditToolbarView`, `ActionBarView`): the dark translucent rounded
// background and swatch-image generation used by the color control.

import AppKit

@MainActor
enum EditorChrome {

    static let cornerRadius: CGFloat = 10
    static let controlSize: CGFloat = 24

    /// Installs a rounded, translucent `NSVisualEffectView` filling `view`,
    /// pinned behind any other subviews added after this call.
    static func installBackground(in view: NSView) {
        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.blendingMode = .withinWindow
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = cornerRadius
        effectView.layer?.masksToBounds = true
        effectView.translatesAutoresizingMaskIntoConstraints = false

        view.wantsLayer = true
        view.addSubview(effectView)
        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: view.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// Builds a small circular swatch image for a color-picker control.
    static func swatchImage(color: NSColor, diameter: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.lockFocus()
        let rect = NSRect(x: 1, y: 1, width: diameter - 2, height: diameter - 2)
        let path = NSBezierPath(ovalIn: rect)
        color.setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.7).setStroke()
        path.lineWidth = 1
        path.stroke()
        image.unlockFocus()
        return image
    }

    /// A template SF Symbol image sized/weighted for a toolbar button.
    static func symbolImage(_ name: String, accessibilityDescription: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let base = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)
        let configured = base?.withSymbolConfiguration(config) ?? base ?? NSImage()
        configured.isTemplate = true
        return configured
    }
}
