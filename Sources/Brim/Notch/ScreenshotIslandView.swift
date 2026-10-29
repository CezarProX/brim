import AppKit
import SwiftUI

/// The Screenshot app: three ways to grab the screen, and the captures already taken.
/// Nothing happens until a mode is chosen, so the island stays open to show what was captured last.
@MainActor
struct ScreenshotIslandView: View {
  @ObservedObject var shelf: ShelfStore = .shared
  var shelfEnabled: () -> Bool = { AppSettings.shared.notchShelfEnabled }
  var shortcut: (ShortcutID) -> String = { ShortcutStore.binding($0).display }
  /// Closes the island before the screen is frozen, so it is not part of the picture.
  var beforeCapture: () -> Void = { NotchShelfController.shared.dismissShelf() }
  var startArea: () -> Void = { CaptureCoordinator.shared.startCapture() }
  var startText: () -> Void = { Task { await TextCaptureModel.shared.captureArea() } }
  var startRecording: () -> Void = { RecordingController.shared.showBar() }

  @State private var shelfOn = true
  @State private var copiedID: UUID?

  var body: some View {
    VStack(alignment: .leading, spacing: IslandSpace.m) {
      HStack(spacing: IslandSpace.s) {
        mode("Capture Area", "Drag to select", "camera.viewfinder", .capture, prominent: true, action: startArea)
        mode("Copy Text", "Read text on screen", "text.viewfinder", .textCapture, action: startText)
        mode("Record Screen", "Video with audio", "record.circle", .recordScreen, action: startRecording)
      }
      recent
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .onAppear { shelfOn = shelfEnabled() }
  }

  private func mode(
    _ title: LocalizedStringKey, _ detail: LocalizedStringKey, _ symbol: String, _ id: ShortcutID,
    prominent: Bool = false, action: @escaping () -> Void
  ) -> some View {
    Button {
      beforeCapture()
      action()
    } label: {
      HStack(spacing: 10) {
        Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
          .foregroundStyle(prominent ? Color.black : IslandInk.primary)
          .frame(width: 32, height: 32)
          .background(prominent ? Color.white : IslandFill.raised, in: Circle())
        VStack(alignment: .leading, spacing: 1) {
          Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(IslandInk.primary).lineLimit(1)
          Text(shortcut(id) == "Not set" ? detail : LocalizedStringKey(shortcut(id)))
            .font(.system(size: 12)).foregroundStyle(IslandInk.secondary).lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 10)
      .frame(maxWidth: .infinity, minHeight: 52)
      .glassCard(radius: IslandRadius.medium)
      .contentShape(RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous))
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.96))
    .help(detail)
  }

  // MARK: Recent

  @ViewBuilder private var recent: some View {
    VStack(alignment: .leading, spacing: IslandSpace.s) {
      HStack {
        Text("Recent captures").font(.system(size: 12, weight: .semibold)).foregroundStyle(IslandInk.secondary)
        Spacer(minLength: 0)
        if !shelf.entries.isEmpty {
          Text("\(shelf.entries.count)").font(.system(size: 12)).foregroundStyle(IslandInk.tertiary)
        }
      }
      if !shelfOn {
        note("symbol", "Recent captures are turned off.", button: "Turn On") {
          AppSettings.shared.notchShelfEnabled = true
          shelfOn = true
        }
      } else if shelf.entries.isEmpty {
        note("photo.on.rectangle.angled", "Your next screenshot shows up here, ready to drag into any app.")
      } else {
        strip
      }
    }
  }

  private func note(_ symbol: String, _ text: LocalizedStringKey, button: LocalizedStringKey? = nil, action: @escaping () -> Void = {})
    -> some View
  {
    HStack(spacing: IslandSpace.m) {
      Image(systemName: symbol == "symbol" ? "eye.slash" : symbol).font(.system(size: 18))
        .foregroundStyle(IslandInk.tertiary)
      Text(text).font(.system(size: 12)).foregroundStyle(IslandInk.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
      if let button { Button(button, action: action).buttonStyle(CaptureAppButtonStyle(prominent: true)) }
    }
    .padding(.horizontal, IslandSpace.m)
    .frame(maxWidth: .infinity, minHeight: 64)
    .glassCard(radius: IslandRadius.medium)
  }

  private var strip: some View {
    ScrollView(.horizontal) {
      HStack(spacing: IslandSpace.s) {
        ForEach(shelf.entries.prefix(12)) { entry in
          ScreenshotThumb(entry: entry, shelf: shelf, copied: copiedID == entry.id) { copy(entry) }
        }
      }
    }
    .scrollIndicators(.never)
    .islandScrollRegion()
  }

  private func copy(_ entry: ShelfEntry) {
    guard let image = shelf.image(for: entry) else { return }
    CaptureActions.copyToClipboard(image)
    copiedID = entry.id
    Task {
      try? await Task.sleep(for: .seconds(1.5))
      if copiedID == entry.id { copiedID = nil }
    }
  }
}

/// One recent capture. Hover shows copy, edit and save; the picture itself drags out as a file.
private struct ScreenshotThumb: View {
  let entry: ShelfEntry
  let shelf: ShelfStore
  let copied: Bool
  let copy: () -> Void
  @State private var hovered = false

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: IslandRadius.small, style: .continuous).fill(IslandFill.subtle)
      if let image = shelf.thumbnail(for: entry) {
        Image(nsImage: image).resizable().scaledToFill()
      }
    }
    .frame(width: 112, height: 72)
    .clipShape(RoundedRectangle(cornerRadius: IslandRadius.small, style: .continuous))
    .overlay { RoundedRectangle(cornerRadius: IslandRadius.small, style: .continuous).strokeBorder(IslandFill.hairline) }
    .overlay {
      if hovered || copied {
        ZStack {
          Color.black.opacity(0.55)
          HStack(spacing: 6) {
            chip(copied ? "checkmark" : "doc.on.doc", "Copy", copy)
            chip("pencil.tip.crop.circle", "Edit") { NotchShelfController.shared.edit(entry) }
            chip("square.and.arrow.down", "Save") { NotchShelfController.shared.save(entry) }
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: IslandRadius.small, style: .continuous))
        .transition(.opacity)
      }
    }
    .onHover { hovered = $0 }
    .onDrag { NSItemProvider(contentsOf: shelf.fileURL(for: entry)) ?? NSItemProvider() }
    .help(entry.pixelSize)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Screenshot \(entry.pixelSize)")
  }

  private func chip(_ symbol: String, _ label: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
        .frame(width: 30, height: 30).background(Color.white.opacity(0.2), in: Circle()).contentShape(Circle())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.88))
    .help(label)
    .accessibilityLabel(label)
  }
}
