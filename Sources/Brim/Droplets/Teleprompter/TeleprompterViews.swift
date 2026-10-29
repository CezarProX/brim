// TeleprompterViews.swift
// Brim
//
// The scrolling text, its control strip, and the island view (script editor + live preview).

import SwiftUI

/// Scrolling script text with soft fades. ←/→ change the speed, ↑/↓ nudge, Space plays/pauses.
struct TeleprompterScrollView: View {
  @ObservedObject var model: TeleprompterModel
  /// Takes key focus when it appears (the floating prompter). The island leaves it to the editor.
  var takesFocus = true
  @FocusState private var focused: Bool

  var body: some View {
    GeometryReader { proxy in
      let paragraphs = TeleprompterMath.paragraphs(model.script)
      ZStack(alignment: .topLeading) {
        if paragraphs.isEmpty {
          placeholder
        } else {
          VStack(alignment: .leading, spacing: CGFloat(model.fontSize) * 0.7) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, text in
              Text(text)
                .font(.system(size: CGFloat(model.fontSize), weight: .semibold, design: .rounded))
                .foregroundStyle(IslandInk.primary)
                .lineSpacing(CGFloat(model.fontSize) * 0.28)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .padding(.horizontal, 18)
          .frame(width: proxy.size.width, alignment: .leading)
          .background(GeometryReader { content in
            Color.clear.onAppear { model.contentHeight = content.size.height }
              .onChange(of: content.size.height) { _, height in model.contentHeight = height }
          })
          .offset(y: -model.offset + 8)
          .scaleEffect(x: model.mirrored ? -1 : 1, y: 1)
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
      .clipped()
      .mask(fade)
      .overlay(alignment: .topLeading) { readingMark }
    }
    .focusable()
    .focused($focused)
    .focusEffectDisabled()
    .onKeyPress(.leftArrow) { model.slower(); return .handled }
    .onKeyPress(.rightArrow) { model.faster(); return .handled }
    .onKeyPress(.upArrow) { model.nudge(by: -40); return .handled }
    .onKeyPress(.downArrow) { model.nudge(by: 40); return .handled }
    .onKeyPress(.space) { model.togglePlay(); return .handled }
    .onHover { model.isHovering = $0 }
    .onAppear { focused = takesFocus }
  }

  private var placeholder: some View {
    VStack(spacing: 6) {
      Image(systemName: "text.alignleft").font(.system(size: 22, weight: .light))
      Text("Your script scrolls here").font(.system(size: 12, weight: .medium))
    }
    .foregroundStyle(IslandInk.tertiary)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var fade: some View {
    LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .black, location: 0.12),
                           .init(color: .black, location: 0.78), .init(color: .clear, location: 1)],
                   startPoint: .top, endPoint: .bottom)
  }

  private var readingMark: some View {
    Image(systemName: "arrowtriangle.right.fill")
      .font(.system(size: 7)).foregroundStyle(Color.orange.opacity(0.9))
      .padding(.leading, 5).padding(.top, CGFloat(model.fontSize) * 0.55 + 4)
      .opacity(model.script.isEmpty ? 0 : 1)
  }
}

struct TeleprompterControls: View {
  @ObservedObject var model: TeleprompterModel
  var showsMirror = true
  /// Drops the progress bar and clock (the island preview is narrow).
  var compact = false

  var body: some View {
    HStack(spacing: 8) {
      DropletIconButton(symbol: model.isPlaying ? "pause.fill" : "play.fill", help: model.isPlaying ? "Pause (Space)" : "Play (Space)", tint: .orange, size: 28) { model.togglePlay() }
      DropletIconButton(symbol: "gobackward", help: "Back to the start", size: 28) { model.restart() }
      HStack(spacing: 4) {
        DropletIconButton(symbol: "minus", help: "Slower (←)", size: 28) { model.slower() }
        Text("\(model.speed)")
          .font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(IslandInk.primary)
          .frame(minWidth: 18).contentTransition(.numericText(value: Double(model.speed)))
          .animation(.snappy(duration: 0.2), value: model.speed)
        DropletIconButton(symbol: "plus", help: "Faster (→)", size: 28) { model.faster() }
      }
      if showsMirror {
        DropletIconButton(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", help: "Mirror text",
                          tint: model.mirrored ? .orange : IslandInk.secondary, size: 28) { model.setMirrored(!model.mirrored) }
      }
      Spacer(minLength: 0)
      if model.isPlaying && !model.isMoving {
        Label("Paused while the pointer is here", systemImage: "pause.circle").labelStyle(.iconOnly)
          .font(.system(size: 13)).foregroundStyle(.orange).help("Paused while the pointer is over the prompter")
      }
      if !compact { ProgressCapsule(progress: model.progress).frame(width: 70, height: 4) }
      if !compact { Text(model.remaining).font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(IslandInk.secondary)
        .contentTransition(.numericText()) }
    }
  }
}

private struct ProgressCapsule: View {
  let progress: Double
  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(IslandFill.raised)
        Capsule().fill(Color.orange).frame(width: max(4, proxy.size.width * progress))
      }
    }
  }
}

/// The droplet's island view: script editor on the left, live preview on the right.
struct TeleprompterIslandView: View {
  @ObservedObject private var model = TeleprompterModel.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: IslandSpace.m) {
        editor.frame(minWidth: 0, maxWidth: .infinity)
        preview.frame(width: 228)
      }
    }
    .frame(minWidth: 520, minHeight: 190)
  }

  private var editor: some View {
    DropletCard {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Label("Script", systemImage: "text.line.first.and.arrowtriangle.forward")
            .font(IslandFont.headline).foregroundStyle(IslandInk.primary)
          Spacer()
          textSize
          if !model.script.isEmpty {
            DropletIconButton(symbol: "trash", help: "Clear the script", size: 28) { model.script = "" }
          }
          DropletIconButton(symbol: "doc.on.clipboard", help: "Paste a script from the clipboard", size: 28) { model.pasteFromClipboard() }
          DropletIconButton(symbol: "folder", help: "Open a text file…", size: 28) { model.chooseFile() }
        }
        TextEditor(text: $model.script)
          .font(.system(size: 13)).scrollContentBackground(.hidden)
          .padding(4).background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: IslandRadius.small))
          .overlay { if model.script.isEmpty { emptyHint } }
        HStack(spacing: IslandSpace.s) {
          Text(summary).font(.system(size: 12)).foregroundStyle(IslandInk.secondary).lineLimit(1)
          if let error = model.loadError { Text(error).font(.system(size: 12)).foregroundStyle(.red).lineLimit(1) }
          Spacer(minLength: 0)
          Button { TeleprompterController.shared.showPrompter(autoPlay: true) } label: {
            Label("Show prompter", systemImage: "rectangle.on.rectangle")
          }
          .buttonStyle(IslandAppPillStyle(prominent: true, tint: .orange))
          .disabled(model.script.isEmpty)
          .help("Opens the prompter under the camera and starts scrolling. Esc closes it.")
        }
      }
      .padding(IslandSpace.s)
    }
  }

  /// First-run state: one clear next step, three ways to get words in.
  private var emptyHint: some View {
    VStack(spacing: 8) {
      Text("Start with some words").font(IslandFont.headline).foregroundStyle(IslandInk.primary)
      HStack(spacing: 6) {
        Button { model.pasteFromClipboard() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
          .buttonStyle(IslandAppPillStyle(prominent: true, tint: .orange))
        Button { model.chooseFile() } label: { Label("Open", systemImage: "folder") }
          .buttonStyle(IslandAppPillStyle())
        Button { model.script = L10n.tr(TeleprompterModel.sampleScript) } label: { Label("Sample", systemImage: "sparkles") }
          .buttonStyle(IslandAppPillStyle())
      }
      Text("or just type here").font(.system(size: 12)).foregroundStyle(IslandInk.tertiary)
    }
  }

  private var textSize: some View {
    HStack(spacing: 2) {
      DropletIconButton(symbol: "textformat.size.smaller", help: "Smaller text", size: 28) { model.setFontSize(model.fontSize - 2) }
      DropletIconButton(symbol: "textformat.size.larger", help: "Larger text", size: 28) { model.setFontSize(model.fontSize + 2) }
    }
  }

  private var summary: String {
    let words = TeleprompterMath.wordCount(model.script)
    guard words > 0 else { return L10n.tr("No script yet") }
    let wpm = TeleprompterMath.approximateWordsPerMinute(level: model.speed, fontSize: Double(model.fontSize))
    return L10n.tr("%lld words · ~%lld wpm", words, wpm)
  }

  private var preview: some View {
    DropletCard {
      VStack(spacing: 6) {
        TeleprompterScrollView(model: model, takesFocus: false).frame(maxHeight: .infinity)
        TeleprompterControls(model: model, showsMirror: true, compact: true).padding(.horizontal, IslandSpace.s).padding(.bottom, IslandSpace.s)
      }
    }
  }
}
