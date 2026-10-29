import Foundation
import ScreenCaptureKit
import Testing
@testable import Brim

struct CapturePermissionTests {
    @Test func onlyScreenCaptureKitDenialRequiresPermissionRecovery() {
        let denied = NSError(domain: SCStreamErrorDomain, code: -3801)
        let captureFailure = NSError(domain: SCStreamErrorDomain, code: -3802)
        let unrelated = NSError(domain: NSCocoaErrorDomain, code: -3801)

        if case .permissionDenied = ScreenCapturer.classifyCaptureError(denied) {} else {
            Issue.record("ScreenCaptureKit denial must offer permission recovery")
        }
        for error in [captureFailure, unrelated] {
            if case .captureFailed = ScreenCapturer.classifyCaptureError(error) {} else {
                Issue.record("Other failures must not be reported as missing permission")
            }
        }
    }
}
