// ActionBarView.swift
// Brim
//
// The horizontal action bar shown alongside the annotation canvas: Upload,
// Share and Print in a secondary menu; Copy, Save and Close stay visible. Purely a dumb view over
// `ActionBarCallbacks` — it has no knowledge of `EditorSession` and performs
// no capture/export logic itself; that's the caller's responsibility (e.g.
// `share` is expected to trigger an `NSSharingServicePicker` from the
// callback owner).

import AppKit

/// The set of actions the action bar can trigger. Owned/constructed by
/// whichever controller assembles the editing UI (outside this directory);
/// this struct is just the callback contract.
@MainActor
struct ActionBarCallbacks {
    var upload: () -> Void
    var share: () -> Void
    var print: () -> Void
    var copy: () -> Void
    var save: () -> Void
    var close: () -> Void

    init(
        upload: @escaping () -> Void,
        share: @escaping () -> Void,
        print: @escaping () -> Void,
        copy: @escaping () -> Void,
        save: @escaping () -> Void,
        close: @escaping () -> Void
    ) {
        self.upload = upload
        self.share = share
        self.print = print
        self.copy = copy
        self.save = save
        self.close = close
    }
}

@MainActor
final class ActionBarView: NSView {

    private let callbacks: ActionBarCallbacks
    private var stack: NSStackView!

    init(callbacks: ActionBarCallbacks) {
        self.callbacks = callbacks
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        EditorChrome.installBackground(in: self)
        buildButtons()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // See the matching note on `EditToolbarView.intrinsicContentSize`:
    // returning `NSView.noIntrinsicMetric` for the width made
    // `RoundedContainerView.panelSize` compute a near-zero-width container,
    // hiding the whole action bar. `stack.fittingSize.width` reports the
    // actual width needed for every button + spacing + insets.
    override var intrinsicContentSize: NSSize {
        NSSize(width: stack.fittingSize.width, height: 36)
    }

    private func buildButtons() {
        let specs: [(symbol: String, tooltip: String, action: Selector)] = [
            ("doc.on.doc", "Copy (⌘C)", #selector(copyTapped)),
            ("square.and.arrow.down", "Save (⌘S)", #selector(saveTapped)),
            ("ellipsis", "More actions", #selector(moreTapped(_:))),
            ("xmark", "Close (Esc)", #selector(closeTapped))
        ]

        let buttons = specs.map { spec in
            makeButton(symbol: spec.symbol, tooltip: spec.tooltip, action: spec.action)
        }

        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        self.stack = stack

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func makeButton(symbol: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton(image: EditorChrome.symbolImage(symbol, accessibilityDescription: tooltip), target: self, action: action)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = tooltip
        button.contentTintColor = .labelColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: EditorChrome.controlSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: EditorChrome.controlSize).isActive = true
        return button
    }

    @objc private func moreTapped(_ sender: NSButton) {
        let menu = NSMenu()
        for (title, action, key) in [
            ("Upload", #selector(uploadTapped), "u"),
            ("Share…", #selector(shareTapped), ""),
            ("Print…", #selector(printTapped), "p")
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY), in: sender)
    }

    @objc private func uploadTapped() { callbacks.upload() }
    @objc private func shareTapped() { callbacks.share() }
    @objc private func printTapped() { callbacks.print() }
    @objc private func copyTapped() { callbacks.copy() }
    @objc private func saveTapped() { callbacks.save() }
    @objc private func closeTapped() { callbacks.close() }
}
