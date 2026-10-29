import Foundation
import Testing

@testable import Brim

struct DemoCommandTests {
  @Test func parsesPagesAndWidgets() {
    #expect(DemoCommand.parse("open home") == .open(.home))
    #expect(DemoCommand.parse("open tray") == .open(.tray))
    #expect(DemoCommand.parse("  OPEN   Clipboard ") == .open(.clipboard))
    #expect(DemoCommand.parse("widget calendar") == .widget(.calendar))
    #expect(DemoCommand.parse("widget agents") == .widget(.agents))
    #expect(DemoCommand.parse("close") == .close)
    #expect(DemoCommand.parse("customize on") == .customize(true))
    #expect(DemoCommand.parse("customize off") == .customize(false))
    #expect(DemoCommand.parse("pill on") == .pill(true))
    #expect(DemoCommand.parse("pill off") == .pill(false))
    #expect(DemoCommand.parse("pill") == nil)
  }

  @Test func parsesFlashesWithClampedLevels() {
    #expect(DemoCommand.parse("flash volume 60") == .flash(.volume(0.6)))
    #expect(DemoCommand.parse("flash volume 140") == .flash(.volume(1)))
    #expect(DemoCommand.parse("flash caps on") == .flash(.capsLock(true)))
    #expect(DemoCommand.parse("flash charging 82") == .flash(.charging(82)))
    #expect(DemoCommand.parse("flash full") == .flash(.full))
    #expect(DemoCommand.parse("flash airpods") == .flash(.airPods))
    #expect(DemoCommand.parse("flash camera") == .flash(.camera))
    #expect(DemoCommand.parse("flash mic") == .flash(.microphone))
  }

  @Test func parsesTrayBasketAndRing() {
    #expect(DemoCommand.parse("tray add /tmp/a b.png") == .trayAdd([URL(fileURLWithPath: "/tmp/a b.png")]))
    #expect(DemoCommand.parse("tray clear") == .trayClear)
    #expect(DemoCommand.parse("basket 900 500 /tmp/x.png") == .basket(CGPoint(x: 900, y: 500), [URL(fileURLWithPath: "/tmp/x.png")]))
    #expect(DemoCommand.parse("ring 756 491") == .ring(CGPoint(x: 756, y: 491)))
    #expect(DemoCommand.parse("ring close") == .ringClose)
    #expect(DemoCommand.parse("basket close") == .basketClose)
    #expect(DemoCommand.parse("quickactions 1000 640") == .quickActions(CGPoint(x: 1000, y: 640)))
    #expect(DemoCommand.parse("quickactions close") == .quickActionsClose)
    #expect(DemoCommand.parse("prepare") == .prepare)
    #expect(DemoCommand.parse("finish") == .finish)
  }

  @Test func parsesMessagesAndReplies() {
    #expect(DemoCommand.parse("message Alex Morgan: Nachos at seven? I'll bring the cheese.")
      == .message(sender: "Alex Morgan", body: "Nachos at seven? I'll bring the cheese."))
    #expect(DemoCommand.parse("type Count me in! See you at 7.") == .type("Count me in! See you at 7."))
    #expect(DemoCommand.parse("send") == .send)
    #expect(DemoCommand.parse("message no colon here") == nil)
    #expect(DemoCommand.parse("message : body only") == nil)
    #expect(DemoCommand.parse("type") == nil)
  }

  @Test func parsesThumbnailAndEditor() {
    #expect(DemoCommand.parse("thumb show /tmp/a b.png") == .thumbnail(URL(fileURLWithPath: "/tmp/a b.png")))
    #expect(DemoCommand.parse("thumb hover on") == .thumbnailHover(true))
    #expect(DemoCommand.parse("thumb hover off") == .thumbnailHover(false))
    #expect(DemoCommand.parse("thumb close") == .thumbnailClose)
    #expect(DemoCommand.parse("editor open /tmp/shot.png") == .editorOpen(URL(fileURLWithPath: "/tmp/shot.png")))
    #expect(DemoCommand.parse("editor close") == .editorClose)
    #expect(DemoCommand.parse("editor ellipse 10 20 300 200") == .mark(.ellipse(CGRect(x: 10, y: 20, width: 300, height: 200))))
    #expect(DemoCommand.parse("editor arrow 40 50 400 300") == .mark(.arrow(CGPoint(x: 40, y: 50), CGPoint(x: 400, y: 300))))
    #expect(DemoCommand.parse("editor text 120 80 Everything you need") == .mark(.text(CGPoint(x: 120, y: 80), "Everything you need")))
  }

  @Test func rejectsIncompleteThumbnailAndEditorCommands() {
    #expect(DemoCommand.parse("thumb show relative.png") == nil)
    #expect(DemoCommand.parse("thumb hover") == nil)
    #expect(DemoCommand.parse("editor open") == nil)
    #expect(DemoCommand.parse("editor ellipse 10 20 300") == nil)
    #expect(DemoCommand.parse("editor ellipse 10 20 0 200") == nil)
    #expect(DemoCommand.parse("editor arrow 1 2 3 x") == nil)
    #expect(DemoCommand.parse("editor text 120 80") == nil)
  }

  @Test func rejectsUnknownOrIncompleteCommands() {
    #expect(DemoCommand.parse("") == nil)
    #expect(DemoCommand.parse("open calendar") == nil)
    #expect(DemoCommand.parse("widget nope") == nil)
    #expect(DemoCommand.parse("flash volume") == nil)
    #expect(DemoCommand.parse("tray add") == nil)
    #expect(DemoCommand.parse("tray add relative/path.png") == nil)
    #expect(DemoCommand.parse("basket 10 x /tmp/x.png") == nil)
    #expect(DemoCommand.parse("quickactions 1000") == nil)
    #expect(DemoCommand.parse("rm -rf /") == nil)
  }
}
