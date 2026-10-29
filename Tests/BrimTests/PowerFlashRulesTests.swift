import Testing

@testable import Brim

struct PowerFlashRulesTests {
  typealias Reading = PowerFlashRules.Reading

  @Test func pluggingAndUnpluggingFlashOnce() {
    #expect(PowerFlashRules.flash(previous: nil, current: Reading(percent: 50, externalPower: true)) == nil)
    #expect(
      PowerFlashRules.flash(
        previous: Reading(percent: 50, externalPower: false), current: Reading(percent: 50, externalPower: true))
        == .charging(50))
    #expect(
      PowerFlashRules.flash(
        previous: Reading(percent: 80, externalPower: true), current: Reading(percent: 80, externalPower: false))
        == .unplugged(80))
    #expect(
      PowerFlashRules.flash(
        previous: Reading(percent: 80, externalPower: true), current: Reading(percent: 81, externalPower: true))
        == nil)
  }

  @Test func lowBatteryFlashesWhenCrossingEachThreshold() {
    #expect(
      PowerFlashRules.flash(
        previous: Reading(percent: 21, externalPower: false), current: Reading(percent: 20, externalPower: false))
        == .low(20))
    #expect(
      PowerFlashRules.flash(
        previous: Reading(percent: 20, externalPower: false), current: Reading(percent: 19, externalPower: false))
        == nil)
    #expect(
      PowerFlashRules.flash(
        previous: Reading(percent: 11, externalPower: false), current: Reading(percent: 10, externalPower: false))
        == .low(10))
  }
}
