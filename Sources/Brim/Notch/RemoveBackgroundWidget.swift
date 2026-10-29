import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Remove Background: drop or choose images and the subject is lifted right away — no extra step.
/// Each image becomes a card showing the cutout on a transparency grid; the footer copies,
/// reveals or clears them.
@MainActor
struct RemoveBackgroundWidgetView: View {
  @ObservedObject var session: RemoveBackgroundSession = .shared
  @State private var targeted = false
  @State private var copied = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Group {
      if session.items.isEmpty { dropZone } else { results }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: session.items.isEmpty)
    .onDrop(of: [UTType.fileURL], isTargeted: $targeted, perform: accept)
  }

  // MARK: Empty

  private var dropZone: some View {
    VStack(spacing: IslandSpace.m) {
      Image(systemName: "wand.and.stars")
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(IslandInk.primary)
        .frame(width: 52, height: 52)
        .background(IslandFill.raised, in: Circle())
      VStack(spacing: IslandSpace.xs) {
        Text("Drop images here").font(IslandFont.title).foregroundStyle(IslandInk.primary)
        Text("The background comes off instantly and is saved as a PNG. Runs on this Mac.")
          .font(IslandFont.label).foregroundStyle(IslandInk.secondary)
          .multilineTextAlignment(.center)
      }
      Button("Choose Images…", action: choose)
        .buttonStyle(IslandPillStyle(prominent: true))
    }
    .padding(IslandSpace.l)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      let shape = RoundedRectangle(cornerRadius: IslandRadius.large, style: .continuous)
      shape.fill(targeted ? Color.accentColor.opacity(0.14) : IslandFill.subtle)
        .overlay(shape.strokeBorder(
          targeted ? Color.accentColor : IslandFill.hover, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
    }
    .animation(NotchMotion.feedback(reduceMotion: reduceMotion), value: targeted)
  }

  // MARK: Results

  private var results: some View {
    VStack(spacing: IslandSpace.m) {
      GeometryReader { proxy in
        ScrollView(.horizontal) {
          HStack(alignment: .top, spacing: IslandSpace.m) {
            ForEach(session.items) { item in
              RemoveBackgroundCard(item: item, session: session)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
          }
          .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .top)
          .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: session.items.map(\.state))
        }
        .scrollIndicators(.never)
        .islandScrollRegion()
      }
      .overlay {
        if targeted {
          RoundedRectangle(cornerRadius: IslandRadius.large, style: .continuous)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        }
      }
      footer
    }
  }

  private var footer: some View {
    HStack(spacing: IslandSpace.s) {
      if session.isWorking { ProgressView().controlSize(.small).scaleEffect(0.8) }
      Text(session.status)
        .font(IslandFont.label.weight(.semibold))
        .foregroundStyle(session.failureCount > 0 ? Color.orange : IslandInk.secondary)
        .lineLimit(1)
        .contentTransition(.numericText())
      Spacer(minLength: 0)
      Button(action: choose) { Label("Add", systemImage: "plus") }
        .buttonStyle(IslandPillStyle(compact: true))
        .help("Add more images")
      if session.results.count == 1, let only = session.results.first {
        Button(copied ? "Copied" : "Copy") { copy(only) }
          .buttonStyle(IslandPillStyle(compact: true))
      }
      if !session.results.isEmpty {
        Button("Show in Finder") { session.reveal() }
          .buttonStyle(IslandPillStyle(compact: true))
      }
      Button("Done") {
        withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { session.clear() }
      }
      .buttonStyle(IslandPillStyle(prominent: true, compact: true))
      .help("Clear and start over")
    }
    .frame(height: 30)
  }

  // MARK: Actions

  private func copy(_ url: URL) {
    session.copy(url)
    copied = true
    Task {
      try? await Task.sleep(for: .seconds(1.5))
      copied = false
    }
  }

  private func choose() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = true
    panel.message = "Choose images to remove their background"
    panel.prompt = "Remove Background"
    NSApp.activate(ignoringOtherApps: true)
    let session = session
    guard panel.runModal() == .OK else {
      NotchShelfController.shared.presentWidget(.removeBackground)
      return
    }
    session.add(panel.urls)
    // The island collapsed while the panel was up; bring the widget back with the run in it.
    NotchShelfController.shared.presentWidget(.removeBackground)
  }

  private func accept(_ providers: [NSItemProvider]) -> Bool {
    guard !providers.isEmpty else { return false }
    let session = session
    for provider in providers {
      _ = provider.loadDataRepresentation(for: .fileURL) { data, _ in
        guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
        Task { @MainActor in session.add([url]) }
      }
    }
    return true
  }
}

/// One image in the run: the original while it works, then the cutout on a transparency grid.
/// Double-click opens the cutout; drag it out to drop it anywhere.
@MainActor
private struct RemoveBackgroundCard: View {
  static let side: CGFloat = 150

  let item: RemoveBackgroundSession.Item
  @ObservedObject var session: RemoveBackgroundSession
  @ObservedObject private var thumbnails = FileThumbnailCache.shared
  @State private var hovered = false
  @State private var copied = false

  var body: some View {
    VStack(spacing: 6) {
      picture
        .frame(width: Self.side, height: Self.side)
        .clipShape(RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous)
            .strokeBorder(IslandFill.hairline, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous))
        .onTapGesture(count: 2) { if let output = item.output { NSWorkspace.shared.open(output) } }
        .overlay(alignment: .bottomTrailing) { if hovered, let output = item.output { actions(output) } }
        .onDrag { item.output.flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider() }
      caption
    }
    .frame(width: Self.side)
    .onHover { hovered = $0 }
    .help(item.output == nil ? item.source.lastPathComponent : "Double-click to open · drag to use it anywhere")
    .accessibilityElement(children: .contain)
    .accessibilityLabel(item.source.lastPathComponent)
  }

  @ViewBuilder private var picture: some View {
    if item.output != nil {
      ZStack {
        TransparencyGrid()
        if let preview = item.preview {
          Image(decorative: preview, scale: 2).resizable().scaledToFit().padding(10)
        } else if let output = item.output {
          Image(nsImage: thumbnails.image(for: output, size: 300)).resizable().scaledToFit().padding(10)
        }
      }
    } else {
      Image(nsImage: thumbnails.image(for: item.source, size: 300)).resizable().scaledToFill()
        .frame(width: Self.side, height: Self.side)
        .opacity(item.state == .working ? 0.45 : 0.3)
        .overlay { badge }
    }
  }

  @ViewBuilder private var badge: some View {
    switch item.state {
    case .working:
      ProgressView().controlSize(.small)
        .padding(10).background(.ultraThinMaterial, in: Circle())
    case .waiting:
      Image(systemName: "clock").font(.system(size: 14, weight: .semibold)).foregroundStyle(IslandInk.secondary)
    case .failed:
      Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 18)).foregroundStyle(Color.orange)
    case .done:
      EmptyView()
    }
  }

  private var caption: some View {
    VStack(spacing: 1) {
      Text(item.output?.lastPathComponent ?? item.source.lastPathComponent)
        .font(IslandFont.caption.weight(.semibold)).foregroundStyle(IslandInk.primary.opacity(0.85))
        .lineLimit(1).truncationMode(.middle)
      Text(detail).font(IslandFont.caption)
        .foregroundStyle(isFailed ? Color.orange : IslandInk.tertiary)
        .lineLimit(1)
    }
  }

  private var isFailed: Bool { if case .failed = item.state { true } else { false } }

  private var detail: String {
    switch item.state {
    case .waiting: "Waiting…"
    case .working: "Removing background…"
    case .done(let url): "PNG · \(TransformSizeSummary.bytes(TransformEngine.fileSize(url)))"
    case .failed(let message): message
    }
  }

  private func actions(_ output: URL) -> some View {
    HStack(spacing: 4) {
      cardButton(copied ? "checkmark" : "doc.on.doc", label: "Copy") {
        session.copy(output)
        copied = true
        Task {
          try? await Task.sleep(for: .seconds(1.5))
          copied = false
        }
      }
      cardButton("folder", label: "Show in Finder") { session.reveal([output]) }
    }
    .padding(6)
    .transition(.opacity)
  }

  private func cardButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
        .frame(width: 26, height: 26)
        .background(Color.black.opacity(0.6), in: Circle())
        .contentShape(Circle())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.88))
    .help(label)
    .accessibilityLabel(label)
  }
}

/// The checkerboard Preview and Photos draw behind transparent pixels.
private struct TransparencyGrid: View {
  var cell: CGFloat = 9

  var body: some View {
    Canvas { context, size in
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.06)))
      let columns = Int(ceil(size.width / cell)), rows = Int(ceil(size.height / cell))
      for row in 0..<rows {
        for column in 0..<columns where (row + column).isMultiple(of: 2) {
          let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
          context.fill(Path(rect), with: .color(.white.opacity(0.12)))
        }
      }
    }
  }
}
