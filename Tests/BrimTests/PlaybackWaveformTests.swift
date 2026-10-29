import Foundation
import Testing
@testable import Brim

struct PlaybackWaveformTests {
    @Test func animationChangesOnlyBarHeightsWithinFixedBounds() {
        let size = CGSize(width: 23, height: 18)
        let first = WaveformDrawing.bars(in: size, count: 4, time: 0, playing: true, reduceMotion: false)
        for time in stride(from: 0.0, through: 8.0, by: 0.05) {
            let next = WaveformDrawing.bars(in: size, count: 4, time: time, playing: true, reduceMotion: false)
            #expect(next.count == first.count)
            for (old, rect) in zip(first, next) {
                #expect(rect.midX == old.midX)
                #expect(rect.midY == size.height / 2)
                #expect(CGRect(origin: .zero, size: size).contains(rect))
            }
        }
    }

    @Test func pausedAndReducedMotionAreTimeIndependent() {
        for reduced in [false, true] {
            let first = WaveformDrawing.bars(in: CGSize(width: 23, height: 18), count: 4, time: 0,
                                             playing: reduced, reduceMotion: reduced)
            let later = WaveformDrawing.bars(in: CGSize(width: 23, height: 18), count: 4, time: 42,
                                             playing: reduced, reduceMotion: reduced)
            #expect(first == later)
        }
    }
}
