import Foundation
import Testing

@testable import Brim

struct RingGeometryTests {
  @Test func firstItemSitsAtTwelveOClockAndGoesClockwise() {
    let top = RingGeometry.offset(index: 0, count: 8, radius: 100)
    #expect(abs(top.width) < 0.001 && abs(top.height + 100) < 0.001)
    let right = RingGeometry.offset(index: 2, count: 8, radius: 100)
    #expect(abs(right.width - 100) < 0.001 && abs(right.height) < 0.001)
  }
}
