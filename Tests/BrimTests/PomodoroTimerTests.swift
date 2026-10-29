import Foundation
import Testing

@testable import Brim

@MainActor
struct PomodoroTimerTests {
  @Test func pomodoroAlternatesFocusAndBreakWithoutCompleting() {
    let model = FocusTimerModel(flashes: nil)
    defer { model.stop() }
    let start = Date(timeIntervalSinceReferenceDate: 1_000)
    model.startPomodoro(focusMinutes: 25, breakMinutes: 5, now: start)
    #expect(model.phase == .focus)
    #expect(model.isPomodoro)

    let focusEnd = start.addingTimeInterval(25 * 60)
    model.tick(now: focusEnd)
    #expect(model.phase == .rest)
    #expect(model.completedSessions == 1)
    #expect(!model.completed)
    #expect(model.remaining(at: focusEnd) == 5 * 60)

    model.tick(now: focusEnd.addingTimeInterval(5 * 60))
    #expect(model.phase == .focus)
    #expect(model.remaining(at: focusEnd.addingTimeInterval(5 * 60)) == 25 * 60)
  }

  @Test func plainTimerAcceptsLongDurationsFromTheDial() {
    let model = FocusTimerModel(flashes: nil)
    defer { model.stop() }
    model.start(minutes: 290)
    #expect(model.duration == 290 * 60)
    #expect(!model.isPomodoro)
    model.start(minutes: 5_000)
    #expect(model.duration == 600 * 60)
  }
}

struct TimerDialMathTests {
  @Test func draggingLeftAddsMinutesAndClampsToRange() {
    #expect(TimerDialMath.minutes(from: 25, translation: -9 * 5, range: 1...600) == 30)
    #expect(TimerDialMath.minutes(from: 25, translation: 9 * 3, range: 1...600) == 22)
    #expect(TimerDialMath.minutes(from: 3, translation: 900, range: 1...600) == 1)
    #expect(TimerDialMath.minutes(from: 598, translation: -900, range: 1...600) == 600)
  }

  @Test func labelsHoursLikeTheClockApp() {
    #expect(TimerDialMath.label(minutes: 25) == "25:00")
    #expect(TimerDialMath.label(minutes: 290) == "4:50:00")
  }
}
