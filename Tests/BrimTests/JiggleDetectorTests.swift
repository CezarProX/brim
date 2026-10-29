import Foundation
import Testing

@testable import Brim

struct JiggleDetectorTests {
  @Test func quickSideToSideShakeTriggers() {
    var detector = JiggleDetector()
    let xs: [CGFloat] = [100, 160, 100, 160, 100, 160]
    var fired = false
    for (index, x) in xs.enumerated() {
      fired = detector.add(x: x, time: Double(index) * 0.08) || fired
    }
    #expect(fired)
  }

  @Test func slowOrSmallMovementDoesNot() {
    var small = JiggleDetector()
    var fired = false
    for (index, x) in [100, 103, 100, 103, 100, 103].enumerated() {
      fired = small.add(x: CGFloat(x), time: Double(index) * 0.08) || fired
    }
    #expect(!fired)

    var slow = JiggleDetector()
    fired = false
    for (index, x) in [100, 170, 100, 170, 100].enumerated() {
      fired = slow.add(x: CGFloat(x), time: Double(index) * 0.6) || fired
    }
    #expect(!fired)
  }

  @Test func straightDragDoesNot() {
    var detector = JiggleDetector()
    var fired = false
    for step in 0..<20 {
      fired = detector.add(x: CGFloat(step * 30), time: Double(step) * 0.03) || fired
    }
    #expect(!fired)
  }
}
