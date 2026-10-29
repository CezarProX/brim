import AppKit
import SwiftUI

/// A progress ring that turns into a check or a warning when its file is done.
struct TransformRing: View {
  let state: TransformUnitState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      Circle().stroke(IslandFill.hover, lineWidth: 3)
      Circle().trim(from: 0, to: progress).stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        .rotationEffect(.degrees(-90))
      Image(systemName: glyph).font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
        .contentTransition(.symbolEffect(.replace))
    }
    .frame(width: 26, height: 26)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: progress)
  }

  private var progress: Double {
    switch state {
    case .waiting, .cancelled: 0
    case .running(let value): max(0.04, value)
    case .done, .skipped, .failed: 1
    }
  }

  private var tint: Color {
    switch state {
    case .done: .green
    case .failed: .orange
    case .skipped, .cancelled, .waiting: IslandInk.tertiary
    case .running: .blue
    }
  }

  private var glyph: String {
    switch state {
    case .done: "checkmark"
    case .failed: "exclamationmark"
    case .skipped: "equal"
    case .cancelled: "xmark"
    case .waiting: "clock"
    case .running: "circle.fill"
    }
  }
}

struct TransformResultRow: View {
  let row: TransformPanelModel.Row

  var body: some View {
    HStack(spacing: IslandSpace.s) {
      TransformRing(state: row.state)
      VStack(alignment: .leading, spacing: 1) {
        Text(row.title).font(IslandFont.label.weight(.semibold)).lineLimit(1).truncationMode(.middle)
        Text(detail).font(IslandFont.caption).foregroundStyle(detailTint).lineLimit(1)
          .contentTransition(.numericText())
      }
      Spacer(minLength: 0)
      if case .done(let outcome) = row.state, let first = outcome.outputs.first {
        Button { NSWorkspace.shared.activateFileViewerSelecting(outcome.outputs) } label: {
          Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.plain).foregroundStyle(IslandInk.secondary).help("Show \(first.lastPathComponent) in Finder")
      }
    }
    .padding(.horizontal, IslandSpace.s).frame(height: 38)
    .glassCard(radius: 11)
  }

  private var detail: String {
    switch row.state {
    case .waiting: "Waiting"
    case .running(let value): "\(Int(value * 100))%"
    case .done(let outcome):
      outcome.outputs.count > 1 ? "\(outcome.outputs.count) files · \(outcome.summary)" : outcome.summary
    case .skipped(let reason): reason
    case .failed(let message): message
    case .cancelled: "Cancelled"
    }
  }

  private var detailTint: Color {
    switch row.state {
    case .failed: .orange
    case .done: IslandInk.secondary
    default: IslandInk.tertiary
    }
  }
}

/// The Transform accent: the indigo of the selected operation tile.
enum TransformStyle {
  static let accent = Color(red: 0.42, green: 0.42, blue: 0.97)
  static let tile = Color.white.opacity(0.09)
  static let group = Color.white.opacity(0.07)
  static let tileSize = CGSize(width: 70, height: 36)
}

/// A file in the panel: a wide rounded thumbnail with its name and size beneath.
struct TransformFileTile: View {
  let url: URL
  let removable: Bool
  let remove: () -> Void
  @ObservedObject private var thumbnails = FileThumbnailCache.shared
  @State private var hovered = false

  var body: some View {
    VStack(spacing: 3) {
      Image(nsImage: thumbnails.image(for: url, size: 128)).resizable().scaledToFill()
        .frame(width: TransformStyle.tileSize.width, height: TransformStyle.tileSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topTrailing) {
          if removable && hovered {
            Button(action: remove) {
              Image(systemName: "xmark.circle.fill").font(.system(size: 13))
                .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.7))
            }
            .buttonStyle(.plain).offset(x: 5, y: -5)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("Remove \(url.lastPathComponent)")
          }
        }
      Text(url.lastPathComponent).font(.system(size: 10, weight: .semibold)).foregroundStyle(IslandInk.secondary)
        .lineLimit(1).truncationMode(.middle)
      Text(TransformSizeSummary.bytes(TransformEngine.fileSize(url))).font(.system(size: 10, weight: .medium))
        .foregroundStyle(IslandInk.tertiary)
    }
    .frame(width: TransformStyle.tileSize.width + 6)
    .onHover { hovered = $0 }
    .accessibilityElement(children: .combine)
  }
}

/// The "+ Add" tile beside the files.
struct TransformAddTile: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 3) {
        Image(systemName: "plus").font(.system(size: 14, weight: .medium))
          .foregroundStyle(IslandInk.secondary)
          .frame(width: TransformStyle.tileSize.width, height: TransformStyle.tileSize.height)
          .background(TransformStyle.tile, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        Text("Add").font(.system(size: 10, weight: .semibold)).foregroundStyle(IslandInk.secondary)
      }
      .frame(width: TransformStyle.tileSize.width + 6)
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.93))
    .accessibilityLabel("Add files")
  }
}

/// An operation: dark rounded tile with its icon, the label beneath; selected fills indigo.
struct TransformOperationTile: View {
  let operation: TransformOperation
  let selected: Bool
  let action: () -> Void
  @State private var hovered = false

  var body: some View {
    Button(action: action) {
      VStack(spacing: 5) {
        Image(systemName: operation.symbol).font(.system(size: 14, weight: .semibold))
          .foregroundStyle(selected ? Color.white : IslandInk.primary.opacity(0.85))
          .frame(maxWidth: .infinity).frame(height: TransformStyle.tileSize.height)
          .background(
            selected ? TransformStyle.accent : (hovered ? Color.white.opacity(0.14) : TransformStyle.tile),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        Text(operation.title).font(.system(size: 10, weight: .semibold))
          .foregroundStyle(selected ? IslandInk.primary : IslandInk.secondary)
          .multilineTextAlignment(.center).lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
          .frame(height: 26, alignment: .top)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.93))
    .onHover { hovered = $0 }
    .accessibilityLabel(operation.title)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// One labelled row in the options group: title on the left, its control on the right.
struct TransformOptionLine<Control: View>: View {
  let title: String
  @ViewBuilder let control: () -> Control

  var body: some View {
    HStack(spacing: IslandSpace.s) {
      Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(IslandInk.primary.opacity(0.85))
      Spacer(minLength: IslandSpace.s)
      control()
    }
    .frame(height: 28)
  }
}
