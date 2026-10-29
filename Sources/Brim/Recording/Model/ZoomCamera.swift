// ZoomCamera.swift
// Brim
//
// The virtual camera over the recording. Targets come from the zoom segments (scale + focus);
// a critically damped spring, simulated once over the whole recording, turns them into the smooth
// push-in / pull-out motion. Precomputing makes scrubbing deterministic: any frame can be asked for
// in any order and gets the same camera.

import CoreGraphics
import Foundation

struct CameraState: Equatable, Sendable {
    var scale: Double
    /// Centre of the visible region, normalised source coordinates (top-left origin).
    var center: CGPoint

    static let identity = CameraState(scale: 1, center: CGPoint(x: 0.5, y: 0.5))

    /// The part of the source that is visible, normalised (top-left origin).
    var visibleRect: CGRect {
        let size = 1 / max(1, scale)
        return CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
    }

    /// Keeps the visible region inside the frame so no edge ever shows.
    static func clampedCenter(_ center: CGPoint, scale: Double) -> CGPoint {
        let half = 0.5 / max(1, scale)
        return CGPoint(x: min(max(center.x, half), 1 - half), y: min(max(center.y, half), 1 - half))
    }
}

struct ZoomCameraPath: Sendable {
    static let rate: Double = 120
    /// Spring angular frequency; ~0.7 s to settle, the Screen Studio feel.
    static let omega: Double = 7.5
    /// While following, the camera only re-aims once the pointer leaves this share of the view.
    static let deadZone: Double = 0.55

    private let scales: [Double]
    private let xs: [Double]
    private let ys: [Double]

    init(segments: [ZoomSegment], duration: Double, cursor: (Double) -> CGPoint?) {
        let sorted = segments.sorted { $0.start < $1.start }
        let count = max(1, Int((max(0, duration) * Self.rate).rounded(.up)) + 1)
        var scales = [Double](repeating: 1, count: count)
        var xs = [Double](repeating: 0.5, count: count)
        var ys = [Double](repeating: 0.5, count: count)
        var scale = 1.0, vScale = 0.0
        var cx = 0.5, cy = 0.5, vx = 0.0, vy = 0.0
        var aimX = 0.5, aimY = 0.5
        var activeID: UUID?
        let dt = 1 / Self.rate, w = Self.omega
        for i in 0..<count {
            let t = Double(i) * dt
            let segment = sorted.last { $0.contains(t) }
            var targetScale = 1.0
            if let segment {
                targetScale = min(max(segment.scale, 1), ZoomSegment.scaleRange.upperBound)
                switch segment.focus {
                case .fixed(let x, let y):
                    aimX = x; aimY = y
                case .cursor:
                    let pointer = cursor(t) ?? CGPoint(x: aimX, y: aimY)
                    if activeID != segment.id {
                        aimX = pointer.x; aimY = pointer.y
                    } else {
                        let reach = Self.deadZone * 0.5 / targetScale
                        if abs(pointer.x - aimX) > reach { aimX = pointer.x - (pointer.x > aimX ? reach : -reach) }
                        if abs(pointer.y - aimY) > reach { aimY = pointer.y - (pointer.y > aimY ? reach : -reach) }
                    }
                }
            }
            let jump = (segment?.instant ?? false) || (segment == nil && sorted.last { $0.contains(t - dt) }?.instant == true)
            activeID = segment?.id
            let clamped = CameraState.clampedCenter(CGPoint(x: aimX, y: aimY), scale: targetScale)
            if jump || i == 0 {
                scale = targetScale; vScale = 0
                if segment != nil || i == 0 { cx = clamped.x; cy = clamped.y }
                vx = 0; vy = 0
            } else {
                Self.step(&scale, &vScale, target: targetScale, w: w, dt: dt)
                if segment != nil {
                    Self.step(&cx, &vx, target: clamped.x, w: w, dt: dt)
                    Self.step(&cy, &vy, target: clamped.y, w: w, dt: dt)
                }
            }
            scales[i] = scale; xs[i] = cx; ys[i] = cy
        }
        self.scales = scales
        self.xs = xs
        self.ys = ys
    }

    /// Exact critically damped spring step (stable at any dt).
    private static func step(_ x: inout Double, _ v: inout Double, target: Double, w: Double, dt: Double) {
        let offset = x - target
        let e = exp(-w * dt)
        let next = (offset + (v + w * offset) * dt) * e
        v = (v - (v + w * offset) * w * dt) * e
        x = target + next
    }

    func state(at t: Double) -> CameraState {
        let f = max(0, t) * Self.rate
        let last = scales.count - 1
        let i = min(Int(f), last), j = min(i + 1, last)
        let frac = min(1, f - Double(i))
        let scale = max(1, scales[i] + (scales[j] - scales[i]) * frac)
        let center = CGPoint(x: xs[i] + (xs[j] - xs[i]) * frac, y: ys[i] + (ys[j] - ys[i]) * frac)
        return CameraState(scale: scale, center: CameraState.clampedCenter(center, scale: scale))
    }
}
