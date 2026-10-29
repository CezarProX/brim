import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Brim

@Suite struct TransformLogicTests {
  private func tempFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("QS-TL-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  // MARK: Naming

  @Test func outputNamesAddASuffixAndNeverCollide() throws {
    let folder = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("photo.png")
    let first = TransformNaming.outputURL(for: source, suffix: "compressed", fileExtension: "jpg", in: folder)
    #expect(first.lastPathComponent == "photo-compressed.jpg")
    try Data().write(to: first)
    let second = TransformNaming.outputURL(for: source, suffix: "compressed", fileExtension: "jpg", in: folder)
    #expect(second.lastPathComponent == "photo-compressed 2.jpg")
    let reserved = TransformNaming.outputURL(
      for: source, suffix: "compressed", fileExtension: "jpg", in: folder, reserved: [second.path])
    #expect(reserved.lastPathComponent == "photo-compressed 3.jpg")
  }

  @Test func convertingWithoutSuffixNeverReplacesTheOriginal() throws {
    let folder = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("a.jpg")
    try Data().write(to: source)
    let output = TransformNaming.outputURL(for: source, suffix: "", fileExtension: "jpg", in: folder)
    #expect(output != source)
    #expect(output.lastPathComponent == "a 2.jpg")
  }

  @Test func destinationPolicyPicksFolders() throws {
    let folder = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let downloads = folder.appendingPathComponent("Downloads")
    let source = folder.appendingPathComponent("x.png")
    var policy = TransformOutputPolicy()
    #expect(TransformNaming.folder(for: source, policy: policy, downloads: downloads).path == folder.path)
    policy.destination = .downloads
    #expect(TransformNaming.folder(for: source, policy: policy, downloads: downloads) == downloads)
    policy.destination = .nextToOriginal
    let readOnly = URL(fileURLWithPath: "/System/Library/x.png")
    #expect(TransformNaming.folder(for: readOnly, policy: policy, downloads: downloads) == downloads)
  }

  // MARK: Rename

  @Test func renamePatternExpandsTokens() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))!
    func name(_ pattern: String, _ index: Int = 1) -> String {
      TransformNaming.renamed(pattern: pattern, originalName: "IMG", index: index, date: date, calendar: calendar)
    }
    #expect(name("{name}-{n}", 3) == "IMG-3")
    #expect(name("Trip {date} {n:3}", 7) == "Trip 2026-03-09 007")
    #expect(name("a/b:c") == "a-b-c")
    #expect(name("") == "IMG")
    #expect(name("...") == "IMG")
    #expect(name("..hidden") == "hidden")
  }

  @Test func batchRenameKeepsExtensionsAndNeverOverwrites() throws {
    let folder = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let a = folder.appendingPathComponent("a.txt"), b = folder.appendingPathComponent("b.txt")
    try "a".write(to: a, atomically: true, encoding: .utf8)
    try "b".write(to: b, atomically: true, encoding: .utf8)
    try "taken".write(to: folder.appendingPathComponent("doc-2.txt"), atomically: true, encoding: .utf8)
    let renamed = try TransformEngine.rename([a, b], pattern: "doc-{n}")
    #expect(renamed.map(\.lastPathComponent) == ["doc-1.txt", "doc-2 2.txt"])
    #expect(try String(contentsOf: folder.appendingPathComponent("doc-2.txt"), encoding: .utf8) == "taken")
  }

  // MARK: Availability

  @Test func operationsFollowTheFileType() {
    #expect(TransformOperation.compress.isAvailable(for: .jpeg))
    #expect(TransformOperation.compress.isAvailable(for: .pdf))
    #expect(!TransformOperation.compress.isAvailable(for: .audio))
    #expect(TransformOperation.splitPDF.isAvailable(for: .pdf))
    #expect(!TransformOperation.splitPDF.isAvailable(for: .png))
    #expect(TransformOperation.extractAudio.isAvailable(for: .mpeg4Movie))
    #expect(!TransformOperation.extractAudio.isAvailable(for: .mp3))
    #expect(TransformOperation.trim.isAvailable(for: .mp3))
    #expect(TransformOperation.extract.isAvailable(for: .zip))
    #expect(TransformOperation.zip.isAvailable(for: .plainText))
    #expect(!TransformOperation.resize.isAvailable(for: nil))
  }

  @Test func mixedSelectionsOnlyOfferWhatEveryFileSupports() {
    let image = URL(fileURLWithPath: "/tmp/a.png"), pdf = URL(fileURLWithPath: "/tmp/b.pdf")
    let both = TransformOperation.available(for: [image, pdf])
    #expect(both.contains(.combinePDF))
    #expect(both.contains(.zip))
    #expect(!both.contains(.resize))
    #expect(TransformOperation.suggested(for: [image]) == .compress)
    #expect(TransformOperation.suggested(for: [URL(fileURLWithPath: "/tmp/a.txt")]) == .zip)
    #expect(TransformOperation.available(for: []).isEmpty)
  }

  @Test func presetsOnlyAppearForFilesTheyFit() {
    let png = URL(fileURLWithPath: "/tmp/a.png"), pdf = URL(fileURLWithPath: "/tmp/a.pdf"), mov = URL(fileURLWithPath: "/tmp/a.mov")
    #expect(TransformPreset.applicable(TransformPreset.builtIn, to: [png]).map(\.id).contains("builtin.web"))
    #expect(TransformPreset.applicable(TransformPreset.builtIn, to: [pdf]).map(\.id) == ["builtin.lightpdf"])
    #expect(TransformPreset.applicable(TransformPreset.builtIn, to: [mov]).map(\.id) == ["builtin.chatgif"])
  }

  // MARK: Target-size search

  @Test func searchPicksTheHighestQualityThatFits() {
    // size = quality * scale^2 * 1,000,000 bytes
    let attempt = TransformSearch.fit(target: 500_000) { quality, scale in Int(quality * scale * scale * 1_000_000) }
    #expect(attempt.fits)
    #expect(attempt.scale == 1)
    #expect(attempt.bytes <= 500_000)
    #expect(attempt.quality > 0.45 && attempt.quality <= 0.5)
  }

  @Test func searchShrinksResolutionWhenQualityAloneIsNotEnough() {
    var calls = 0
    let attempt = TransformSearch.fit(target: 30_000) { quality, scale in
      calls += 1
      return Int(quality * scale * scale * 1_000_000)
    }
    #expect(attempt.fits)
    #expect(attempt.scale < 1)
    #expect(attempt.bytes <= 30_000)
    #expect(calls < 60)
  }

  @Test func searchReturnsTheSmallestWhenNothingFits() {
    let attempt = TransformSearch.fit(target: 10) { _, scale in Int(scale * 10_000) + 100 }
    #expect(!attempt.fits)
    #expect(attempt.bytes == Int(0.2 * 10_000) + 100)
  }

  @Test func searchStopsEarlyWhenTopQualityAlreadyFits() {
    let attempt = TransformSearch.fit(target: 10_000_000) { quality, _ in Int(quality * 1_000_000) }
    #expect(attempt.quality == TransformSearch.qualityRange.upperBound)
  }

  // MARK: GIF timing

  @Test func gifTimingFollowsFrameRate() {
    let plan = GIFTiming.plan(duration: 10, fps: 12)
    #expect(plan.times.count == 120)
    #expect(abs(plan.times[1] - 1.0 / 12) < 1e-9)
    #expect(plan.delay == 0.08)  // 83 ms rounds to whole hundredths
    #expect(plan.times.last! < 10)
  }

  @Test func gifTimingCapsFramesOnLongClips() {
    let plan = GIFTiming.plan(duration: 60, fps: 30)
    #expect(plan.times.count <= GIFTiming.maximumFrames)
    #expect(plan.times.count >= GIFTiming.maximumFrames - 1)
    #expect(plan.delay >= 0.2 - 0.005)
  }

  @Test func gifTimingHandlesTinyAndInvalidClips() {
    #expect(GIFTiming.plan(duration: 0.05, fps: 12).times == [0])
    #expect(GIFTiming.plan(duration: 0, fps: 12).times == [0])
    #expect(GIFTiming.plan(duration: 2, fps: 100).delay == 0.02)
  }

  @Test func gifSizeNeverEnlarges() {
    #expect(GIFTiming.outputSize(source: CGSize(width: 1920, height: 1080), maxWidth: 480) == CGSize(width: 480, height: 270))
    #expect(GIFTiming.outputSize(source: CGSize(width: 200, height: 100), maxWidth: 480) == CGSize(width: 200, height: 100))
  }

  // MARK: Size summary

  @Test func sizeSummaryReadsNaturally() {
    let text = TransformSizeSummary.text(before: 4_200_000, after: 680_000)
    #expect(text == "4.2 MB → 680 KB, −84%")
    #expect(TransformSizeSummary.percentChange(before: 0, after: 5) == 0)
    #expect(TransformSizeSummary.text(before: 100, after: 150).hasSuffix("+50%"))
  }

  // MARK: Video geometry

  @Test func quarterTurnSwapsTheRenderSize() {
    let size = CGSize(width: 1920, height: 1080)
    let (transform, render) = VideoGeometry.rotated(.identity, size: size, degrees: 90)
    #expect(render == CGSize(width: 1080, height: 1920))
    // The clip's top-left corner lands in the top-right after a clockwise quarter turn.
    let corner = CGPoint.zero.applying(transform)
    #expect(abs(corner.x - 1080) < 0.001 && abs(corner.y) < 0.001)
    #expect(VideoGeometry.rotated(.identity, size: size, degrees: 180).1 == size)
  }

  @Test func optionsSurviveASaveAndLoad() throws {
    var options = TransformOptions()
    options.targetBytes = 5_000_000
    options.renamePattern = "x-{n}"
    let decoded = try JSONDecoder().decode(TransformOptions.self, from: JSONEncoder().encode(options))
    #expect(decoded == options)
  }
}
