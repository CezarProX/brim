// RecordingCountdown.swift
// Brim
//
// The 3-2-1 before recording starts: a frosted disc in the middle of the recorded display with a
// draining ring. Click it or press Esc to cancel.

import AppKit
import SwiftUI

@MainActor
final class RecordingCountdown {
    private var panel: NSPanel?
    private var keyMonitor: Any?

    /// Counts `seconds` down on `screen`; returns false if cancelled.
    func run(seconds: Int, on screen: NSScreen?) async -> Bool {
        guard seconds > 0 else { return true }
        let model = CountdownModel(total: seconds)
        let size = CGSize(width: 168, height: 168)
        let frame = (screen ?? NSScreen.main)?.frame ?? .zero
        let panel = NSPanel(contentRect: CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                                                width: size.width, height: size.height),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: CountdownView(model: model) { model.cancelled = true })
        panel.orderFrontRegardless()
        self.panel = panel
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return }
            MainActor.assumeIsolated { model.cancelled = true }
        }
        defer { close() }
        for remaining in stride(from: seconds, to: 0, by: -1) {
            model.remaining = remaining
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(100))
                if model.cancelled { return false }
            }
        }
        // Let the panel disappear before the first frame is captured.
        panel.orderOut(nil)
        try? await Task.sleep(for: .milliseconds(120))
        return !model.cancelled
    }

    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

@MainActor
private final class CountdownModel: ObservableObject {
    let total: Int
    @Published var remaining: Int
    var cancelled = false

    init(total: Int) {
        self.total = total
        remaining = total
    }
}

private struct CountdownView: View {
    @ObservedObject var model: CountdownModel
    let onCancel: () -> Void
    @State private var drain = 1.0

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
            Circle().fill(.black.opacity(0.45))
            Circle().trim(from: 0, to: drain)
                .stroke(Color(red: 1, green: 0.27, blue: 0.23), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(10)
            Text("\(model.remaining)")
                .font(.system(size: 76, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: true))
        }
        .padding(4)
        .onTapGesture(perform: onCancel)
        .onChange(of: model.remaining, initial: true) { _, _ in
            drain = 1
            withAnimation(.linear(duration: 1)) { drain = 0 }
        }
        .animation(.spring(duration: 0.35), value: model.remaining)
        .help("Click or press Esc to cancel")
        .accessibilityLabel("Recording starts in \(model.remaining)")
    }
}
