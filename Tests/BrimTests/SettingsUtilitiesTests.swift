import Foundation
import Testing
import UserNotifications

@testable import Brim

@Suite struct SettingsTransferTests {
  private func suite() -> (UserDefaults, String) {
    let name = "transfer.\(UUID().uuidString)"
    return (UserDefaults(suiteName: name)!, name)
  }

  @Test func roundTripKeepsTypesAndExcludesBlockedKeys() throws {
    let (source, sourceName) = suite()
    defer { source.removePersistentDomain(forName: sourceName) }
    let when = Date(timeIntervalSince1970: 1_700_000_000)
    source.set(true, forKey: "shellHaptics")
    source.set(7, forKey: "shellOpenDelay")
    source.set(0.35, forKey: "hudScale")
    source.set("liquid", forKey: "lockLook")
    source.set(["a", "b"], forKey: "hiddenApps")
    source.set(Data([1, 2, 3]), forKey: "blob")
    source.set(when, forKey: "stamp")
    source.set(["x": 1, "y": ["z": true]], forKey: "nested")
    source.set("hunter2", forKey: "uploadApiToken")
    source.set("abc", forKey: "someSecret")
    source.set(Data(repeating: 0, count: 200_000), forKey: "artworkBlob")
    source.set("cached", forKey: "lyricsCacheIndex")
    source.set(true, forKey: "NSWindow Frame foo")
    source.set(true, forKey: "onboardingCompleted")

    let data = try SettingsTransfer.export(domain: source.persistentDomain(forName: sourceName) ?? [:], appVersion: "1.0")
    let (target, targetName) = suite()
    defer { target.removePersistentDomain(forName: targetName) }
    let result = try SettingsTransfer.importSettings(data, into: target)

    #expect(target.bool(forKey: "shellHaptics") == true)
    #expect(target.integer(forKey: "shellOpenDelay") == 7)
    #expect(target.double(forKey: "hudScale") == 0.35)
    #expect(target.string(forKey: "lockLook") == "liquid")
    #expect(target.stringArray(forKey: "hiddenApps") == ["a", "b"])
    #expect(target.data(forKey: "blob") == Data([1, 2, 3]))
    #expect((target.object(forKey: "stamp") as? Date) == when)
    let nested = target.dictionary(forKey: "nested")
    #expect((nested?["x"] as? Int) == 1)
    #expect((nested?["y"] as? [String: Any])?["z"] as? Bool == true)
    for blocked in ["uploadApiToken", "someSecret", "artworkBlob", "lyricsCacheIndex", "NSWindow Frame foo", "onboardingCompleted"] {
      #expect(target.object(forKey: blocked) == nil, "\(blocked) must not be exported")
    }
    #expect(result.applied == 8)
    #expect(result.skipped.isEmpty)
  }

  @Test func importRejectsBlockedKeysSmuggledIntoAHandEditedFile() throws {
    let json = #"{"format":"BrimSettings","version":1,"values":{"shellHaptics":true,"apiToken":"x","onboardingCompleted":true}}"#
    let (target, name) = suite()
    defer { target.removePersistentDomain(forName: name) }
    let result = try SettingsTransfer.importSettings(Data(json.utf8), into: target)
    #expect(result.applied == 1)
    #expect(Set(result.skipped) == ["apiToken", "onboardingCompleted"])
    #expect(target.object(forKey: "apiToken") == nil)
  }

  @Test func importAcceptsFilesExportedBeforeTheRename() throws {
    let json = #"{"format":"QuickShotSettings","version":1,"values":{"shellHaptics":true}}"#
    let (target, name) = suite()
    defer { target.removePersistentDomain(forName: name) }
    #expect(try SettingsTransfer.importSettings(Data(json.utf8), into: target).applied == 1)
  }

  @Test func importRejectsForeignAndNewerFiles() {
    let (target, name) = suite()
    defer { target.removePersistentDomain(forName: name) }
    #expect(throws: SettingsTransfer.TransferError.notSettingsFile) {
      try SettingsTransfer.importSettings(Data(#"{"hello":"world"}"#.utf8), into: target)
    }
    #expect(throws: SettingsTransfer.TransferError.unreadable) {
      try SettingsTransfer.importSettings(Data("nope".utf8), into: target)
    }
    #expect(throws: SettingsTransfer.TransferError.newerVersion(9)) {
      try SettingsTransfer.importSettings(Data(#"{"format":"BrimSettings","version":9,"values":{}}"#.utf8), into: target)
    }
  }

  @Test func exportIsDeterministicallyShapedJSON() throws {
    let data = try SettingsTransfer.export(domain: ["a": 1], appVersion: "2.0", now: Date(timeIntervalSince1970: 0))
    let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(root["format"] as? String == "BrimSettings")
    #expect(root["appVersion"] as? String == "2.0")
    #expect(root["exportedAt"] as? String == "1970-01-01T00:00:00Z")
  }
}

@Suite struct SettingsSearchLexiconTests {
  private let panes = SettingsPane.allCases.map(\.rawValue)

  private func hits(_ query: String) -> [String] { SettingsSearchLexicon.matches(query, in: panes) }

  @Test func emptyQueryKeepsEverything() {
    #expect(hits("") == panes)
    #expect(hits("   ") == panes)
  }

  @Test func titleAndKeywordMatches() {
    #expect(hits("clipboard").contains("Clipboard & Tray"))
    #expect(hits("volume").contains("HUDs & Live Activities"))
    #expect(hits("lyrics") == ["Music"])
    #expect(hits("cpu").contains("Home & Widgets"))
    #expect(hits("launch").contains("General"))
  }

  @Test func synonymsReachTechnicalPanes() {
    #expect(hits("dark").contains("Island"))
    #expect(hits("backup").contains("About"))
    #expect(hits("tour").contains("About"))
    #expect(hits("song").contains("Music"))
    #expect(hits("screenshot").contains("Shortcuts"))
  }

  @Test func everyWordMustMatch() {
    #expect(hits("command center").contains("General"))
    #expect(hits("volume banana").isEmpty)
  }

  @Test func matchingIgnoresCase() {
    #expect(hits("HUD") == hits("hud"))
    #expect(!hits("HUD").isEmpty)
  }

  @Test func lexiconOnlyDescribesRealPaneTitles() {
    let known = Set(SettingsPane.allCases.map(\.rawValue))
    #expect(Set(SettingsSearchLexicon.keywords.keys).isSubset(of: known))
  }

  @Test func everyPaneHasSearchKeywords() {
    for pane in SettingsPane.allCases {
      #expect(!(SettingsSearchLexicon.keywords[pane.rawValue] ?? []).isEmpty, "\(pane.rawValue) has no keywords")
    }
  }

  @Test func newPanesAreFoundByTheirFeatures() {
    let all = SettingsPane.allCases.map(\.rawValue)
    let find = { (query: String) in SettingsSearchLexicon.matches(query, in: all) }
    #expect(find("obsidian").contains("Home & Widgets"))
    #expect(find("pomodoro").contains("Home & Widgets"))
    #expect(find("teleprompter").contains("Home & Widgets"))
    #expect(find("terminal").contains("Home & Widgets"))
    #expect(find("ocr").contains("Home & Widgets"))
    #expect(find("preferred devices").contains("Home & Widgets"))
    #expect(find("airpods") == ["HUDs & Live Activities"])
    #expect(find("discord") == ["Music"])
    #expect(find("edge sliders") == ["Lock Screen"])
    #expect(find("weather").contains("Home & Widgets"))
  }

  @Test func searchListsTheMatchingWidgetsAndTools() {
    #expect(SettingsSearchLexicon.matchingTools("weather") == [.weather])
    #expect(SettingsSearchLexicon.matchingTools("obsidian") == [.notes])
    #expect(SettingsSearchLexicon.matchingTools("") == [])
  }

  @Test func everyToolHasAPlaceInSettings() {
    #expect(Set(SettingsTool.widgets + SettingsTool.tools) == Set(SettingsTool.allCases))
    let destination = SettingsDestination.tool(.weather, anchor: "weather.city")
    #expect(destination.pane == .widgets && destination.tool == .weather)
  }
}

@Suite struct PermissionStateTests {
  @Test func automationStatusMapping() {
    #expect(PermissionState.fromAutomation(status: 0) == .granted)
    #expect(PermissionState.fromAutomation(status: -1743) == .notGranted)
    #expect(PermissionState.fromAutomation(status: -1744) == .unknown)
    #expect(PermissionState.fromAutomation(status: -600) == .unknown)
  }

  @Test func notificationStatusMapping() {
    #expect(PermissionState.fromNotification(.authorized) == .granted)
    #expect(PermissionState.fromNotification(.denied) == .notGranted)
    #expect(PermissionState.fromNotification(.notDetermined) == .unknown)
  }

  @Test func everyPermissionOpensASystemSettingsPane() {
    for kind in PermissionKind.allCases {
      #expect(kind.settingsURL.scheme == "x-apple.systempreferences")
    }
  }

  @Test func tourCoversEveryPageWithCopy() {
    #expect(OnboardingPage.allCases.count >= 8 && OnboardingPage.allCases.count <= 15)
    for page in OnboardingPage.allCases { #expect(!page.title.isEmpty && !page.subtitle.isEmpty) }
  }
}
