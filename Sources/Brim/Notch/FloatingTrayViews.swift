import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The tiles that appear beside the pointer while shaking a file drag.
struct QuickActionsView: View {
  let targets: [DropTarget]
  let size: CGSize
  let perform: (DropTarget, [URL]) -> Void
  @State private var appeared = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    // The shake panel: two columns of tiles on a dark glass card; an odd last tile spans the row.
    Grid(horizontalSpacing: FloatingTrayLayout.tileSpacing, verticalSpacing: FloatingTrayLayout.tileSpacing) {
      ForEach(Array(FloatingTrayLayout.rows(targets).enumerated()), id: \.offset) { _, row in
        GridRow {
          ForEach(row) { target in
            DropTargetTile(target: target, large: true, floating: true) { urls in perform(target, urls) }
              .frame(height: FloatingTrayLayout.tileHeight)
              .gridCellColumns(row.count == 1 ? 2 : 1)
          }
        }
      }
    }
    .padding(FloatingTrayLayout.padding)
    .frame(width: size.width, height: size.height, alignment: .top)
    .glassPanel(radius: FloatingTrayLayout.cornerRadius, shadow: false)
    .scaleEffect(appeared || reduceMotion ? 1 : 0.8)
    .opacity(appeared ? 1 : 0)
    .animation(.spring(duration: 0.35, bounce: 0.35), value: appeared)
    .onAppear { appeared = true }
    .foregroundStyle(.white)
    .preferredColorScheme(.dark)
  }
}

/// The floating tray: a grab handle, the count and size, a switcher when several are open,
/// grid or list, and every file action on right-click.
struct BasketView: View {
  @ObservedObject var model: BasketModel
  @ObservedObject var registry: FloatingTrayRegistry
  let number: Int
  let close: () -> Void
  @ObservedObject private var thumbnails = FileThumbnailCache.shared
  @State private var targeted = false
  @State private var appeared = false
  @State private var asList = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var bytes: Int64 {
    model.urls.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
  }

  private var showsSwitcher: Bool { registry.tabs.count > 1 && AppSettings.shared.floatingTraySwitcher }

  var body: some View {
    VStack(alignment: .leading, spacing: IslandSpace.m) {
      Capsule().fill(IslandFill.hover).frame(width: 36, height: 4).frame(maxWidth: .infinity)
      header
      content
    }
    .padding(.horizontal, IslandSpace.l).padding(.vertical, IslandSpace.s)
    .frame(width: FloatingTrayLayout.size.width, height: FloatingTrayLayout.size.height)
    .glassPanel(radius: 28, shadow: false)
    .overlay {
      if targeted {
        RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.blue, lineWidth: 2)
      }
    }
    .foregroundStyle(.white)
    .scaleEffect(appeared || reduceMotion ? (targeted ? 1.03 : 1) : 0.85)
    .animation(.spring(duration: 0.35, bounce: 0.35), value: appeared)
    .animation(NotchMotion.press(reduceMotion: reduceMotion), value: targeted)
    .onDrop(of: FileDropLoader.types, isTargeted: $targeted, perform: model.drop)
    .onHover { model.isHovered = $0 }
    .onAppear { appeared = true }
    .preferredColorScheme(.dark)
  }

  private var header: some View {
    HStack(spacing: IslandSpace.s) {
      IslandGlyphButton(symbol: "xmark", label: "Close tray", size: 26, action: close)
      VStack(alignment: .leading, spacing: 0) {
        Text(model.urls.isEmpty ? "Tray" : model.urls.count == 1 ? "1 File" : "\(model.urls.count) Files")
          .font(IslandFont.title).contentTransition(.numericText())
        Text(model.urls.isEmpty ? "Drop files to hold them" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
          .font(IslandFont.label).foregroundStyle(IslandInk.tertiary)
      }
      Spacer()
      if showsSwitcher { TraySwitcher(registry: registry, current: model.id) }
      IslandGlyphButton(symbol: asList ? "list.bullet" : "square.grid.2x2.fill", label: asList ? "Show as grid" : "Show as list", size: 26) {
        asList.toggle()
      }
    }
  }

  @ViewBuilder private var content: some View {
    if model.urls.isEmpty {
      RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous)
        .strokeBorder(IslandFill.hover, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        .overlay { Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 20)).foregroundStyle(IslandInk.tertiary) }
        .frame(maxHeight: .infinity)
    } else {
      fileList
    }
  }

  private var fileList: some View {
    ScrollView(asList ? .vertical : .horizontal) {
      Group {
        if asList {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(model.urls, id: \.self) { url in
              HStack(spacing: 8) {
                Image(nsImage: thumbnails.image(for: url)).resizable().scaledToFit().frame(width: 22, height: 22)
                Text(url.lastPathComponent).font(IslandFont.label).lineLimit(1).truncationMode(.middle)
                Spacer()
              }
              .modifier(BasketItem(url: url, model: model))
            }
          }
        } else {
          HStack(spacing: IslandSpace.s) {
            ForEach(model.urls, id: \.self) { url in
              VStack(spacing: 4) {
                Image(nsImage: thumbnails.image(for: url)).resizable().scaledToFit().frame(width: 60, height: 56)
                Text(url.lastPathComponent).font(IslandFont.caption.weight(.semibold)).lineLimit(1)
                  .truncationMode(.middle).frame(width: 70)
              }
              .modifier(BasketItem(url: url, model: model))
            }
          }
        }
      }
      .animation(NotchMotion.press(reduceMotion: reduceMotion), value: model.urls)
    }
    .scrollIndicators(.hidden)
    .frame(maxHeight: .infinity)
  }
}

/// Numbered pills that jump between open trays.
private struct TraySwitcher: View {
  @ObservedObject var registry: FloatingTrayRegistry
  let current: UUID

  var body: some View {
    HStack(spacing: 3) {
      ForEach(registry.tabs) { tab in
        Button { registry.onSelect(tab.id) } label: {
          Text("\(tab.number)").font(IslandFont.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(tab.id == current ? Color.black : IslandInk.secondary)
            .frame(width: 18, height: 18)
            .background(tab.id == current ? Color.white : IslandFill.raised, in: Circle())
            .overlay(alignment: .topTrailing) {
              if tab.count > 0 && tab.id != current {
                Circle().fill(Color.blue).frame(width: 6, height: 6).offset(x: 2, y: -2)
              }
            }
        }
        .buttonStyle(.plain)
        .help("Tray \(tab.number)")
        .accessibilityLabel("Tray \(tab.number), \(tab.count) files")
      }
    }
  }
}

/// Drag-out and the full right-click menu for a tray item.
struct BasketItem: ViewModifier {
  let url: URL
  @ObservedObject var model: BasketModel

  func body(content: Content) -> some View {
    content
      .contentShape(Rectangle())
      .onDrag {
        if AppSettings.shared.trayRemoveAfterDragOut {
          TrayDragOut.trackRelease { point in
            if DragOutPolicy.shouldRemove(
              enabled: true, releasedOnTray: TrayDragOut.isOverTray(point), pinned: false)
            { model.remove(url) }
          }
        }
        return TrayDragOut.provider(for: url, protect: AppSettings.shared.trayProtectOriginals)
      }
      .contextMenu {
        Button("Copy") { FileDropActions.copy([url]) }
        Button("Open") { NSWorkspace.shared.open(url) }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        Button("AirDrop") { FileDropActions.airDrop([url]) }
        Button("Transform…") { NotchShelfController.shared.presentConvert([url]) }
        Button("Create ZIP") { FileDropActions.zip([url]) }
        Button("Move to Shelf") {
          FileTrayStore.shared.add([url])
          model.remove(url)
        }
        Divider()
        Button("Remove from Tray", role: .destructive) { model.remove(url) }
      }
      .transition(.scale(scale: 0.6).combined(with: .opacity))
  }
}
