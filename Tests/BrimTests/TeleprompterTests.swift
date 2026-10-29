import Foundation
import Testing
@testable import Brim

struct TeleprompterMathTests {
  @Test("Speed levels map to points per second and clamp")
  func speed() {
    #expect(TeleprompterMath.pointsPerSecond(level: 1) == 9)
    #expect(TeleprompterMath.pointsPerSecond(level: 20) == 66)
    #expect(TeleprompterMath.pointsPerSecond(level: 99) == 66)
    #expect(TeleprompterMath.pointsPerSecond(level: -4) == 9)
  }

  @Test("Advance moves by speed x dt and finishes at the end")
  func advance() {
    let step = TeleprompterMath.advance(offset: 0, dt: 0.1, level: 6, contentHeight: 1000)
    #expect(abs(step.offset - 2.4) < 0.0001 && !step.finished)
    let end = TeleprompterMath.advance(offset: 999, dt: 0.1, level: 20, contentHeight: 1000)
    #expect(end == .init(offset: 1000, finished: true))
  }

  @Test("A stalled frame never jumps and bad input is safe")
  func stalled() {
    let step = TeleprompterMath.advance(offset: 0, dt: 5, level: 20, contentHeight: 10_000)
    #expect(abs(step.offset - 16.5) < 0.0001)
    #expect(TeleprompterMath.advance(offset: -10, dt: 0, level: 5, contentHeight: 100).offset == 0)
    #expect(TeleprompterMath.advance(offset: 5, dt: 1, level: 5, contentHeight: 0) == .init(offset: 5, finished: false))
  }

  @Test("Progress, time remaining and clock")
  func progress() {
    #expect(TeleprompterMath.progress(offset: 250, contentHeight: 1000) == 0.25)
    #expect(TeleprompterMath.progress(offset: 5000, contentHeight: 1000) == 1)
    #expect(TeleprompterMath.secondsRemaining(offset: 0, level: 6, contentHeight: 240) == 10)
    #expect(TeleprompterMath.clock(185) == "3:05")
  }

  @Test("Paragraphs and word counts")
  func text() {
    #expect(TeleprompterMath.paragraphs("a b\r\n\r\n\n\nc") == ["a b", "c"])
    #expect(TeleprompterMath.wordCount("one two\nthree") == 3)
    #expect(TeleprompterMath.approximateWordsPerMinute(level: 6, fontSize: 24) > 100)
  }

  @MainActor
  @Test("Model: hovering pauses movement, speed keys clamp, empty script won't play")
  func model() {
    let defaults = UserDefaults(suiteName: "qs-tp-\(UUID())")!
    let settings = AppSettings(defaults: defaults)
    let model = TeleprompterModel(settings: settings)
    model.play()
    #expect(!model.isPlaying)
    model.script = "hello world"
    model.play()
    #expect(model.isPlaying && model.isMoving)
    model.isHovering = true
    #expect(!model.isMoving)
    model.pause()
    for _ in 0..<40 { model.faster() }
    #expect(model.speed == 20 && settings.teleprompterSpeed == 20)
  }
}
