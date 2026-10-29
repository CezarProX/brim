import CoreGraphics
import Testing

@testable import Brim

struct LiquidPopOutDragTests {
  private typealias Drag = LiquidPopOutDrag

  @Test func aShortDownwardPullStartsTheDrag() {
    #expect(Drag.shouldBegin(translation: CGSize(width: 2, height: 12), enabled: true))
    #expect(!Drag.shouldBegin(translation: CGSize(width: 2, height: 12), enabled: false))
    #expect(!Drag.shouldBegin(translation: CGSize(width: 30, height: 12), enabled: true), "sideways is a track swipe")
    #expect(!Drag.shouldBegin(translation: CGSize(width: 0, height: -20), enabled: true))
    #expect(!Drag.shouldBegin(translation: CGSize(width: 0, height: CGFloat.nan), enabled: true))
  }

  @Test func pullingFurtherGrowsFromPlayerToExpanded() {
    let player = LiquidPlayerPolicy.size(for: .player).height
    let expanded = LiquidPlayerPolicy.size(for: .expanded).height
    #expect(Drag.height(pull: 0) == player)
    #expect(Drag.height(pull: -50) == player)
    #expect(Drag.height(pull: 140) > player && Drag.height(pull: 140) < expanded)
    #expect(Drag.height(pull: 900) == expanded)
    #expect(Drag.height(pull: 100) < Drag.height(pull: 200))
  }

  @Test func theCardFadesAndScalesInOverTheFirstPoints() {
    #expect(Drag.progress(pull: 0) == 0)
    #expect(Drag.progress(pull: 20) > 0 && Drag.progress(pull: 20) < 1)
    #expect(Drag.progress(pull: 200) == 1)
  }

  @Test func releaseCommitsWhenPulledFarOrFlicked() {
    #expect(Drag.commits(pull: 70, velocity: 0))
    #expect(!Drag.commits(pull: 30, velocity: 0), "a small pull goes back to the notch")
    #expect(Drag.commits(pull: 30, velocity: 900), "a quick flick down still pops out")
    #expect(!Drag.commits(pull: 10, velocity: 900))
  }

  @Test func settlesOnTheNearestSizeAfterTheFlick() {
    #expect(Drag.settledSize(height: LiquidPlayerPolicy.size(for: .player).height + 20, velocity: 0) == .player)
    #expect(Drag.settledSize(height: 420, velocity: 0) == .expanded)
    #expect(Drag.settledSize(height: 300, velocity: 1500) == .expanded, "a fast pull keeps growing")
    #expect(Drag.settledSize(height: 60, velocity: 0) == .player, "never collapses to Mini on the way out")
  }

  @Test func theCardHangsFromThePointer() {
    let topLeft = Drag.topLeft(pointer: CGPoint(x: 500, y: 800), width: 340)
    #expect(topLeft.x == 330)
    #expect(topLeft.y > 800, "the pointer holds the card near its top edge")
  }
}
