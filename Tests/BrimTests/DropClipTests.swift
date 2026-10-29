import Foundation
import Testing
@testable import Brim

struct DropClipTransformTests {
  @Test("Case transforms")
  func cases() {
    #expect(DropClipTransforms.uppercased("Grüße, world") == "GRÜSSE, WORLD")
    #expect(DropClipTransforms.lowercased("ABC Def") == "abc def")
    #expect(DropClipTransforms.titleCased("the quick brown fox jumps over the lazy dog") == "The Quick Brown Fox Jumps Over the Lazy Dog")
    #expect(DropClipTransforms.titleCased("SHOUTING AT THE END OF") == "Shouting at the End Of")
    #expect(DropClipTransforms.titleCased("  ") == "  ")
    #expect(DropClipTransforms.titleCased("hello  world") == "Hello  World")
  }

  @Test("Counts")
  func counts() {
    let counts = DropClipTransforms.counts("one two\nthree four five")
    #expect(counts == .init(words: 5, characters: 22, lines: 2, readingSeconds: 1))
    #expect(counts.summary == "5 words · 22 characters · 2 lines")
    #expect(DropClipTransforms.counts("").words == 0)
    #expect(DropClipTransforms.counts("x").summary == "1 word · 1 character")
  }

  @Test("URL templates percent-escape reserved characters")
  func escaping() {
    #expect(DropClipTransforms.escapeForURL("a&b=c d?#/é") == "a%26b%3Dc%20d%3F%23%2F%C3%A9")
    #expect(DropClipTransforms.escapeForURL("a b", spaceAsPlus: true) == "a+b")
    #expect(DropClipTransforms.escapeForURL("1+1") == "1%2B1")
    #expect(DropClipTransforms.escapeForURL("  padded  ") == "padded")
    #expect(DropClipTransforms.escapeForURL(String(repeating: "x", count: 5000)).count == 2000)
  }

  @Test("Template expansion and rejection of unsafe or malformed templates")
  func expansion() {
    #expect(DropClipTransforms.expand(template: "https://example.com/?q={text}", text: "swift & co")?.absoluteString == "https://example.com/?q=swift%20%26%20co")
    #expect(DropClipTransforms.expand(template: "https://duckduckgo.com/?q={text+}", text: "a b")?.absoluteString == "https://duckduckgo.com/?q=a+b")
    #expect(DropClipTransforms.expand(template: "things:///add?title={text}", text: "Buy milk")?.scheme == "things")
    #expect(DropClipTransforms.expand(template: "https://example.com/", text: "x") == nil)
    #expect(DropClipTransforms.expand(template: "javascript:alert('{text}')", text: "x") == nil)
    #expect(DropClipTransforms.expand(template: "file:///{text}", text: "etc/passwd") == nil)
    #expect(DropClipTransforms.expand(template: "{text}", text: "x") == nil)
    #expect(DropClipTransforms.expand(template: "https://{text}", text: "evil.com/path")?.host != "evil.com")
  }

  @Test("AppleScript quoting cannot break out of the string")
  func appleScript() {
    #expect(DropClipTransforms.appleScriptQuoted("say \"hi\" \\ now") == "\"say \\\"hi\\\" \\\\ now\"")
    let script = DropClipTransforms.notesScript(for: "a\" & (do shell script \"x\") & \"<b>")
    #expect(script.hasPrefix("tell application \"Notes\""))
    #expect(!script.contains("\" & (do"))
    #expect(DropClipTransforms.notesHTML("a<b>&\nc") == "<div>a&lt;b&gt;&amp;<br>c</div>")
  }
}

struct DropClipRulesTests {
  @Test("Action ids round-trip")
  func ids() {
    let id = UUID()
    for action in DropClipAction.builtIns + [.custom(id)] { #expect(DropClipAction(rawValue: action.rawValue) == action) }
    #expect(DropClipAction(rawValue: "nonsense") == nil)
  }

  @Test("Per-app rules hide the bar or individual actions")
  func rules() {
    var rules = DropClipRules()
    #expect(rules.isEnabled(in: "com.apple.Safari") && rules.isEnabled(in: nil))
    rules = rules.setting(DropClipAppRule(enabled: false), for: "com.apple.Terminal")
      .setting(DropClipAppRule(enabled: true, hidden: ["notes", "translate"]), for: "com.apple.Safari")
    #expect(!rules.isEnabled(in: "com.apple.Terminal"))
    let shown = rules.actions(global: DropClipAction.builtIns, in: "com.apple.Safari")
    #expect(!shown.contains(.notes) && !shown.contains(.translate) && shown.contains(.copy))
    #expect(rules.actions(global: DropClipAction.builtIns, in: "other") == DropClipAction.builtIns)
    #expect(rules.removing("com.apple.Terminal").isEnabled(in: "com.apple.Terminal"))
  }

  @Test("Settings persist actions, custom actions and rules")
  func persistence() {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "qs-dc-\(UUID())")!)
    #expect(settings.dropClipActions == DropClipAction.builtIns)
    settings.dropClipActions = [.copy, .count]
    let custom = DropClipCustomAction(title: "IMDb", kind: .url, template: "https://imdb.com/find?q={text}")
    settings.dropClipCustomActions = [custom]
    settings.dropClipRules = DropClipRules().setting(DropClipAppRule(enabled: false), for: "x.y")
    #expect(settings.dropClipActions == [.copy, .count])
    #expect(settings.dropClipCustomActions == [custom])
    #expect(!settings.dropClipRules.isEnabled(in: "x.y"))
  }

  @Test("AX rects convert to Cocoa coordinates")
  @MainActor func coordinates() {
    let rect = SelectionReader.cocoaRect(fromAX: CGRect(x: 100, y: 50, width: 200, height: 20), primaryHeight: 900)
    #expect(rect == CGRect(x: 100, y: 830, width: 200, height: 20))
  }
}

struct ShellSnippetTests {
  @Test("Text reaches the snippet via env and stdin, never via the command line")
  func run() async {
    let hostile = "$(touch /tmp/qs-should-not-exist); `id`"
    let outcome = await ShellSnippetRunner.run("printf '%s|' \"$DROPCLIP_TEXT\"; cat", text: hostile, title: "t")
    #expect(outcome.body == "\(hostile)|\(hostile)")
    #expect(!FileManager.default.fileExists(atPath: "/tmp/qs-should-not-exist"))
    let failed = await ShellSnippetRunner.run("exit 3", text: "x", title: "t")
    #expect(failed.isError && failed.title.contains("exit 3"))
  }
}
