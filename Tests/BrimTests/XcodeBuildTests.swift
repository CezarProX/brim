import Foundation
import SwiftUI
import Testing

@testable import Brim

struct XcodeBuildDetectorTests {
  private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  private func entry(
    _ file: String = "A.xcactivitylog", title: String = "Build App", started: TimeInterval? = -30, stopped: TimeInterval? = nil,
    status: String? = nil, errors: Int = 0, warnings: Int = 0
  ) -> XcodeManifestEntry {
    XcodeManifestEntry(
      fileName: file, title: title, started: started.map { now.addingTimeInterval($0) },
      stopped: stopped.map { now.addingTimeInterval($0) }, status: status, errors: errors, warnings: warnings)
  }

  private func snapshot(
    modified: TimeInterval? = -1, entries: [XcodeManifestEntry] = [], running: Bool = false, log: String? = "A.xcactivitylog"
  ) -> XcodeLogSnapshot {
    XcodeLogSnapshot(
      project: "App", latestLog: log, latestLogModified: modified.map { now.addingTimeInterval($0) }, entries: entries,
      xcodebuildRunning: running)
  }

  @Test func aFreshlyWrittenLogMeansBuilding() {
    let status = XcodeBuildDetector.status(snapshot(entries: [entry()]), previous: .idle, now: now)
    guard case .building(let project, let since) = status else { Issue.record("expected building"); return }
    #expect(project == "App")
    #expect(since == now.addingTimeInterval(-30))
  }

  @Test func xcodebuildProcessAloneMeansBuildingEvenWithAQuietLog() {
    let status = XcodeBuildDetector.status(snapshot(modified: -60, running: true), previous: .idle, now: now)
    #expect(status.isBuilding)
  }

  @Test func aQuietLogWithNoProcessIsIdle() {
    #expect(XcodeBuildDetector.status(snapshot(modified: -60, entries: [entry(stopped: -55, status: "S")]), previous: .idle, now: now) == .idle)
    #expect(XcodeBuildDetector.status(snapshot(modified: nil, log: nil), previous: .idle, now: now) == .idle)
  }

  @Test func theManifestEndingTheBuildStopsTheBuildingState() {
    let done = entry(stopped: -1, status: "S")
    let status = XcodeBuildDetector.status(snapshot(modified: -1, entries: [done]), previous: .idle, now: now)
    #expect(!status.isBuilding)
  }

  @Test func buildingThenQuietReportsSuccessWithDuration() {
    let previous = XcodeBuildStatus.building(project: "App", since: now.addingTimeInterval(-40))
    let finished = entry(started: -40, stopped: -6, status: "S", warnings: 3)
    let status = XcodeBuildDetector.status(snapshot(modified: -6, entries: [finished]), previous: previous, now: now)
    #expect(status == .succeeded(project: "App", duration: 34, warnings: 3))
  }

  @Test func buildingThenQuietReportsFailureWithErrorCount() {
    let previous = XcodeBuildStatus.building(project: "App", since: now.addingTimeInterval(-10))
    let failed = entry(started: -10, stopped: -5, status: "E", errors: 2)
    #expect(XcodeBuildDetector.status(snapshot(modified: -5, entries: [failed]), previous: previous, now: now)
      == .failed(project: "App", duration: 5, errors: 2))
    let noCount = entry(started: -10, stopped: -5, status: "E")
    #expect(XcodeBuildDetector.status(snapshot(modified: -5, entries: [noCount]), previous: previous, now: now)
      == .failed(project: "App", duration: 5, errors: 1))
  }

  @Test func resultsExpireAndNonBuildTasksAreIgnored() {
    let result = XcodeBuildStatus.succeeded(project: "App", duration: 3, warnings: 0)
    let oldEntry = entry(started: -30, stopped: -20, status: "S")
    #expect(XcodeBuildDetector.status(snapshot(modified: -20, entries: [oldEntry]), previous: result, now: now) == .idle)
    let clean = entry(title: "Clean App", started: -9, stopped: -5, status: "S")
    let previous = XcodeBuildStatus.building(project: "App", since: now.addingTimeInterval(-9))
    #expect(XcodeBuildDetector.status(snapshot(modified: -5, entries: [clean]), previous: previous, now: now) == .idle)
  }

  @Test func continuingABuildKeepsItsStartTime() {
    let since = now.addingTimeInterval(-20)
    let previous = XcodeBuildStatus.building(project: "App", since: since)
    #expect(XcodeBuildDetector.status(snapshot(modified: -1, entries: []), previous: previous, now: now) == previous)
  }

  @Test func derivedDataFolderNamesLoseTheirHash() {
    #expect(XcodeBuildDetector.projectName(fromDerivedDataFolder: "Brim-bkxyzabcdefghijklmnopqrstuvwx") == "Brim")
    #expect(XcodeBuildDetector.projectName(fromDerivedDataFolder: "My-App-bkxyzabcdefghijklmnopqrstuvwx") == "My-App")
    #expect(XcodeBuildDetector.projectName(fromDerivedDataFolder: "Plain-Name") == "Plain-Name")
  }

  @Test func clockFormatting() {
    #expect(XcodeBuildDetector.clock(7.4) == "7s")
    #expect(XcodeBuildDetector.clock(65) == "1m 05s")
    #expect(XcodeBuildDetector.clock(-3) == "0s")
  }

  @Test func parsesAManifestShapedLikeXcodesAndToleratesGarbage() throws {
    let plist: [String: Any] = [
      "logFormatVersion": 11,
      "logs": [
        "U1": [
          "fileName": "U1.xcactivitylog", "title": "Build App", "timeStartedRecording": 100.0, "timeStoppedRecording": 142.5,
          "primaryObservable": ["highLevelStatus": "E", "totalNumberOfErrors": 3, "totalNumberOfWarnings": 1],
        ],
        "U2": ["fileName": "U2.xcactivitylog", "signature": "Clean App", "highLevelStatus": "S"],
      ],
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    let entries = XcodeBuildDetector.parseManifest(data).sorted { $0.fileName < $1.fileName }
    #expect(entries.count == 2)
    #expect(entries[0].status == "E" && entries[0].errors == 3 && entries[0].warnings == 1 && entries[0].duration == 42.5)
    #expect(entries[1].title == "Clean App" && !entries[1].isBuild && entries[1].started == nil)
    #expect(XcodeBuildDetector.parseManifest(Data("garbage".utf8)).isEmpty)
  }

  @Test func scannerReadsADerivedDataTree() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dd-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let logs = root.appendingPathComponent("Demo-bkxyzabcdefghijklmnopqrstuvwx/Logs/Build")
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    try Data("log".utf8).write(to: logs.appendingPathComponent("U1.xcactivitylog"))
    let plist: [String: Any] = ["logs": ["U1": ["fileName": "U1.xcactivitylog", "title": "Build Demo"]]]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: logs.appendingPathComponent("LogStoreManifest.plist"))
    let snapshot = try #require(XcodeLogScanner.snapshot(root: root, xcodebuildRunning: false))
    #expect(snapshot.project == "Demo" && snapshot.latestLog == "U1.xcactivitylog" && snapshot.entries.count == 1)
    #expect(XcodeBuildDetector.status(snapshot, previous: .idle, now: .now).isBuilding)
    #expect(XcodeLogScanner.snapshot(root: root.appendingPathComponent("missing"), xcodebuildRunning: false) == nil)
  }
}
