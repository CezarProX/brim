import AppKit
import SwiftUI
import Testing

@testable import Brim

@MainActor
@Suite(.serialized)
struct DropletRingEmojiRenderTests {
  @Test func rendersTheRingWithAHoveredSlot() async throws {
    let layout = RingLayout.standard.addingRing()
    let model = RingViewModel(layout: layout)
    model.pointerMoved(dx: 70, dy: 70)  // lower right: slot 3
    let bitmap = try await DropletRender.png(RingView(model: model), size: CGSize(width: 340, height: 340), name: "ring.png")
    #expect(bitmap.pixelsWide > 0)
  }

  @Test func rendersTheEmojiPicker() async throws {
    let settings = DropletRender.isolatedSettings()
    settings.emojiRecents = ["😀", "🔥", "👍🏽"]
    let model = EmojiPickerModel(settings: settings)
    let view = EmojiPickerView(model: model).padding(12)
    try await DropletRender.png(view, size: CGSize(width: 420, height: 400), name: "emoji.png")
    model.query = "heart"
    try await DropletRender.png(EmojiPickerView(model: model).padding(12), size: CGSize(width: 420, height: 400), name: "emoji-search.png")
  }
}
