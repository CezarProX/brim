import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Brim

struct ImageDragExportTests {
  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("drag-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private var png: Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 8, bitsPerPixel: 32)!
    return bitmap.representation(using: .png, properties: [:])!
  }

  @Test func writesARealPNGFileWithAFinderStyleName() throws {
    let dir = try folder()
    let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 2, minute: 41, second: 13))!
    let file = try #require(ImageDragExport.write(png, date: date, in: dir))
    #expect(file.lastPathComponent == "Image 2026-09-25 at 02.41.13.png")
    #expect(try Data(contentsOf: file) == png)
  }

  @Test func sameSecondDoesNotOverwriteAnEarlierDrag() throws {
    let dir = try folder()
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    let first = try #require(ImageDragExport.write(png, date: date, in: dir))
    let second = try #require(ImageDragExport.write(png, date: date, in: dir))
    #expect(first != second)
    #expect(FileManager.default.fileExists(atPath: first.path))
  }

  /// Chat apps take files; editors take image data. The file comes first.
  @Test func providerOffersTheFileThenTheImageData() throws {
    let dir = try folder()
    let provider = try #require(ImageDragExport.provider(for: png, date: .now, in: dir))
    let types = provider.registeredTypeIdentifiers
    #expect(types.first == UTType.fileURL.identifier)
    #expect(types.contains(UTType.png.identifier))
  }

  @Test func oldExportsAreCleanedUp() throws {
    let dir = try folder()
    let old = try #require(ImageDragExport.write(png, date: .now, in: dir))
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: old.path)
    let fresh = try #require(ImageDragExport.write(png, date: .now.addingTimeInterval(5), in: dir))
    ImageDragExport.removeStale(in: dir)
    #expect(!FileManager.default.fileExists(atPath: old.path))
    #expect(FileManager.default.fileExists(atPath: fresh.path))
  }
}
