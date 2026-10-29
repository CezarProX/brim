import AppKit
import SwiftUI

/// Bars animated by Core Animation in the render server. A SwiftUI timeline here re-laid out
/// the whole notch hosting view 30 times a second for as long as music played.
struct PlaybackWaveform: NSViewRepresentable {
    let isPlaying: Bool
    var colored = false
    /// Accent sampled from the artwork; falls back to the neutral music gradient.
    var tint: Color?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> WaveformLayerView { WaveformLayerView() }

    func updateNSView(_ view: WaveformLayerView, context: Context) {
        let settings = AppSettings.shared
        let gradient = settings.visualizerStyle == .gradient
        let accent = tint ?? (gradient ? ArtworkTint.color(for: NowPlayingModel.shared.track?.artwork) : nil)
        let colors: [NSColor]
        if gradient, let accent {
            let base = NSColor(accent)
            colors = [base.blended(withFraction: 0.4, of: .white) ?? base,
                      base.blended(withFraction: 0.3, of: .black) ?? base]
        } else if colored || gradient {
            colors = accent.map { [NSColor($0), NSColor($0.opacity(0.55))] }
                ?? [NSColor(red: 0.48, green: 0.62, blue: 0.78, alpha: 1), NSColor(red: 0.78, green: 0.37, blue: 0.25, alpha: 1)]
        } else {
            colors = [NSColor.white.withAlphaComponent(0.78)]
        }
        view.configure(WaveformLayerView.Style(
            count: colored || gradient ? 5 : 4, colors: colors, playing: isPlaying,
            reduceMotion: reduceMotion, live: settings.liveVisualizerEnabled && isPlaying))
    }

    static func dismantleNSView(_ view: WaveformLayerView, coordinator: ()) { view.detachLive() }
}

final class WaveformLayerView: NSView {
    struct Style: Equatable {
        let count: Int
        let colors: [NSColor]
        let playing: Bool
        let reduceMotion: Bool
        /// Follow real audio levels from `LiveAudioMonitor` when it has them.
        var live = false
    }

    private var style: Style?
    private var liveToken: UUID?
    private var liveActive = false
    private var bars: [CAGradientLayer] = []
    private var laidOutSize: CGSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    func configure(_ next: Style) {
        guard next != style else { return }
        style = next
        if next.live { attachLive() } else { detachLive() }
        rebuild()
    }

    func detachLive() {
        if let liveToken { LiveAudioMonitor.shared.removeObserver(liveToken) }
        liveToken = nil
        liveActive = false
    }

    private func attachLive() {
        guard liveToken == nil else { return }
        liveToken = LiveAudioMonitor.shared.addObserver { [weak self] levels in self?.apply(levels: levels) }
    }

    /// Real levels drive the bars directly; nil hands control back to the synthetic wave.
    func apply(levels: [Float]?) {
        guard let style else { return }
        guard let levels else {
            if liveActive { liveActive = false; rebuild() }
            return
        }
        if !liveActive || bars.count != levels.count {
            liveActive = true
            rebuild(barCount: levels.count)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (bar, rect) in zip(bars, WaveformDrawing.liveBars(in: bounds.size, levels: levels)) {
            bar.frame = rect
            bar.cornerRadius = rect.width / 2
        }
        CATransaction.commit()
        _ = style
    }

    override func layout() {
        super.layout()
        guard bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        rebuild()
    }

    private func rebuild(barCount: Int? = nil) {
        guard let style, let host = layer else { return }
        let count = barCount ?? style.count
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if bars.count != count {
            bars.forEach { $0.removeFromSuperlayer() }
            bars = (0..<count).map { _ in CAGradientLayer() }
            bars.forEach(host.addSublayer)
        }
        let colors = (style.colors.count == 1 ? style.colors + style.colors : style.colors).map(\.cgColor)
        let rects = WaveformDrawing.bars(in: bounds.size, count: count, time: 0,
            playing: style.playing, reduceMotion: true)
        for (index, (bar, rect)) in zip(bars, rects).enumerated() {
            bar.colors = colors
            bar.frame = rect
            bar.cornerRadius = rect.width / 2
            bar.removeAllAnimations()
            guard style.playing, !style.reduceMotion, !liveActive else { continue }
            bar.add(WaveformDrawing.animation(index: index, height: bounds.height), forKey: "wave")
        }
    }
}

enum WaveformDrawing {
    /// Bars whose heights follow audio `levels` (0...1), centered like the synthetic wave.
    static func liveBars(in size: CGSize, levels: [Float]) -> [CGRect] {
        guard size.width > 0, size.height > 0, !levels.isEmpty else { return [] }
        let count = levels.count
        let width = min(3.0, size.width / CGFloat(count * 2 - 1))
        let gap = min(2.0, width)
        let total = CGFloat(count) * width + CGFloat(count - 1) * gap
        return levels.enumerated().map { index, level in
            let unit = CGFloat(level.isFinite ? min(1, max(0, level)) : 0)
            let height = max(min(2, size.height), size.height * (0.12 + 0.88 * unit))
            return CGRect(x: (size.width - total) / 2 + CGFloat(index) * (width + gap),
                          y: (size.height - height) / 2, width: width, height: height)
        }
    }

    static func bars(in size: CGSize, count: Int, time: TimeInterval, playing: Bool, reduceMotion: Bool) -> [CGRect] {
        guard size.width > 0, size.height > 0, count > 0 else { return [] }
        let width = min(3.0, size.width / CGFloat(count * 2 - 1))
        let gap = min(2.0, width)
        let total = CGFloat(count) * width + CGFloat(count - 1) * gap
        return (0..<count).map { index in
            let fraction: CGFloat
            if !playing { fraction = 0.17 }
            else if reduceMotion { fraction = [0.4, 0.85, 0.6, 0.45, 0.7][index % 5] }
            else {
                let phase = time * (4.1 + Double(index) * 0.63) + Double(index) * 1.7
                fraction = 0.22 + 0.72 * CGFloat((sin(phase) + 1) / 2)
            }
            let height = max(min(2, size.height), size.height * fraction)
            return CGRect(x: (size.width - total) / 2 + CGFloat(index) * (width + gap),
                          y: (size.height - height) / 2, width: width, height: height)
        }
    }

    /// The same motion as `bars`, as a repeating Core Animation on one bar's height.
    static func animation(index: Int, height: CGFloat) -> CAAnimation {
        let speed = 4.1 + Double(index) * 0.63
        let period = 2 * Double.pi / speed
        let steps = 12
        let heights = (0...steps).map { step -> CGFloat in
            let phase = 2 * Double.pi * Double(step) / Double(steps)
            return max(min(2, height), height * (0.22 + 0.72 * CGFloat((sin(phase) + 1) / 2)))
        }
        let wave = CAKeyframeAnimation(keyPath: "bounds.size.height")
        wave.values = heights
        wave.calculationMode = .cubic
        wave.duration = period
        wave.repeatCount = .infinity
        wave.timeOffset = period * (Double(index) * 1.7).truncatingRemainder(dividingBy: 2 * .pi) / (2 * .pi)
        wave.isRemovedOnCompletion = false
        return wave
    }
}
