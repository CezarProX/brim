// CursorSmoothing.swift
// Brim
//
// Turns the jittery, irregular pointer log into the calm path the editor draws. The track is
// resampled on a uniform grid and filtered with a centred Gaussian, so the smoothed pointer has
// no lag and still lands where the user clicked when they paused to click.

import CoreGraphics
import Foundation

struct SmoothedCursorPath: Sendable {
    static let rate: Double = 120

    private let xs: [Double]
    private let ys: [Double]
    private let start: Double

    /// `smoothing` 0 keeps the raw path; 1 is very soft (sigma ~ 0.15 s).
    init(track: CursorTrack, smoothing: Double) {
        guard let first = track.samples.first, let last = track.samples.last else {
            xs = []; ys = []; start = 0
            return
        }
        start = first.t
        let count = max(1, Int(((last.t - first.t) * Self.rate).rounded(.up)) + 1)
        var rawX = [Double](repeating: 0, count: count)
        var rawY = [Double](repeating: 0, count: count)
        for i in 0..<count {
            let p = track.position(at: first.t + Double(i) / Self.rate) ?? .zero
            rawX[i] = p.x
            rawY[i] = p.y
        }
        let sigma = max(0, min(1, smoothing)) * 0.15 * Self.rate
        xs = Self.gaussian(rawX, sigma: sigma)
        ys = Self.gaussian(rawY, sigma: sigma)
    }

    var isEmpty: Bool { xs.isEmpty }

    func position(at t: Double) -> CGPoint? {
        guard !xs.isEmpty else { return nil }
        let f = (t - start) * Self.rate
        if f <= 0 { return CGPoint(x: xs[0], y: ys[0]) }
        let last = xs.count - 1
        if f >= Double(last) { return CGPoint(x: xs[last], y: ys[last]) }
        let i = Int(f), frac = f - Double(i)
        return CGPoint(x: xs[i] + (xs[i + 1] - xs[i]) * frac, y: ys[i] + (ys[i + 1] - ys[i]) * frac)
    }

    /// Separable Gaussian with clamped edges. Sigma is in samples.
    static func gaussian(_ values: [Double], sigma: Double) -> [Double] {
        guard sigma >= 0.5, values.count > 1 else { return values }
        let radius = Int((sigma * 3).rounded(.up))
        var kernel = (-radius...radius).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        let sum = kernel.reduce(0, +)
        kernel = kernel.map { $0 / sum }
        let last = values.count - 1
        return values.indices.map { i in
            var acc = 0.0
            for (k, weight) in kernel.enumerated() {
                let j = min(last, max(0, i + k - radius))
                acc += values[j] * weight
            }
            return acc
        }
    }
}

/// When the redrawn pointer should be visible: it fades out after resting a while and fades back
/// in just before it next moves (the editor knows the future, so it never pops in late).
struct CursorVisibility: Sendable {
    var idleDelay: Double = 1.6
    var fadeOut: Double = 0.35
    var fadeIn: Double = 0.18
    private let activity: [Double]

    init(track: CursorTrack, idleDelay: Double = 1.6) {
        self.idleDelay = idleDelay
        activity = track.activityTimes()
    }

    func opacity(at t: Double) -> Double {
        guard !activity.isEmpty else { return 1 }
        let index = Self.upperBound(activity, t)
        let previous = index > 0 ? activity[index - 1] : nil
        let next = index < activity.count ? activity[index] : nil
        var visible = 0.0
        if let previous {
            let rest = t - previous
            visible = rest <= idleDelay ? 1 : max(0, 1 - (rest - idleDelay) / fadeOut)
        } else {
            // Before the first movement: shown until it has rested for `idleDelay` from zero.
            visible = t <= idleDelay ? 1 : max(0, 1 - (t - idleDelay) / fadeOut)
        }
        if let next, next - t < fadeIn { visible = max(visible, 1 - (next - t) / fadeIn) }
        return min(1, max(0, visible))
    }

    private static func upperBound(_ values: [Double], _ t: Double) -> Int {
        var low = 0, high = values.count
        while low < high {
            let mid = (low + high) / 2
            if values[mid] <= t { low = mid + 1 } else { high = mid }
        }
        return low
    }
}

/// The look of a click: the pointer dips while pressed and a ring spreads from the click point.
enum ClickEffect {
    static let rippleDuration: Double = 0.55
    static let pressedScale: Double = 0.82

    /// Pointer scale at `t` given the clicks (1 when nothing is pressed).
    static func pointerScale(at t: Double, clicks: [CursorClick]) -> Double {
        var scale = 1.0
        for click in clicks where t >= click.t - 0.08 {
            let release = max(click.up ?? click.t + 0.12, click.t + 0.1)
            guard t <= release + 0.12 else { continue }
            let pressIn = min(1, max(0, (t - (click.t - 0.08)) / 0.08))
            let pressOut = t > release ? max(0, 1 - (t - release) / 0.12) : 1
            scale = min(scale, 1 - (1 - pressedScale) * min(pressIn, pressOut))
        }
        return scale
    }

    /// Active ripples at `t`: (click, progress 0...1).
    static func ripples(at t: Double, clicks: [CursorClick]) -> [(CursorClick, Double)] {
        clicks.compactMap { click in
            let progress = (t - click.t) / rippleDuration
            return progress >= 0 && progress <= 1 ? (click, progress) : nil
        }
    }
}
