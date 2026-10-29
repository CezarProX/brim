import AppKit
import SwiftUI
import Testing

@testable import Brim

@MainActor
struct OnboardingTourTests {
  @Test func windowStaysBelowTheMenuBarAndNotch() {
    let screens: [CGRect] = [
      CGRect(x: 0, y: 0, width: 1512, height: 944),  // 14" notched MacBook: visible frame excludes the menu bar
      CGRect(x: 0, y: 0, width: 1440, height: 875),
      CGRect(x: 0, y: 0, width: 1280, height: 775),  // small scaled display
      CGRect(x: -1920, y: 40, width: 1920, height: 1055),  // secondary display, negative origin
      CGRect(x: 0, y: 0, width: 1024, height: 640),  // too small for the full window: scales down
    ]
    for visible in screens {
      let placed = OnboardingPlacement.layout(size: OnboardingMetrics.size, visibleFrame: visible)
      #expect(placed.frame.maxY < visible.maxY, "top stays under the menu bar on \(visible)")
      #expect(placed.frame.minY >= visible.minY)
      #expect(placed.frame.minX >= visible.minX && placed.frame.maxX <= visible.maxX)
      #expect(placed.scale <= 1)
    }
    let roomy = OnboardingPlacement.layout(size: OnboardingMetrics.size, visibleFrame: screens[0])
    #expect(roomy.scale == 1 && roomy.frame.size == OnboardingMetrics.size)
  }

  @Test func windowUsesTheFloatingLevelAndKeyboard() throws {
    #expect(OnboardingKey.from(keyCode: 53) == .close)
    #expect(OnboardingKey.from(keyCode: 123) == .back)
    #expect(OnboardingKey.from(keyCode: 124) == .forward)
    #expect(OnboardingKey.from(keyCode: 0) == nil)
    let window = OnboardingWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    var keys: [OnboardingKey] = []
    window.onKey = { keys.append($0) }
    let event = try #require(NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
      isARepeat: false, keyCode: 124))
    window.keyDown(with: event)
    window.cancelOperation(nil)
    #expect(keys == [.forward, .close])
    #expect(window.canBecomeKey)
  }

  @Test func flowMovesAndTracksDirection() {
    let flow = OnboardingFlow()
    flow.step(-1)
    #expect(flow.page == .welcome)
    flow.step(1)
    #expect(flow.page == .tray && flow.forward)
    flow.go(to: 0)
    #expect(!flow.forward)
    flow.go(to: 999)
    #expect(flow.page == .welcome)
  }

  @Test func everyPageHasCopyAndAHeroThatFits() {
    for page in OnboardingPage.allCases {
      #expect(!page.title.isEmpty && !page.subtitle.isEmpty)
      if case .island(let size) = page.hero {
        let bottom = OnboardingMetrics.band + size.height
        #expect(bottom < OnboardingMetrics.dotsY(rows: page.optionRowCount > 0), "\(page) island clears the page dots")
        #expect(size.width < OnboardingMetrics.size.width)
      }
    }
  }

  @Test func sceneGeneratesAllLayers() {
    #expect(OnboardingArt.shared.layers.count == 7)
    #expect(OnboardingArt.shared.composite(progress: 0.5) != nil)
  }

  @Test func everyPageRendersToAPng() async throws {
    let playing = await OnboardingSamples.nowPlaying()
    for page in OnboardingPage.allCases {
      let bitmap = try await DropletRender.png(
        OnboardingView(page: page, sample: playing, hudStep: page == .huds ? 2 : nil,
                       replyPhase: page == .replies ? .code(.payload("https://web.whatsapp.com/link-demo")) : nil),
        size: OnboardingView.size,
        name: "onboarding-\(String(format: "%02d", page.rawValue))-\(page).png", background: .clear)
      var bright = 0
      for x in stride(from: 150, to: 650, by: 7) {
        for y in stride(from: 440, to: 700, by: 4) {
          if let color = bitmap.colorAt(x: x, y: y), color.brightnessComponent > 0.8 { bright += 1 }
        }
      }
      #expect(bright > 30, "\(page) title and copy draw")
    }
  }
}
