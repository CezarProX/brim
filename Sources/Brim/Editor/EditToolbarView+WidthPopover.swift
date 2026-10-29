import AppKit

extension EditToolbarView {
    @objc func widthButtonTapped(_ sender: NSButton) {
        if let widthPopover, widthPopover.isShown {
            widthPopover.performClose(nil)
            return
        }
        colorPopover?.performClose(nil)
        let controller = LineWidthPopoverController(initialWidth: currentStyle.lineWidth)
        controller.onChange = { [weak self] width in
            self?.updateStyle { $0.lineWidth = width }
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = controller
        popover.contentSize = LineWidthPopoverController.pickerSize
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxX)
        widthPopover = popover
    }
}

/// Explicit content bounds keep the slider and presets inside the native popover's inset.
@MainActor
final class LineWidthPopoverController: NSViewController {
    static let pickerSize = NSSize(width: 224, height: 132)
    var onChange: ((CGFloat) -> Void)?

    private var width: CGFloat
    private var slider: NSSlider!
    private let valueLabel = NSTextField(labelWithString: "")
    private var presetButtons: [WidthPresetButton] = []

    init(initialWidth: CGFloat) {
        width = initialWidth.isFinite ? min(10, max(1, initialWidth)) : 3
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = Self.pickerSize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let container = NSView(frame: NSRect(origin: .zero, size: Self.pickerSize))
        container.appearance = NSAppearance(named: .darkAqua)
        let title = NSTextField(labelWithString: "Stroke width")
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.textColor = .labelColor
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        let heading = NSStackView(views: [title, NSView(), valueLabel])
        heading.orientation = .horizontal
        heading.alignment = .centerY

        slider = NSSlider(value: Double(width), minValue: 1, maxValue: 10,
                          target: self, action: #selector(sliderChanged(_:)))
        // Commit once on release so a drag does not create dozens of undo steps.
        slider.isContinuous = false
        slider.controlSize = .small
        slider.setAccessibilityLabel("Stroke width")
        slider.setAccessibilityIdentifier("stroke-width-slider")

        presetButtons = [("Thin", CGFloat(2)), ("Medium", CGFloat(4)), ("Thick", CGFloat(8))].map { label, value in
            let button = WidthPresetButton(width: value, label: label, target: self, action: #selector(presetTapped(_:)))
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
            return button
        }
        let presets = NSStackView(views: presetButtons)
        presets.orientation = .horizontal
        presets.distribution = .fillEqually
        presets.spacing = 6

        for child in [heading, slider!, presets] {
            child.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(child)
        }
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            heading.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            heading.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            heading.heightAnchor.constraint(equalToConstant: 16),
            slider.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 10),
            slider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            slider.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            slider.heightAnchor.constraint(equalToConstant: 20),
            presets.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 16),
            presets.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            presets.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            presets.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])
        view = container
        refreshSelection()
    }

    private func refreshSelection() {
        valueLabel.stringValue = String(format: "%.1f pt", Double(width)).replacingOccurrences(of: ".0 pt", with: " pt")
        for button in presetButtons {
            button.state = abs(button.width - width) < 0.05 ? .on : .off
            button.needsDisplay = true
        }
    }

    private func selectWidth(_ value: CGFloat) {
        width = min(10, max(1, value))
        slider.doubleValue = Double(width)
        refreshSelection()
        onChange?(width)
    }

    @objc private func sliderChanged(_ sender: NSSlider) { selectWidth(CGFloat(sender.doubleValue)) }
    @objc private func presetTapped(_ sender: WidthPresetButton) { selectWidth(sender.width) }
}

/// Equal hit targets and an explicit selected state, with stroke samples at their actual widths.
private final class WidthPresetButton: NSButton {
    let width: CGFloat

    init(width: CGFloat, label: String, target: AnyObject?, action: Selector?) {
        self.width = width
        super.init(frame: .zero)
        self.target = target
        self.action = action
        title = label
        isBordered = false
        setButtonType(.pushOnPushOff)
        toolTip = "\(label) · \(Int(width)) pt"
        setAccessibilityLabel("\(label), \(Int(width)) points")
        setAccessibilityIdentifier("stroke-width-\(Int(width))")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ dirtyRect: NSRect) {
        let selected = state == .on
        let surface = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        NSColor.white.withAlphaComponent(isHighlighted ? 0.16 : selected ? 0.11 : 0.035).setFill()
        surface.fill()
        NSColor.white.withAlphaComponent(selected ? 0.26 : 0.07).setStroke()
        surface.lineWidth = 1
        surface.stroke()
        let stroke = NSBezierPath()
        stroke.move(to: NSPoint(x: bounds.midX - 13, y: 25))
        stroke.line(to: NSPoint(x: bounds.midX + 13, y: 25))
        stroke.lineWidth = width
        stroke.lineCapStyle = .round
        NSColor.white.withAlphaComponent(selected ? 1 : 0.75).setStroke()
        stroke.stroke()
        let text = "\(Int(width)) pt" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(selected ? 0.9 : 0.55)
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: 5), withAttributes: attributes)
    }
}
