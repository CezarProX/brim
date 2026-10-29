import AppKit

extension EditToolbarView {
    @objc func colorButtonTapped(_ sender: NSButton) {
        if let colorPopover, colorPopover.isShown {
            colorPopover.performClose(nil)
            return
        }
        widthPopover?.performClose(nil)
        let controller = ColorSwatchPopoverController(initialColor: currentStyle.color)
        controller.onSelect = { [weak self] color in
            self?.updateStyle { $0.color = color }
            self?.colorPopover?.performClose(nil)
        }
        controller.onOpenColorPanel = { [weak self] in
            self?.colorPopover?.performClose(nil)
            self?.openColorPanel()
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = controller
        popover.contentSize = ColorSwatchPopoverController.pickerSize
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxX)
        colorPopover = popover
    }

    private func openColorPanel() {
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.color = currentStyle.color
        // Keep a color drag to one annotation edit and one undo step.
        panel.isContinuous = false
        if let host = window {
            panel.parent?.removeChildWindow(panel)
            // Capture overlays sit above ordinary floating panels. Keep the palette
            // with its editor so it also hides when that editor is dismissed.
            host.addChildWindow(panel, ordered: .above)
            if let screen = host.screen {
                let anchor = host.convertToScreen(convert(bounds, to: nil))
                let visible = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(
                    x: max(visible.minX, min(anchor.maxX + 12, visible.maxX - panel.frame.width)),
                    y: max(visible.minY, min(anchor.midY - panel.frame.height / 2, visible.maxY - panel.frame.height))
                ))
            }
        }
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        updateStyle { $0.color = sender.color }
    }
}

/// Matches the width picker, with explicit insets around every swatch and the footer.
@MainActor
final class ColorSwatchPopoverController: NSViewController {
    static let pickerSize = NSSize(width: 224, height: 132)
    var onSelect: ((NSColor) -> Void)?
    var onOpenColorPanel: (() -> Void)?

    private let initialColor: NSColor
    private static let swatchColors: [NSColor] = [
        .systemRed, .systemYellow, .systemGreen, .systemBlue, .black, .white
    ]

    init(initialColor: NSColor = .systemRed) {
        self.initialColor = initialColor
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = Self.pickerSize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let container = NSView(frame: NSRect(origin: .zero, size: Self.pickerSize))
        container.appearance = NSAppearance(named: .darkAqua)
        let title = NSTextField(labelWithString: "Color")
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.textColor = .labelColor

        let grid = NSStackView(views: Self.swatchColors.map(makeSwatchButton))
        grid.orientation = .horizontal
        grid.distribution = .fillEqually
        grid.spacing = 4

        let moreButton = NSButton(title: "More Colors…", target: self, action: #selector(moreTapped))
        moreButton.bezelStyle = .rounded
        moreButton.controlSize = .small
        moreButton.font = .systemFont(ofSize: 11, weight: .medium)
        moreButton.setAccessibilityIdentifier("more-colors")

        for child in [title, grid, moreButton] {
            child.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(child)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            title.heightAnchor.constraint(equalToConstant: 16),
            grid.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            grid.heightAnchor.constraint(equalToConstant: 30),
            moreButton.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 18),
            moreButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            moreButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            moreButton.heightAnchor.constraint(equalToConstant: 28),
            moreButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])
        view = container
    }

    private func makeSwatchButton(color: NSColor) -> NSButton {
        let button = ColorPresetButton(color: color, target: self, action: #selector(swatchTapped(_:)))
        button.state = colorsMatch(initialColor, color) ? .on : .off
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return button
    }

    private func colorsMatch(_ left: NSColor, _ right: NSColor) -> Bool {
        guard let left = left.usingColorSpace(.deviceRGB), let right = right.usingColorSpace(.deviceRGB) else { return false }
        return abs(left.redComponent - right.redComponent) < 0.005
            && abs(left.greenComponent - right.greenComponent) < 0.005
            && abs(left.blueComponent - right.blueComponent) < 0.005
            && abs(left.alphaComponent - right.alphaComponent) < 0.005
    }

    @objc private func swatchTapped(_ sender: ColorPresetButton) { onSelect?(sender.color) }
    @objc private func moreTapped() { onOpenColorPanel?() }
}

/// A ring marks the selected color without covering the swatch itself.
private final class ColorPresetButton: NSButton {
    let color: NSColor

    init(color: NSColor, target: AnyObject?, action: Selector?) {
        self.color = color
        super.init(frame: .zero)
        self.target = target
        self.action = action
        // The name belongs in accessibility, not the cell's invisible text sizing.
        title = ""
        toolTip = color.accessibilityName
        isBordered = false
        setButtonType(.pushOnPushOff)
        setAccessibilityLabel(color.accessibilityName)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { NSSize(width: 28, height: 30) }

    override func draw(_ dirtyRect: NSRect) {
        let diameter = min(bounds.width, bounds.height) - 8
        let rect = NSRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2,
                          width: diameter, height: diameter)
        let swatch = NSBezierPath(ovalIn: rect)
        color.setFill()
        swatch.fill()
        NSColor.white.withAlphaComponent(0.22).setStroke()
        swatch.lineWidth = 1
        swatch.stroke()
        if state == .on || isHighlighted {
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: -3, dy: -3))
            NSColor.white.withAlphaComponent(isHighlighted ? 1 : 0.85).setStroke()
            ring.lineWidth = 1.5
            ring.stroke()
        }
    }
}
