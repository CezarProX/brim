import AppKit
import Foundation
import Testing

@testable import Brim

struct ExtendedActivityTests {
  @Test func urgentActivitiesPrecedeBackgroundUtilities() {
    let state = IslandActivities(
      recording: true, call: false, music: true,
      additional: [.devices, .calendar, .focus])
    #expect(state.primary == .recording)
    #expect(state.secondary == .music)
    #expect(state.available.contains(.calendar))
    #expect(state.selected(.focus) == .focus)
  }

  @Test func duplicatesAndUnsupportedSelectionsDoNotCreateGhostActivities() {
    let state = IslandActivities(
      recording: false, call: false, music: false,
      additional: [.devices, .devices, .calendar])
    #expect(state.available == [.calendar, .devices])
    #expect(state.selected(.recording) == .calendar)
  }

  @Test func meetingLinksOnlyAcceptKnownHTTPSProviders() {
    #expect(MeetingLink.validated("https://meet.google.com/abc-defg-hij") != nil)
    #expect(MeetingLink.validated("https://company.zoom.us/j/123") != nil)
    #expect(MeetingLink.validated("https://zoom.us.evil.test/j/123") == nil)
    #expect(MeetingLink.validated("file:///etc/passwd") == nil)
    #expect(MeetingLink.validated("https://user:pass@zoom.us/j/123") == nil)
  }

  @Test func batteryPercentRejectsUnavailableAndInvalidValues() {
    #expect(DeviceBattery.percentage(current: 45, maximum: 50) == 90)
    #expect(DeviceBattery.percentage(current: -1, maximum: 100) == nil)
    #expect(DeviceBattery.percentage(current: 101, maximum: 100) == nil)
    #expect(DeviceBattery.percentage(current: 0, maximum: 0) == nil)
  }
}

@MainActor
struct FocusAndSharingTests {
  @Test func focusPausesAndResumesWithoutLosingRemainingTime() {
    let model = FocusTimerModel()
    defer { model.stop() }
    let now = Date(timeIntervalSince1970: 1000)
    model.start(minutes: 5, now: now)
    model.pause(now: now.addingTimeInterval(20))
    #expect(model.isPaused)
    #expect(model.remaining(at: now.addingTimeInterval(100)) == 280)
    model.resume(now: now.addingTimeInterval(100))
    #expect(model.remaining(at: now.addingTimeInterval(101)) == 279)
    model.tick(now: now.addingTimeInterval(380))
    #expect(model.completed)
    #expect(model.isActive)
    model.stop()
    #expect(!model.isActive)
  }

  @Test func contextArrivalPreservesDeliberateMusicSelection() {
    let presentation = NotchPresentation()
    presentation.updateActivities(IslandActivities(recording: false, call: false, music: true))
    presentation.selectedActivity = .music
    presentation.updateActivities(
      IslandActivities(recording: false, call: false, music: true, additional: [.calendar]))
    #expect(presentation.selectedActivity == .music)
    #expect(presentation.activities.selected(presentation.selectedActivity) == .music)
  }

  /// Folders can be sent with AirDrop too, so the Share app accepts them; duplicates and remote
  /// URLs are still dropped.
  @Test func sharingOnlyAcceptsReadableLocalFilesAndFolders() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("example.txt")
    try Data("Fixture".utf8).write(to: file)
    let model = SharingActivityModel()
    model.accept([file, file, directory, URL(string: "https://example.com/file")!])
    #expect(Set(model.files) == [file, directory])
    #expect(model.files.count == 2)
    model.clear()
    #expect(!model.isActive)
  }

  @Test func qrCodeCannotEncodeLocalFilesOrCredentialURLs() {
    #expect(SharingActivityModel.shareableLink("file:///tmp/test.txt") == nil)
    #expect(SharingActivityModel.shareableLink("https://user:pass@example.com") == nil)
    #expect(SharingActivityModel.qrCode(for: "https://example.com") != nil)
    #expect(SharingActivityModel.qrCode(for: "not a URL") == nil)
  }
}
