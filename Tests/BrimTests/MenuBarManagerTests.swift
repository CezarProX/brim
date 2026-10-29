import Foundation
import Testing

@testable import Brim

@Suite struct HiddenBarPolicyTests {
  @Test func collapsedSeparatorIsWiderThanAnyDisplayButBounded() {
    let normal = HiddenBarPolicy.separatorLength(collapsed: true, widestScreen: 1512)
    let ultrawide = HiddenBarPolicy.separatorLength(collapsed: true, widestScreen: 6016)
    #expect(normal > 1512)
    #expect(ultrawide > 6016)
    #expect(HiddenBarPolicy.separatorLength(collapsed: true, widestScreen: 100_000) == HiddenBarPolicy.maxCollapsedLength)
    #expect(HiddenBarPolicy.separatorLength(collapsed: false, widestScreen: 1512) == HiddenBarPolicy.expandedLength)
  }

  @Test func neverCollapsesUnlessSeparatorIsLeftOfTheToggle() {
    #expect(HiddenBarPolicy.canCollapse(separatorMinX: 900, toggleMinX: 1000))
    #expect(!HiddenBarPolicy.canCollapse(separatorMinX: 1100, toggleMinX: 1000))
    #expect(!HiddenBarPolicy.canCollapse(separatorMinX: nil, toggleMinX: 1000))
    #expect(!HiddenBarPolicy.canCollapse(separatorMinX: 900, toggleMinX: nil))
  }

  @Test func autoRehideWaitsForTheDelayAndHonoursTheSetting() {
    let start = Date(timeIntervalSince1970: 1000)
    #expect(!HiddenBarPolicy.shouldAutoCollapse(expandedAt: start, now: start.addingTimeInterval(9), delay: 10, enabled: true))
    #expect(HiddenBarPolicy.shouldAutoCollapse(expandedAt: start, now: start.addingTimeInterval(10), delay: 10, enabled: true))
    #expect(!HiddenBarPolicy.shouldAutoCollapse(expandedAt: start, now: start.addingTimeInterval(99), delay: 10, enabled: false))
    #expect(!HiddenBarPolicy.shouldAutoCollapse(expandedAt: nil, now: start, delay: 10, enabled: true))
  }

  @Test func everyToolIsOffByDefault() {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "QS-Tools-\(UUID().uuidString)")!)
    #expect(!settings.menuBarManagerEnabled)
    #expect(!settings.thunderstormEnabled)
    #expect(!settings.cleanerEnabled)
    #expect(settings.menuBarManagerRehideSeconds == 10)
    settings.menuBarManagerRehideSeconds = 1
    #expect(settings.menuBarManagerRehideSeconds == 2)
  }
}
