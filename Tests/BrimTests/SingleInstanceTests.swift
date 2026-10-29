import Foundation
import Testing

@testable import Brim

struct SingleInstanceTests {
  @Test func findsOtherCopiesOfTheSameApp() {
    let running: [(pid: pid_t, bundleID: String?)] = [
      (10, "io.github.cezarprox.brim"), (11, "io.github.cezarprox.brim"), (12, "com.example.otherapp"), (13, nil),
    ]
    #expect(SingleInstance.otherInstances(bundleID: "io.github.cezarprox.brim", ownPID: 11, running: running) == [10])
  }

  @Test func withoutABundleIDNothingIsTerminated() {
    #expect(SingleInstance.otherInstances(bundleID: nil, ownPID: 1, running: [(2, nil)]).isEmpty)
  }
}
