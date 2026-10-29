import AppKit
import SwiftUI

/// The Transform panel shown in the island after files land on Transform, laid out as follows:
/// a "Transform / file, size" header beside the camera, the files with "+ Add", a grid of operation
/// tiles, an options group (Format, Save to) and one full-width action button.
struct TransformPanelView: View {
  /// Height the island reserves for this panel under the camera band.
  static let preferredHeight: CGFloat = 404
  /// Width of the island while the panel is open.
  static let preferredWidth: CGFloat = 502

  /// Once it runs, the panel only needs its header, the result rows and the footer: the island
  /// shrinks to them instead of keeping the configure layout's height with an empty middle.
  static func resultsHeight(rows: Int) -> CGFloat {
    let visible = CGFloat(min(max(rows, 1), 6))
    return min(preferredHeight, 112 + visible * 38 + (visible - 1) * 6)
  }

  @StateObject private var model: TransformPanelModel
  let close: () -> Void
  @State private var savingPreset = false
  @State private var presetName = ""
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(model: TransformPanelModel, close: @escaping () -> Void) {
    _model = StateObject(wrappedValue: model)
    self.close = close
  }

  /// Opens on these files, preselecting the operation a Transform ▸ menu item asked for.
  init(urls: [URL], close: @escaping () -> Void) {
    _model = StateObject(wrappedValue: TransformLaunchRequest.shared.makeModel(for: urls))
    self.close = close
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Group {
        switch model.phase {
        case .configure: configure
        case .running, .finished: results
        }
      }
      .frame(maxHeight: .infinity, alignment: .top)
      .transition(.opacity)
      footer
    }
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: model.phase)
    .preference(key: TransformPanelHeightKey.self,
                value: model.phase == .configure ? Self.preferredHeight : Self.resultsHeight(rows: model.rows.count))
    .onDisappear { if model.phase == .running { model.cancel() } }
  }

  // MARK: Header

  private var header: some View {
    HStack(spacing: 10) {
      Image(systemName: "arrow.triangle.2.circlepath.doc.on.clipboard")
        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
        .frame(width: 30, height: 30)
        .background(
          LinearGradient(colors: [TransformStyle.accent, TransformStyle.accent.opacity(0.7)], startPoint: .top, endPoint: .bottom),
          in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      VStack(alignment: .leading, spacing: 1) {
        Text("Transform").font(.system(size: 13, weight: .semibold)).foregroundStyle(IslandInk.primary)
        Text(subtitle).font(.system(size: 11, weight: .medium)).foregroundStyle(IslandInk.secondary)
          .lineLimit(1).truncationMode(.middle)
      }
      .frame(maxWidth: 150, alignment: .leading)
      Spacer(minLength: 0)
      if model.phase == .configure { presetsMenu }
      IslandGlyphButton(symbol: "xmark", label: "Close Transform", size: 26, action: close)
    }
    .frame(height: 36)
  }

  private var subtitle: String {
    let bytes = model.files.reduce(Int64(0)) { $0 + TransformEngine.fileSize($1) }
    let size = TransformSizeSummary.bytes(bytes)
    if model.files.count == 1, let first = model.files.first { return "\(first.lastPathComponent), \(size)" }
    return "\(model.files.count) files, \(size)"
  }

  // MARK: Configure

  private var configure: some View {
    VStack(alignment: .leading, spacing: 12) {
      files
      operations
      optionsGroup
    }
    .padding(.top, 8)
  }

  private var files: some View {
    ScrollView(.horizontal) {
      HStack(alignment: .top, spacing: 8) {
        ForEach(model.files, id: \.self) { url in
          TransformFileTile(url: url, removable: model.files.count > 1) {
            withAnimation(NotchMotion.press(reduceMotion: reduceMotion)) { model.remove(url) }
          }
        }
        TransformAddTile(action: addFiles)
      }
      .padding(.top, 5)
    }
    .scrollIndicators(.hidden)
    .frame(height: 66)
  }

  private var operations: some View {
    let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)
    return ScrollView(.vertical) {
      LazyVGrid(columns: columns, spacing: 8) {
        ForEach(model.available) { operation in
          TransformOperationTile(operation: operation, selected: model.operation == operation) {
            withAnimation(NotchMotion.press(reduceMotion: reduceMotion)) { model.select(operation) }
          }
        }
      }
    }
    .scrollIndicators(.hidden)
    .frame(height: 2 * 67 + 8)
  }

  private var optionsGroup: some View {
    VStack(spacing: 2) {
      TransformOptionLine(title: optionsTitle) {
        TransformOptionsRow(model: model).fixedSize()
      }
      TransformOptionLine(title: "Save to") {
        OptionMenu(title: "", value: model.policy.destination.rawValue, choices: TransformDestination.allCases,
                   label: { $0.rawValue }) { model.setDestination($0) }
      }
    }
    .padding(.horizontal, 12).padding(.vertical, 6)
    .background(TransformStyle.group, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var optionsTitle: String {
    switch model.operation {
    case .convert: "Format"
    case .compress: "Quality"
    case .resize: "Size"
    case .rotate: "Angle"
    case .trim: "Range"
    case .rename: "Name"
    default: "Options"
    }
  }

  private func addFiles() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK else { return }
    withAnimation(NotchMotion.press(reduceMotion: reduceMotion)) { model.add(panel.urls) }
  }

  private var presetsMenu: some View {
    Menu {
      ForEach(model.presets) { preset in
        Button { model.apply(preset) } label: { Label(preset.name, systemImage: preset.symbol) }
      }
      Divider()
      Button("Save Current as Preset…") {
        presetName = ""
        savingPreset = true
      }
      let mine = model.presets.filter { !$0.isBuiltIn }
      if !mine.isEmpty {
        Menu("Delete Preset") {
          ForEach(mine) { preset in Button(preset.name, role: .destructive) { model.deletePreset(preset) } }
        }
      }
    } label: {
      Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold))
        .foregroundStyle(IslandInk.secondary)
        .frame(width: 26, height: 26).background(IslandFill.subtle, in: Circle())
    }
    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    .help("Presets")
    .popover(isPresented: $savingPreset) {
      HStack {
        TextField("Preset name", text: $presetName).textFieldStyle(.roundedBorder).frame(width: 160)
          .onSubmit(savePreset)
        Button("Save", action: savePreset).keyboardShortcut(.defaultAction)
      }
      .padding(12)
    }
  }

  private func savePreset() {
    model.savePreset(named: presetName)
    savingPreset = false
  }

  // MARK: Results

  private var results: some View {
    ScrollView {
      VStack(spacing: 6) {
        ForEach(model.rows) { row in TransformResultRow(row: row) }
      }
      .padding(.top, 10)
    }
    .scrollIndicators(.hidden)
  }

  // MARK: Footer

  @ViewBuilder private var footer: some View {
    Group {
      switch model.phase {
      case .configure:
        actionButton(model.operation.title, enabled: model.canRun) { model.run() }
          .keyboardShortcut(.defaultAction)
      case .running:
        HStack(spacing: IslandSpace.s) {
          ProgressView(value: model.overallProgress).tint(TransformStyle.accent)
          Button("Cancel") { model.cancel() }.buttonStyle(IslandPillStyle(compact: true))
        }
      case .finished:
        finishedFooter
      }
    }
    .frame(height: 38)
    .padding(.top, 10)
  }

  private var finishedFooter: some View {
    HStack(spacing: IslandSpace.s) {
      // One file: its row already says how it went, so the footer doesn't repeat it.
      if model.rows.count > 1 || model.failureCount > 0 || model.results.isEmpty {
        Text(finishedSummary).font(IslandFont.label.weight(.semibold))
          .foregroundStyle(model.failureCount > 0 ? Color.orange : IslandInk.secondary).lineLimit(1)
          .contentTransition(.numericText())
      }
      Spacer()
      if !model.results.isEmpty {
        Button("Show in Finder") { model.reveal() }.buttonStyle(IslandPillStyle(compact: true))
        Button("Keep in Tray") {
          model.keepInTray()
          close()
        }
        .buttonStyle(IslandPillStyle(compact: true))
      }
      Button("Again") { model.again() }.buttonStyle(IslandPillStyle(compact: true))
      Button("Done", action: close).buttonStyle(IslandPillStyle(prominent: true, tint: TransformStyle.accent, compact: true))
    }
  }

  private func actionButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).font(.system(size: 14, weight: .semibold))
        .foregroundStyle(enabled ? Color(red: 0.72, green: 0.72, blue: 1) : IslandInk.tertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.98))
    .disabled(!enabled)
  }

  private var finishedSummary: String {
    if let total = model.totalSummary, model.failureCount == 0 { return total }
    if model.failureCount > 0 { return "\(model.failureCount) failed" }
    return model.rows.contains { if case .cancelled = $0.state { true } else { false } } ? "Cancelled" : "Nothing to change"
  }
}

/// A Transform ▸ menu item asks for an operation before the panel opens; the panel takes it once.
@MainActor
final class TransformLaunchRequest {
  static let shared = TransformLaunchRequest()
  var operation: TransformOperation?

  func makeModel(for urls: [URL]) -> TransformPanelModel {
    let model = TransformPanelModel(files: urls)
    if let operation { model.select(operation) }
    operation = nil
    return model
  }
}

/// What the notch shows after files land on Transform.
struct ConvertCard: View {
  let urls: [URL]
  let close: () -> Void

  var body: some View {
    TransformPanelView(urls: urls, close: close)
  }
}

/// The height the open Transform panel wants, read by the island to size itself.
struct TransformPanelHeightKey: PreferenceKey {
  static let defaultValue: CGFloat? = nil
  static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() ?? value }
}
