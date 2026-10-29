import Testing

@testable import Brim

struct UploadConsentTests {
  @Test func theFirstUploadToAHostAsksAndLaterOnesDoNot() {
    #expect(UploadConsent.hostNeedingConsent(serviceURL: "https://0x0.st", acknowledged: nil) == "0x0.st")
    #expect(UploadConsent.hostNeedingConsent(serviceURL: "https://0x0.st", acknowledged: "0x0.st") == nil)
  }

  @Test func changingTheServiceAsksAgain() {
    #expect(UploadConsent.hostNeedingConsent(serviceURL: "https://files.example.com/up", acknowledged: "0x0.st")
      == "files.example.com")
  }

  @Test func aURLWithoutAHostIsLeftToTheUploader() {
    #expect(UploadConsent.hostNeedingConsent(serviceURL: "not a url", acknowledged: nil) == nil)
  }
}
