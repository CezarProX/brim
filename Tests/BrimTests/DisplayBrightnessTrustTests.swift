import Testing

@testable import Brim

/// On some macOS builds DisplayServices answers "success" but never touches the panel (it reads 1.0
/// while IOKit reports the real level). The brightness keys must then go to macOS, not be swallowed.
struct DisplayBrightnessTrustTests {
  @Test func apiThatDisagreesWithThePanelIsNotTrusted() {
    #expect(!DisplayBrightnessControl.isTrustworthy(api: 1.0, panel: 0.5))
  }

  @Test func apiThatMatchesThePanelIsTrusted() {
    #expect(DisplayBrightnessControl.isTrustworthy(api: 0.62, panel: 0.625))
  }

  /// Measured on this Mac (macOS 27): DisplayServices reads 0.625 while IOKit's backlight value reads
  /// 0.5 — two different scales of a working panel — and a set moved DisplayServices to the target.
  /// Only the stuck-at-full failure means "not trusted".
  @Test func aWorkingApiOnADifferentScaleIsTrusted() {
    #expect(DisplayBrightnessControl.isTrustworthy(api: 0.625, panel: 0.5))
    #expect(DisplayBrightnessControl.isTrustworthy(api: 0.2, panel: 0.35))
    #expect(DisplayBrightnessControl.isTrustworthy(api: 1.0, panel: 0.97))
  }

  @Test func withoutAPanelReadingTheAPIIsTrusted() {
    #expect(DisplayBrightnessControl.isTrustworthy(api: 0.4, panel: nil))
  }

  @Test func panelReadingIsNormalisedFromTheRegistryRange() {
    #expect(DisplayBrightnessControl.panelFraction(value: 32768, min: 0, max: 65536) == 0.5)
    #expect(DisplayBrightnessControl.panelFraction(value: 5, min: 0, max: 0) == nil)
  }
}
