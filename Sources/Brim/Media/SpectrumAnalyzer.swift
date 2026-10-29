import Accelerate
import Foundation

/// Turns a block of mono samples into a handful of log-spaced band levels (0...1).
/// Not thread-safe: use one instance per audio callback queue.
final class SpectrumAnalyzer {
  static let size = 1024
  private let log2n = vDSP_Length(10)
  private let setup: FFTSetup
  private var window = [Float](repeating: 0, count: SpectrumAnalyzer.size)
  private var real = [Float](repeating: 0, count: SpectrumAnalyzer.size / 2)
  private var imag = [Float](repeating: 0, count: SpectrumAnalyzer.size / 2)
  private var windowed = [Float](repeating: 0, count: SpectrumAnalyzer.size)

  init?() {
    guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
    self.setup = setup
    vDSP_hann_window(&window, vDSP_Length(Self.size), Int32(vDSP_HANN_NORM))
  }

  deinit { vDSP_destroy_fftsetup(setup) }

  /// `bars` band levels from the newest `size` samples; silence or bad input yields zeros.
  func levels(samples: UnsafeBufferPointer<Float>, sampleRate: Float, bars: Int) -> [Float] {
    guard bars > 0 else { return [] }
    let zeros = [Float](repeating: 0, count: bars)
    guard sampleRate.isFinite, sampleRate > 8_000, !samples.isEmpty else { return zeros }
    let n = Self.size
    let tail = samples.count >= n ? samples.suffix(n) : samples[...]
    for i in 0..<n { windowed[i] = 0 }
    var index = 0
    for sample in tail { windowed[index] = sample.isFinite ? sample : 0; index += 1 }
    vDSP_vmul(windowed, 1, window, 1, &windowed, 1, vDSP_Length(n))

    var magnitudes = [Float](repeating: 0, count: n / 2)
    real.withUnsafeMutableBufferPointer { rp in
      imag.withUnsafeMutableBufferPointer { ip in
        var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
        windowed.withUnsafeBufferPointer { buffer in
          buffer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
          }
        }
        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
        vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(n / 2))
      }
    }
    // zrip output is scaled by 2; bring it to roughly sample amplitude.
    var scale = Float(1) / Float(n)
    vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(n / 2))
    return Self.bands(magnitudes: magnitudes, sampleRate: sampleRate, bars: bars)
  }

  /// Log-spaced bands from ~70 Hz to ~12 kHz; each is the peak magnitude in its range.
  static func bands(magnitudes: [Float], sampleRate: Float, bars: Int) -> [Float] {
    let binWidth = sampleRate / Float(size)
    let low: Float = 70, high = min(12_000, sampleRate / 2 - binWidth)
    guard high > low, bars > 0 else { return [Float](repeating: 0, count: max(0, bars)) }
    return (0..<bars).map { band in
      let start = low * powf(high / low, Float(band) / Float(bars))
      let end = low * powf(high / low, Float(band + 1) / Float(bars))
      let first = max(1, Int(start / binWidth))
      let last = min(magnitudes.count - 1, max(first, Int(end / binWidth)))
      let peak = magnitudes[first...last].max() ?? 0
      // Higher bands carry less energy in music; tilt so all bars move.
      let tilt = 1 + Float(band) * 0.5
      return VisualizerMath.normalize(peak * tilt * tilt, floor: 0.0004, ceiling: 0.08)
    }
  }
}
