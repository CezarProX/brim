import AVFoundation
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers

@testable import Brim

/// Runs the real engine on small generated files.
@Suite(.serialized) struct TransformIntegrationTests {
  private func run(
    _ operation: TransformOperation, _ files: [URL], _ options: TransformOptions = TransformOptions(),
    policy: TransformOutputPolicy = TransformOutputPolicy()
  ) async throws -> [TransformOutcome] {
    var outcomes: [TransformOutcome] = []
    for sources in TransformEngine.units(for: files, operation: operation) {
      outcomes.append(try await TransformEngine.process(
        sources, operation: operation, options: options, context: TransformContext(policy: policy)))
    }
    return outcomes
  }

  @Test func compressWritesASmallerCopyAndKeepsTheOriginal() async throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let source = try fixtures.image("shot.jpg", width: 800, height: 600)
    let before = TransformFixtures.size(source)
    var options = TransformOptions()
    options.imageQuality = 0.4
    let outcome = try #require(try await run(.compress, [source], options).first)
    let output = try #require(outcome.outputs.first)
    #expect(output.lastPathComponent == "shot-compressed.jpg")
    #expect(outcome.bytesAfter < before)
    #expect(FileManager.default.fileExists(atPath: source.path))
    #expect(TransformFixtures.size(source) == before)
    // Running again must not overwrite the first result.
    let second = try #require(try await run(.compress, [source], options).first?.outputs.first)
    #expect(second.lastPathComponent == "shot-compressed 2.jpg")
  }

  @Test func underTargetSearchLandsInsideTheBudget() async throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let source = try fixtures.image("big.jpg", width: 1200, height: 900)
    let budget = TransformFixtures.size(source) / 4
    var options = TransformOptions()
    options.targetBytes = budget
    options.imageFormat = .jpeg
    let outcome = try #require(try await run(.compress, [source], options).first)
    #expect(outcome.bytesAfter <= budget)
    #expect(outcome.bytesAfter > budget / 4)
  }

  @Test func resizeCapsTheLongestSideAndNeverEnlarges() async throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let source = try fixtures.image("wide.png", width: 600, height: 300, type: .png, withMetadata: false)
    var options = TransformOptions()
    options.maxDimension = 200
    let output = try #require(try await run(.resize, [source], options).first?.outputs.first)
    let props = TransformFixtures.properties(output)
    #expect(props[kCGImagePropertyPixelWidth] as? Int == 200)
    #expect(props[kCGImagePropertyPixelHeight] as? Int == 100)
    options.maxDimension = 5000
    let same = try #require(try await run(.resize, [source], options).first?.outputs.first)
    #expect(TransformFixtures.properties(same)[kCGImagePropertyPixelWidth] as? Int == 600)
    options.resizeMode = .percent
    options.percent = 50
    let half = try #require(try await run(.resize, [source], options).first?.outputs.first)
    #expect(TransformFixtures.properties(half)[kCGImagePropertyPixelWidth] as? Int == 300)
  }

  @Test func convertChangesTheFormat() async throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let source = try fixtures.image("p.png", type: .png, withMetadata: false)
    var options = TransformOptions()
    options.convertFormat = .jpeg
    let jpg = try #require(try await run(.convert, [source], options).first?.outputs.first)
    #expect(jpg.lastPathComponent == "p.jpg")
    #expect(ImageTransforms.sourceType(jpg)?.conforms(to: .jpeg) == true)
    options.convertFormat = .heic
    let heic = try #require(try await run(.convert, [source], options).first?.outputs.first)
    #expect(ImageTransforms.sourceType(heic)?.conforms(to: .heic) == true)
  }

  @Test func removeMetadataDropsGPSAndExifButKeepsPixels() async throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let source = try fixtures.image("geo.jpg")
    #expect(TransformFixtures.properties(source)[kCGImagePropertyGPSDictionary] != nil)
    let output = try #require(try await run(.removeMetadata, [source]).first?.outputs.first)
    let props = TransformFixtures.properties(output)
    #expect(props[kCGImagePropertyGPSDictionary] == nil)
    #expect((props[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment] == nil)
    #expect((props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] == nil)
    #expect(props[kCGImagePropertyPixelWidth] as? Int == 400)
    #expect(TransformFixtures.properties(source)[kCGImagePropertyGPSDictionary] != nil)
  }

  @Test func compressStripsMetadataWhenAsked() async throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let source = try fixtures.image("geo.jpg")
    var options = TransformOptions()
    options.stripMetadata = true
    options.imageQuality = 0.5
    let output = try #require(try await run(.compress, [source], options).first?.outputs.first)
    #expect(TransformFixtures.properties(output)[kCGImagePropertyGPSDictionary] == nil)
    options.stripMetadata = false
    let kept = try #require(try await run(.compress, [source], options).first?.outputs.first)
    #expect(TransformFixtures.properties(kept)[kCGImagePropertyGPSDictionary] != nil)
  }

  @Test func rotateTurnsImagesClockwise() async throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let source = try fixtures.image("r.png", width: 40, height: 20, type: .png, withMetadata: false)
    let output = try #require(try await run(.rotate, [source]).first?.outputs.first)
    let props = TransformFixtures.properties(output)
    #expect(props[kCGImagePropertyPixelWidth] as? Int == 20)
    #expect(props[kCGImagePropertyPixelHeight] as? Int == 40)
  }

  @Test func combineMakesOnePDFFromImagesAndPDFs() async throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let image = try fixtures.image("a.jpg")
    let pdf = try fixtures.pdf("b.pdf", pages: 2)
    let outcomes = try await run(.combinePDF, [image, pdf])
    #expect(outcomes.count == 1)
    let output = try #require(outcomes.first?.outputs.first)
    #expect(output.lastPathComponent == "a-combined.pdf")
    #expect(PDFDocument(url: output)?.pageCount == 3)
  }

  @Test func splitWritesOnePDFPerPage() async throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let pdf = try fixtures.pdf("doc.pdf", pages: 3)
    let outputs = try #require(try await run(.splitPDF, [pdf]).first?.outputs)
    #expect(outputs.map(\.lastPathComponent) == ["doc-page-1.pdf", "doc-page-2.pdf", "doc-page-3.pdf"])
    #expect(outputs.allSatisfy { PDFDocument(url: $0)?.pageCount == 1 })
  }

  @Test func pdfMetadataIsCleared() async throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let pdf = try fixtures.pdf("meta.pdf", pages: 1, title: "Private title")
    let output = try #require(try await run(.removeMetadata, [pdf]).first?.outputs.first)
    let attributes = PDFDocument(url: output)?.documentAttributes ?? [:]
    #expect(attributes[PDFDocumentAttribute.titleAttribute] == nil)
    #expect(attributes[PDFDocumentAttribute.authorAttribute] == nil)
  }

  @Test func pdfCompressRotateKeepPageCount() async throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let pdf = try fixtures.pdf("big.pdf", pages: 2)
    var options = TransformOptions()
    options.pdfQuality = .small
    let outcome = try #require(try await run(.compress, [pdf], options).first)
    if let output = outcome.outputs.first {
      #expect(PDFDocument(url: output)?.pageCount == 2)
    } else {
      #expect(outcome.note == "Already as small as it gets")
    }
    let rotated = try #require(try await run(.rotate, [pdf]).first?.outputs.first)
    #expect(PDFDocument(url: rotated)?.page(at: 0)?.rotation == 90)
  }

  @Test func zipThenExtractRoundTrips() async throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let a = fixtures.folder.appendingPathComponent("a.txt"), b = fixtures.folder.appendingPathComponent("b.txt")
    try "alpha".write(to: a, atomically: true, encoding: .utf8)
    try "beta".write(to: b, atomically: true, encoding: .utf8)
    let archive = try #require(try await run(.zip, [a, b]).first?.outputs.first)
    #expect(archive.lastPathComponent == "Archive.zip")
    let folder = try #require(try await run(.extract, [archive]).first?.outputs.first)
    #expect(try String(contentsOf: folder.appendingPathComponent("Archive/a.txt"), encoding: .utf8) == "alpha")
    #expect(try String(contentsOf: folder.appendingPathComponent("Archive/b.txt"), encoding: .utf8) == "beta")
  }

  @Test func trashingOriginalsRemovesThemOnlyOnRequest() async throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let keep = try fixtures.image("keep.jpg")
    let drop = try fixtures.image("drop.jpg")
    var options = TransformOptions()
    options.imageQuality = 0.3
    _ = try await run(.compress, [keep], options)
    #expect(FileManager.default.fileExists(atPath: keep.path))
    var policy = TransformOutputPolicy()
    policy.moveOriginalsToTrash = true
    let outcome = try #require(try await run(.compress, [drop], options, policy: policy).first)
    #expect(!FileManager.default.fileExists(atPath: drop.path))
    #expect(FileManager.default.fileExists(atPath: try #require(outcome.outputs.first).path))
  }

  @Test func downloadsDestinationIsHonored() async throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let source = try fixtures.image("d.jpg")
    let downloads = fixtures.folder.appendingPathComponent("Dl")
    try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
    var policy = TransformOutputPolicy()
    policy.destination = .downloads
    var options = TransformOptions()
    options.imageQuality = 0.3
    let outcome = try await TransformEngine.process(
      [source], operation: .compress, options: options, context: TransformContext(policy: policy, downloads: downloads))
    #expect(outcome.outputs.first?.deletingLastPathComponent().path == downloads.path)
  }

  @Test func cancellingStopsTheRunAndMarksTheRest() async throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let files = try (0..<3).map { try fixtures.image("c\($0).jpg", width: 200, height: 200) }
    let states = StateLog()
    let task = Task {
      await TransformEngine.run(
        units: files.map { [$0] }, operation: .compress, options: TransformOptions(), policy: TransformOutputPolicy()
      ) { index, state in states.record(index, state) }
    }
    task.cancel()
    await task.value
    #expect(states.final(0) == .cancelled)
    #expect(states.final(2) == .cancelled)
  }

  // MARK: Audio / video

  @Test func videoOperationsProduceOutput() async throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let video = try await fixtures.video("clip.mp4")
    var options = TransformOptions()
    options.gifFPS = 5
    options.gifWidth = 32
    let gif = try #require(try await run(.makeGIF, [video], options).first?.outputs.first)
    let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
    #expect(CGImageSourceGetCount(source) == 10)
    #expect(gif.pathExtension == "gif")

    options.trimStart = 0.5
    options.trimEnd = 1.5
    let trimmed = try #require(try await run(.trim, [video], options).first?.outputs.first)
    let duration = try await AVURLAsset(url: trimmed).load(.duration).seconds
    #expect(abs(duration - 1.0) < 0.35)

    options.targetFPS = 5
    let slowed = try #require(try await run(.frameRate, [video], options).first?.outputs.first)
    let rate = try await AVURLAsset(url: slowed).loadTracks(withMediaType: .video).first?.load(.nominalFrameRate) ?? 0
    #expect(rate > 0 && rate <= 10)

    options.rotation = 90
    let rotated = try #require(try await run(.rotate, [video], options).first?.outputs.first)
    let size = try await AVURLAsset(url: rotated).loadTracks(withMediaType: .video).first?.load(.naturalSize)
    #expect(size?.width == 48 && size?.height == 64)

    let silent = try #require(try await run(.removeAudio, [video]).first?.outputs.first)
    #expect(try await AVURLAsset(url: silent).loadTracks(withMediaType: .audio).isEmpty)
  }

  @Test func gifFromImagesMakesOneFramePerPicture() async throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let images = try (0..<3).map { try fixtures.image("f\($0).jpg", width: 100, height: 80) }
    var options = TransformOptions()
    options.gifWidth = 64
    let outcomes = try await run(.makeGIF, images, options)
    #expect(outcomes.count == 1)
    let gif = try #require(outcomes.first?.outputs.first)
    #expect(CGImageSourceGetCount(try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))) == 3)
  }
}

private final class StateLog: @unchecked Sendable {
  private let lock = NSLock()
  private var states: [Int: TransformUnitState] = [:]
  func record(_ index: Int, _ state: TransformUnitState) {
    lock.lock(); states[index] = state; lock.unlock()
  }
  func final(_ index: Int) -> TransformUnitState? {
    lock.lock(); defer { lock.unlock() }
    return states[index]
  }
}
