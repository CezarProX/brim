// AppIconRenderer.swift
// Brim
//
// AppKit wrappers around BrimIconArt: the app icon for each variant as an NSImage (the Settings
// picker, About, onboarding and alternate Dock icons) and the template menu-bar glyph.

import AppKit

@MainActor
enum AppIconRenderer {
  /// The Brim logo bundled by build_app.sh (Resources/AppIcon/BrimLogo.png); nil under swift run and tests.
  static let logo: NSImage? = Bundle.main.url(forResource: "BrimLogo", withExtension: "png").flatMap(NSImage.init(contentsOf:))

  /// A square icon `size` points on a side. The default is the Brim logo; the colourways (and the
  /// default without a bundled logo) are drawn lazily, so they stay sharp at any backing scale.
  static func image(for variant: AppIconVariant, size: CGFloat) -> NSImage {
    if variant == .standard, let logo {
      return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        logo.draw(in: rect)
        return true
      }
    }
    let palette = variant.palette
    return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
      guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
      BrimIconArt.draw(in: ctx, size: size, palette: palette)
      return true
    }
  }

  /// The Brim mark for the menu bar: an 18 pt template image, so macOS tints it for light, dark and
  /// highlighted menu bars.
  static func menuBarGlyph(accessibilityDescription: String = "Brim") -> NSImage {
    let side: CGFloat = 18
    let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
      guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
      BrimIconArt.drawGlyph(in: ctx, points: side)
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = accessibilityDescription
    return image
  }
}
