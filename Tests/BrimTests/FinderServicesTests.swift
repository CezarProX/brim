import AppKit
import Foundation
import Testing

@testable import Brim

struct FinderServicesTests {
  @Test func readsFileURLsOnceAndIgnoresWebLinks() throws {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("qs-services-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    let a = URL(fileURLWithPath: "/tmp/a.txt")
    let b = URL(fileURLWithPath: "/tmp/b.png")
    pasteboard.clearContents()
    pasteboard.writeObjects([a as NSURL, b as NSURL, a as NSURL, URL(string: "https://example.com")! as NSURL])
    let urls = FinderServicesProvider.fileURLs(from: pasteboard)
    #expect(urls.map(\.lastPathComponent) == ["a.txt", "b.png"])
  }

  @Test func emptyPasteboardGivesNoFiles() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("qs-services-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    pasteboard.clearContents()
    pasteboard.setString("hello", forType: .string)
    #expect(FinderServicesProvider.fileURLs(from: pasteboard).isEmpty)
  }

  @Test func infoPlistDeclaresBothServicesWithMatchingHandlers() throws {
    var root = URL(fileURLWithPath: #filePath)
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) { root.deleteLastPathComponent() }
    let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
    let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    let services = try #require(plist["NSServices"] as? [[String: Any]])
    let messages = Set(services.compactMap { $0["NSMessage"] as? String })
    #expect(messages == ["addToTray", "transformFiles"])
    for message in messages {
      #expect(FinderServicesProvider.instancesRespond(to: Selector("\(message):userData:error:")))
    }
  }
}
