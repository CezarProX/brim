import AppKit
import SwiftUI

/// Screenshots keep their ShelfStore identity; clipboard content has separate bounded storage.
enum LibraryItem: Identifiable {
  case screenshot(ShelfEntry), clipboard(ClipboardEntry)

  var id: String {
    switch self {
    case .screenshot(let entry): return "capture-\(entry.id)"
    case .clipboard(let entry): return "clipboard-\(entry.id)"
    }
  }
  var date: Date {
    switch self {
    case .screenshot(let entry): return entry.date
    case .clipboard(let entry): return entry.date
    }
  }
  var isScreenshot: Bool {
    if case .screenshot = self { return true }
    return false
  }
  var clipboardEntry: ClipboardEntry? {
    if case .clipboard(let entry) = self { return entry }
    return nil
  }
  var isPinned: Bool { clipboardEntry?.isPinned ?? false }
  var ocrText: String? { clipboardEntry?.ocrText }
  var kind: ClipboardEntry.Kind { clipboardEntry?.kind ?? .image }
  var tag: ClipboardTag? { clipboardEntry?.tag }
  var title: String {
    switch self {
    case .screenshot: return "Screenshot"
    case .clipboard(let entry): return entry.title
    }
  }
  var kindTitle: String {
    if isScreenshot { return "Screenshot" }
    switch kind {
    case .image: return "Image"
    case .text:
      let text = clipboardEntry?.text ?? ""
      if ClipboardClassifier.isEmail(text) { return "Email" }
      return ClipboardClassifier.isCode(text) ? "Code" : "Text"
    case .link: return "Link"
    case .color: return "Color"
    case .file: return "File"
    }
  }
  var searchText: String {
    switch self {
    case .screenshot(let entry): return "Screenshot \(entry.pixelSize) \(entry.date.formatted())"
    case .clipboard(let entry):
      return
        "\(entry.text ?? "Copied image") \(entry.ocrText ?? "") \(entry.pixelSize ?? "") \(entry.tag?.title ?? "") \(entry.date.formatted())"
    }
  }
}

/// Clipboard card: a tinted header with kind, age and source app,
/// a content-aware preview, and a detail footer. Actions surface on hover.
struct ClipboardCard<Preview: View>: View {
  let item: LibraryItem
  let detail: String
  let onCopy: () -> Void
  let onTogglePin: (() -> Void)?
  /// Keyboard cursor / multi-select marker; `.none` leaves the card exactly as it was.
  var mark: ClipboardCardMark = .none
  @ViewBuilder let preview: () -> Preview
  @State private var hovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var headerTint: Color {
    if let tag = item.tag { return Color(nsColor: tag.color) }
    return .white
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      preview()
        .frame(maxWidth: .infinity).frame(height: 104).clipped()
        .blur(radius: item.clipboardEntry?.isBlurred == true && !hovered ? 9 : 0)
        .overlay {
          if item.clipboardEntry?.isBlurred == true && !hovered {
            Image(systemName: "eye.slash.fill").font(.system(size: 14, weight: .semibold))
              .foregroundStyle(IslandInk.secondary)
          }
        }
      footer
    }
    .background(
      hovered ? IslandFill.raised : IslandFill.subtle,
      in: RoundedRectangle(cornerRadius: IslandRadius.medium - 2, style: .continuous)
    )
    .clipShape(RoundedRectangle(cornerRadius: IslandRadius.medium - 2, style: .continuous))
    .overlay {
      // The card under the pointer is outlined in white.
      RoundedRectangle(cornerRadius: IslandRadius.medium - 2, style: .continuous)
        .strokeBorder(.white.opacity(hovered ? 0.85 : 0.06), lineWidth: hovered ? 2 : 1)
    }
    .overlay { markOverlay }
    .scaleEffect(hovered && !reduceMotion ? 1.02 : 1)
    .onHover { hovered = $0 }
    .animation(NotchMotion.press(reduceMotion: reduceMotion), value: hovered)
  }

  @ViewBuilder private var markOverlay: some View {
    let shape = RoundedRectangle(cornerRadius: IslandRadius.medium - 2, style: .continuous)
    switch mark {
    case .none: EmptyView()
    case .cursor: shape.strokeBorder(.white.opacity(0.85), lineWidth: 2).allowsHitTesting(false)
    case .selected(let position):
      shape.strokeBorder(Color.blue, lineWidth: 2).allowsHitTesting(false)
        .overlay(alignment: .topTrailing) {
          Text("\(position)").font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundStyle(.white)
            .frame(width: 18, height: 18).background(Color.blue, in: Circle())
            .padding(.top, 42).padding(.trailing, 7).allowsHitTesting(false)
            .accessibilityLabel("Selected \(position)")
        }
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 6) {
      VStack(alignment: .leading, spacing: 0) {
        Text(item.kindTitle).font(IslandFont.label.weight(.bold)).lineLimit(1).minimumScaleFactor(0.8)
        TimelineView(.everyMinute) { context in
          Text(Self.age(of: item.date, now: context.date))
            .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
        }
      }
      Spacer(minLength: 2)
      if let bundle = item.clipboardEntry?.sourceApp,
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
      {
        // The source app's icon is tucked over the header's corner.
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
          .frame(width: 30, height: 30)
          .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
          .offset(x: 4, y: -2)
          .help(FileManager.default.displayName(atPath: url.path))
      } else if item.isScreenshot {
        Image(systemName: "camera.viewfinder").font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white.opacity(0.85))
      }
    }
    .padding(.horizontal, 9).padding(.top, 6).frame(height: 36, alignment: .top)
    .background(headerFill)
  }

  /// Tagged items take their tag's color; everything else gets a quiet dark band.
  private var headerFill: some ShapeStyle {
    item.tag == nil ? AnyShapeStyle(Color.white.opacity(0.09)) : AnyShapeStyle(headerTint.opacity(0.62))
  }

  static func age(of date: Date, now: Date = .now) -> String {
    guard now.timeIntervalSince(date) >= 60 else { return "Just now" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: now)
  }

  private var footer: some View {
    HStack(spacing: 6) {
      Text(detail).lineLimit(1)
      Spacer(minLength: 1)
      if hovered {
        Button(action: onCopy) { Image(systemName: "doc.on.doc") }
          .buttonStyle(IslandPressStyle(pressedScale: 0.8))
          .help("Copy item").accessibilityLabel("Copy \(item.title)")
          .transition(.scale.combined(with: .opacity))
      }
      if let togglePin = onTogglePin, item.isPinned || hovered {
        Button(action: togglePin) {
          Image(systemName: item.isPinned ? "star.fill" : "star")
            .foregroundStyle(item.isPinned ? Color.yellow : IslandInk.secondary)
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(IslandPressStyle(pressedScale: 0.8))
        .help(item.isPinned ? "Remove from favorites" : "Favorite")
        .accessibilityLabel(item.isPinned ? "Unfavorite \(item.title)" : "Favorite \(item.title)")
        .transition(.scale.combined(with: .opacity))
      }
      if let copies = item.clipboardEntry?.copies {
        Label("\(copies)", systemImage: "line.3.horizontal")
          .labelStyle(.titleAndIcon).monospacedDigit()
          .help(copies == 1 ? "Copied once" : "Copied \(copies) times")
      }
    }
    .font(IslandFont.caption).foregroundStyle(IslandInk.secondary)
    .padding(.horizontal, 9).frame(height: 26)
  }
}

/// How a library card is marked for keyboard and multi-select use.
enum ClipboardCardMark: Equatable {
  case none, cursor
  /// Selected; the number is its place in the paste order.
  case selected(Int)
}

/// Edits a copied text, link or color in place.
struct ClipboardEditPopover: View {
  @State var text: String
  let save: (String) -> Void

  var body: some View {
    VStack(alignment: .trailing, spacing: 10) {
      TextEditor(text: $text)
        .font(.system(size: 12, design: .monospaced))
        .frame(width: 280, height: 120)
        .scrollContentBackground(.hidden)
        .padding(6)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
      Button("Save") { save(text) }.keyboardShortcut(.defaultAction)
    }
    .padding(12)
  }
}
