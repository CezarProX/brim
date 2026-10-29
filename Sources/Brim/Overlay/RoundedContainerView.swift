// RoundedContainerView.swift
// Brim
//
// A thin floating-chrome container that gives a hosted view (the edit
// toolbar or the action bar) a subtle rounded background so it reads as a
// panel floating over the frozen screenshot rather than a bare control
// strip with no visual grounding.

import AppKit

final class RoundedContainerView: NSView {

    private let hosted: NSView
    private let padding: CGFloat

    init(hosting view: NSView, padding: CGFloat = 8) {
        self.hosted = view
        self.padding = padding
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.85).cgColor
        layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        layer?.borderWidth = 1
        addSubview(hosted)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Total size needed to host the wrapped view at its intrinsic size
    /// plus padding. `EditToolbarView`/`ActionBarView` both document a
    /// valid `intrinsicContentSize`, so this is a plain, no-Auto-Layout
    /// "fitting size" the positioner can lay frames out with directly.
    ///
    /// Named `panelSize` (not `fittingSize`) to avoid accidentally
    /// shadowing `NSView.fittingSize`, which is a different (Auto Layout
    /// driven) read-only property this class does not otherwise use.
    var panelSize: CGSize {
        let inner = hosted.intrinsicContentSize
        return CGSize(width: inner.width + padding * 2, height: inner.height + padding * 2)
    }

    override func layout() {
        super.layout()
        hosted.frame = bounds.insetBy(dx: padding, dy: padding)
    }
}
