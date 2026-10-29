import Testing

@testable import Brim

struct ReopenPolicyTests {
  /// A menu-bar app opens Settings when the user reopens it, not when the system or another app does.
  @Test func onlyUserLaunchersOpenSettings() {
    for launcher in ["com.apple.dock", "com.apple.finder", "com.apple.Spotlight"] {
      #expect(ReopenPolicy.opensSettings(sender: launcher), "\(launcher)")
    }
    for other in ["com.apple.siri", "com.apple.Siri", "com.apple.intelligencecontextd", "com.apple.linkd", nil] {
      #expect(!ReopenPolicy.opensSettings(sender: other), "\(String(describing: other))")
    }
  }
}
