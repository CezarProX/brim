import Foundation
import Testing

@testable import Brim

struct SpectrumAnalyzerTests {
  private func sine(_ frequency: Float, rate: Float = 48_000, count: Int = 1024, amplitude: Float = 0.5) -> [Float] {
    (0..<count).map { amplitude * sinf(2 * .pi * frequency * Float($0) / rate) }
  }

  @Test func silenceGivesZeroBars() throws {
    let analyzer = try #require(SpectrumAnalyzer())
    let bars = [Float](repeating: 0, count: 1024).withUnsafeBufferPointer {
      analyzer.levels(samples: $0, sampleRate: 48_000, bars: 5)
    }
    #expect(bars == [0, 0, 0, 0, 0])
  }

  @Test func toneLightsTheMatchingBandMost() throws {
    let analyzer = try #require(SpectrumAnalyzer())
    func peakBar(_ hz: Float) -> Int {
      let samples = sine(hz)
      let bars = samples.withUnsafeBufferPointer { analyzer.levels(samples: $0, sampleRate: 48_000, bars: 5) }
      return bars.firstIndex(of: bars.max() ?? 0) ?? -1
    }
    #expect(peakBar(120) < peakBar(1_000))
    #expect(peakBar(1_000) < peakBar(9_000))
  }

  @Test func levelsStayInUnitRangeAndHandleBadInput() throws {
    let analyzer = try #require(SpectrumAnalyzer())
    var loud = sine(440, amplitude: 4)
    loud[10] = .nan
    let bars = loud.withUnsafeBufferPointer { analyzer.levels(samples: $0, sampleRate: 48_000, bars: 6) }
    #expect(bars.count == 6)
    #expect(bars.allSatisfy { $0 >= 0 && $0 <= 1 })
    let none = analyzer.levels(samples: UnsafeBufferPointer(start: nil, count: 0), sampleRate: 48_000, bars: 4)
    #expect(none == [0, 0, 0, 0])
    let badRate = loud.withUnsafeBufferPointer { analyzer.levels(samples: $0, sampleRate: 0, bars: 4) }
    #expect(badRate == [0, 0, 0, 0])
  }

  @Test func shortBuffersAreZeroPadded() throws {
    let analyzer = try #require(SpectrumAnalyzer())
    let short = sine(1_000, count: 200)
    let bars = short.withUnsafeBufferPointer { analyzer.levels(samples: $0, sampleRate: 48_000, bars: 5) }
    #expect(bars.max() ?? 0 > 0)
  }
}
