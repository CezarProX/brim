// EditToolbarView.swift
// Brim
//
// The vertical annotation toolbar: tool buttons, color + line-width
// controls (in EditToolbarView+ColorPopover.swift /
// +WidthPopover.swift), and undo/redo/clear. All state is driven by
// `EditorSession` — this view has no state of its own beyond the popovers
// it briefly owns while open.

import AppKit

@MainActor
final class EditToolbarView: NSView {

    private let session: EditorSession

    private var toolButtons: [AnnotationTool: NSButton] = [:]
    var onLayoutChanged: (() -> Void)?
    private var styleSeparator: NSView!
    private var clearButton: NSButton!
    private(set) var colorButton: NSButton!
    private(set) var widthButton: NSButton!
    private var stack: NSStackView!

    var colorPopover: NSPopover?
    var widthPopover: NSPopover?

    private static let toolOrder: [(AnnotationTool, String, String)] = [
        (.pen, "pencil", "Pen"),
        (.arrow, "arrow.up.right", "Arrow"),
        (.rectangle, "rectangle", "Rectangle"),
        (.text, "textformat", "Text")
    ]

    init(session: EditorSession) {
        self.session = session
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        EditorChrome.installBackground(in: self)
        buildControls()

        session.addObserver { [weak self] in self?.refreshState() }
        refreshState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // `RoundedContainerView.panelSize` (and, through it,
    // `ToolbarPositioner`) sizes this view's floating container from this
    // value. Returning `NSView.noIntrinsicMetric` for the height (as if a
    // vertical stack of fixed-size buttons had no natural height) made the
    // container collapse to a sliver a few points tall, hiding every tool
    // button. `stack.fittingSize.height` reports the actual height needed
    // to lay out every button/separator at its fixed size.
    override var intrinsicContentSize: NSSize {
        NSSize(width: 40, height: stack.fittingSize.height)
    }

    // MARK: - Layout

    private func buildControls() {
        var arrangedViews: [NSView] = []

        for (tool, symbol, name) in Self.toolOrder {
            let button = makeButton(
                symbol: symbol,
                tooltip: "\(name)",
                action: #selector(toolButtonTapped(_:))
            )
            toolButtons[tool] = button
            arrangedViews.append(button)
        }

        styleSeparator = makeSeparator()
        arrangedViews.append(styleSeparator)

        let colorButton = makeButton(symbol: "circle.fill", tooltip: "Color", action: #selector(colorButtonTapped(_:)))
        self.colorButton = colorButton
        arrangedViews.append(colorButton)

        let widthButton = makeButton(symbol: "lineweight", tooltip: "Line width", action: #selector(widthButtonTapped(_:)))
        self.widthButton = widthButton
        arrangedViews.append(widthButton)

        arrangedViews.append(makeSeparator())

        let moreButton = makeButton(symbol: "ellipsis", tooltip: "More editing options", action: #selector(moreTapped(_:)))
        clearButton = makeButton(symbol: "trash", tooltip: "Delete selected annotation", action: #selector(clearTapped))
        arrangedViews.append(contentsOf: [moreButton, clearButton])

        let stack = NSStackView(views: arrangedViews)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        self.stack = stack

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    private func makeButton(symbol: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton(image: EditorChrome.symbolImage(symbol, accessibilityDescription: tooltip), target: self, action: action)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = tooltip
        button.contentTintColor = .secondaryLabelColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: EditorChrome.controlSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: EditorChrome.controlSize).isActive = true
        return button
    }

    private func makeSeparator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: 24).isActive = true
        return line
    }

    // MARK: - Actions

    @objc private func toolButtonTapped(_ sender: NSButton) {
        guard let tool = toolButtons.first(where: { $0.value === sender })?.key else { return }
        if tool == .arrow {
            showToolMenu(sender)
        } else {
            session.currentTool = (session.currentTool == tool) ? nil : tool
        }
    }

    @objc private func undoTapped() { session.undo() }
    @objc private func redoTapped() { session.redo() }
    @objc private func clearTapped() { session.deleteSelected() }

    private func showToolMenu(_ sender: NSButton) {
        let menu = NSMenu()
        for (title, action, tool) in [
            ("Arrow", #selector(arrowTapped), AnnotationTool.arrow),
            ("Line", #selector(lineTapped), AnnotationTool.line)
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.state = session.currentTool == tool ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: sender.bounds.maxX, y: sender.bounds.maxY), in: sender)
    }

    @objc private func arrowTapped() { session.currentTool = session.currentTool == .arrow ? nil : .arrow }
    @objc private func lineTapped() { session.currentTool = session.currentTool == .line ? nil : .line }
    @objc private func highlighterTapped() { session.currentTool = session.currentTool == .highlighter ? nil : .highlighter }

    @objc private func moreTapped(_ sender: NSButton) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (title, action, key, enabled) in [
            ("Highlighter", #selector(highlighterTapped), "", true),
            ("Undo", #selector(undoTapped), "z", session.document.canUndo),
            ("Redo", #selector(redoTapped), "Z", session.document.canRedo)
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            item.isEnabled = enabled
            if action == #selector(redoTapped) { item.keyEquivalentModifierMask = [.command, .shift] }
            if action == #selector(highlighterTapped) { item.state = session.currentTool == .highlighter ? .on : .off }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: sender.bounds.maxX, y: sender.bounds.maxY), in: sender)
    }

    // MARK: - State sync

    private func refreshState() {
        for (tool, button) in toolButtons {
            let selected = session.currentTool == tool || (tool == .arrow && session.currentTool == .line)
            button.contentTintColor = selected ? .controlAccentColor : .secondaryLabelColor
        }
        let showStyle = session.currentTool != nil || session.selectedAnnotationID != nil
        colorButton.isHidden = !showStyle
        widthButton.isHidden = !showStyle || session.currentTool == .text
        styleSeparator.isHidden = !showStyle
        clearButton.isHidden = session.selectedAnnotationID == nil
        if !showStyle {
            colorPopover?.close()
            widthPopover?.close()
        }
        invalidateIntrinsicContentSize()
        onLayoutChanged?()
        colorButton.image = EditorChrome.swatchImage(color: session.currentStyle.color)
    }

    /// Applies a new style value, used by the color/width popovers.
    func updateStyle(_ transform: (inout AnnotationStyle) -> Void) {
        var style = session.currentStyle
        transform(&style)
        session.currentStyle = style
    }

    var currentStyle: AnnotationStyle { session.currentStyle }
}
