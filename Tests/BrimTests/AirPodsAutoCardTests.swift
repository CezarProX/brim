import SwiftUI
import Testing

@testable import Brim

/// Holds the state so `#expect` can call it (the macro cannot take a mutating call).
private final class Card {
  var state = HUDAutoCard()
  var isAutoOpen: Bool { state.isAutoOpen }
  func update(flash: IslandFlash?, hovered: Bool, now: TimeInterval) -> Bool {
    state.update(flash: flash, hovered: hovered, now: now)
  }
}

@Suite("AirPods card opens on connect")
struct AirPodsAutoCardTests {
  private func flash(autoOpen: TimeInterval?) -> IslandFlash {
    IslandFlash(title: "AirPods Pro", symbol: "airpodspro", tint: .white, value: nil, until: .distantFuture,
                kind: .bluetooth, autoOpenCard: autoOpen)
  }

  @Test func opensByItselfThenCollapses() {
    let card = Card()
    let pods = flash(autoOpen: 3)
    #expect(card.update(flash: pods, hovered: false, now: 100))
    #expect(card.update(flash: pods, hovered: false, now: 102.9))
    #expect(!card.update(flash: pods, hovered: false, now: 103))
    #expect(!card.isAutoOpen)
    #expect(!card.update(flash: pods, hovered: false, now: 104), "stays a strip once collapsed")
  }

  @Test func hoverKeepsItOpenAndLeavingRestartsTheTimer() {
    let card = Card()
    let pods = flash(autoOpen: 3)
    _ = card.update(flash: pods, hovered: false, now: 0)
    #expect(card.update(flash: pods, hovered: true, now: 2))
    #expect(card.update(flash: pods, hovered: true, now: 10), "hover holds it past the timer")
    #expect(card.update(flash: pods, hovered: false, now: 11), "leaving restarts the countdown")
    #expect(card.update(flash: pods, hovered: false, now: 13.9))
    #expect(!card.update(flash: pods, hovered: false, now: 14))
  }

  @Test func plainFlashesOnlyOpenOnHover() {
    let card = Card()
    let volume = flash(autoOpen: nil)
    #expect(!card.update(flash: volume, hovered: false, now: 0))
    #expect(card.update(flash: volume, hovered: true, now: 1))
    #expect(!card.update(flash: volume, hovered: false, now: 1.1), "hover-only cards close on leave")
  }

  @Test func hoverAfterTheAutoPeriodBehavesLikeNormalHover() {
    let card = Card()
    let pods = flash(autoOpen: 3)
    _ = card.update(flash: pods, hovered: false, now: 0)
    _ = card.update(flash: pods, hovered: false, now: 5)
    #expect(card.update(flash: pods, hovered: true, now: 6))
    #expect(!card.update(flash: pods, hovered: false, now: 6.1))
  }

  @Test func aNewFlashStartsOverAndNoFlashShowsNothing() {
    let card = Card()
    _ = card.update(flash: flash(autoOpen: 3), hovered: false, now: 0)
    #expect(!card.update(flash: nil, hovered: true, now: 1))
    #expect(card.update(flash: flash(autoOpen: 3), hovered: false, now: 50), "the next connect opens again")
  }

  @MainActor @Test func connectPresentsAnAutoOpeningCard() throws {
    let center = IslandFlashCenter()
    let pods = AirPodsBatteries(name: "AirPods Pro", symbol: "airpodspro", left: 80, right: 75, caseLevel: 40,
                                model: .airPodsPro)
    AirPodsConnectCard.present(pods, name: "AirPods Pro", center: center)
    let shown = try #require(center.current)
    #expect(shown.airPods == pods)
    #expect(shown.autoOpenCard == AirPodsConnectCard.autoOpenDuration)
    #expect(shown.duration > AirPodsConnectCard.autoOpenDuration, "the strip still shows after the card folds")
    #expect(shown.detail == "Connected")
    center.dismiss()
  }
}
