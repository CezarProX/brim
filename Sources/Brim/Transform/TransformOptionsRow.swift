import SwiftUI

/// The one-line options for the selected operation.
struct TransformOptionsRow: View {
  @ObservedObject var model: TransformPanelModel

  var body: some View {
    HStack(spacing: IslandSpace.s) {
      switch model.operation {
      case .compress: compress
      case .resize: resize
      case .convert: convert
      case .makeGIF: gif
      case .trim: trim
      case .frameRate:
        OptionMenu(title: "Rate", value: "\(Int(model.options.targetFPS)) fps", choices: [12, 15, 24, 30, 60], label: { "\(Int($0)) fps" }) {
          model.options.targetFPS = $0
        }
      case .rotate:
        ForEach([90, 180, 270], id: \.self) { degrees in
          OptionChip(title: "\(degrees)°", symbol: "rotate.right", selected: model.options.clampedRotation == degrees) {
            model.options.rotation = degrees
          }
        }
      case .rename: rename
      default: Text(note).font(IslandFont.label).foregroundStyle(IslandInk.tertiary).lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .frame(height: 28)
  }

  private var note: String {
    switch model.operation {
    case .removeMetadata: "Strips location, camera and author details."
    case .removeBackground: "Keeps the subject on a transparent PNG."
    case .removeAudio: "Saves a silent copy of the video."
    case .extractAudio: "Saves the sound as an .m4a file."
    case .combinePDF: "Joins images and PDFs, in order, into one PDF."
    case .splitPDF: "Saves every page as its own PDF."
    case .zip: "Packs the files into a ZIP archive."
    case .extract: "Unpacks into a new folder."
    default: ""
    }
  }

  // MARK: Per operation

  @ViewBuilder private var compress: some View {
    if model.kinds.contains(.image) {
      if model.options.targetBytes != nil {
        OptionMenu(title: "Under", value: Self.megabytes(model.options.targetBytes ?? 0), choices: [1, 2, 5, 10, 25], label: { "\($0) MB" }) {
          model.options.targetBytes = Int64($0) * 1_000_000
        }
        OptionChip(title: "Quality", symbol: "slider.horizontal.3", selected: false) { model.options.targetBytes = nil }
      } else {
        Slider(value: $model.options.imageQuality, in: 0.1...1).controlSize(.mini).tint(.blue).frame(width: 110)
        Text("\(Int(model.options.imageQuality * 100))%").font(IslandFont.label.monospacedDigit())
          .foregroundStyle(IslandInk.secondary).frame(width: 34, alignment: .leading)
        OptionChip(title: "Size", symbol: "scalemass", selected: false) { model.options.targetBytes = 10_000_000 }
      }
      OptionMenu(title: "Format", value: model.options.imageFormat.rawValue,
                 choices: TransformImageFormat.writable().filter { $0 != .tiff }, label: { $0.rawValue }) {
        model.options.imageFormat = $0
      }
    }
    if model.kinds.contains(.video) {
      OptionMenu(title: "Video", value: model.options.videoQuality.rawValue, choices: TransformQuality.allCases, label: { $0.rawValue }) {
        model.options.videoQuality = $0
      }
    }
    if model.kinds.contains(.pdf) {
      OptionMenu(title: "PDF", value: model.options.pdfQuality.rawValue, choices: TransformQuality.allCases, label: { $0.rawValue }) {
        model.options.pdfQuality = $0
      }
    }
  }

  private var resize: some View {
    HStack(spacing: IslandSpace.s) {
      OptionMenu(title: "By", value: model.options.resizeMode.rawValue, choices: TransformResizeMode.allCases, label: { $0.rawValue }) {
        model.options.resizeMode = $0
      }
      if model.options.resizeMode == .maxDimension {
        OptionMenu(title: "Max", value: "\(model.options.maxDimension) px", choices: [480, 800, 1200, 1600, 2400, 3840], label: { "\($0) px" }) {
          model.options.maxDimension = $0
        }
      } else {
        OptionMenu(title: "Scale", value: "\(model.options.percent)%", choices: [25, 50, 75], label: { "\($0)%" }) {
          model.options.percent = $0
        }
      }
    }
  }

  @ViewBuilder private var convert: some View {
    if model.kinds.contains(.image) {
      OptionMenu(title: "To", value: model.options.convertFormat.rawValue,
                 choices: TransformImageFormat.writable().filter { $0 != .automatic }, label: { $0.rawValue }) {
        model.options.convertFormat = $0
      }
    }
    if model.kinds.contains(.video) {
      OptionMenu(title: "Video", value: model.options.videoContainer.rawValue, choices: TransformVideoContainer.available(), label: { $0.rawValue }) {
        model.options.videoContainer = $0
      }
    }
    if model.kinds.contains(.audio) { Text("Audio becomes .m4a").font(IslandFont.label).foregroundStyle(IslandInk.tertiary) }
  }

  @ViewBuilder private var gif: some View {
    OptionMenu(title: "Speed", value: "\(Int(model.options.gifFPS)) fps", choices: [8, 10, 12, 15, 20], label: { "\(Int($0)) fps" }) {
      model.options.gifFPS = $0
    }
    OptionMenu(title: "Width", value: "\(model.options.gifWidth) px", choices: [320, 480, 640, 800], label: { "\($0) px" }) {
      model.options.gifWidth = $0
    }
  }

  private var trim: some View {
    HStack(spacing: IslandSpace.s) {
      SecondsField(title: "From", value: Binding(get: { model.options.trimStart }, set: { model.options.trimStart = max(0, $0) }))
      SecondsField(title: "To", value: Binding(get: { model.options.trimEnd ?? 0 }, set: { model.options.trimEnd = $0 > 0 ? $0 : nil }), placeholder: "end")
    }
  }

  private var rename: some View {
    HStack(spacing: IslandSpace.s) {
      TextField("{name}-{n}", text: $model.options.renamePattern)
        .textFieldStyle(.plain).font(IslandFont.label).padding(.horizontal, 8).frame(width: 130, height: 24)
        .background(IslandFill.raised, in: Capsule())
      if let first = model.files.first {
        let preview = TransformNaming.renamed(
          pattern: model.options.renamePattern, originalName: first.deletingPathExtension().lastPathComponent, index: 1)
        Text("→ \(preview).\(first.pathExtension)").font(IslandFont.caption).foregroundStyle(IslandInk.tertiary)
          .lineLimit(1).truncationMode(.middle)
      }
    }
  }

  private static func megabytes(_ bytes: Int64) -> String { "\(bytes / 1_000_000) MB" }
}

/// A "Title  value ⌄" pill that opens a menu of choices.
struct OptionMenu<Value: Hashable>: View {
  let title: String
  let value: String
  let choices: [Value]
  let label: (Value) -> String
  let pick: (Value) -> Void

  var body: some View {
    Menu {
      ForEach(choices, id: \.self) { choice in
        Button(label(choice)) { pick(choice) }
      }
    } label: {
      HStack(spacing: 4) {
        Text(title).foregroundStyle(IslandInk.tertiary)
        Text(value).foregroundStyle(IslandInk.primary).contentTransition(.numericText())
        Image(systemName: "chevron.up.chevron.down").font(.system(size: 7, weight: .bold)).foregroundStyle(IslandInk.tertiary)
      }
      .font(IslandFont.label)
      .padding(.horizontal, 9).frame(height: 24)
      .background(IslandFill.raised, in: Capsule())
    }
    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
  }
}

struct OptionChip: View {
  let title: String
  let symbol: String
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
        Text(title)
      }
      .font(IslandFont.label)
      .foregroundStyle(selected ? Color.black : IslandInk.secondary)
      .padding(.horizontal, 9).frame(height: 24)
      .background(selected ? Color.white : IslandFill.subtle, in: Capsule())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.94))
  }
}

private struct SecondsField: View {
  let title: String
  @Binding var value: Double
  var placeholder = "0"

  var body: some View {
    HStack(spacing: 4) {
      Text(title).font(IslandFont.label).foregroundStyle(IslandInk.tertiary)
      TextField(placeholder, value: $value, format: .number.precision(.fractionLength(0...1)))
        .textFieldStyle(.plain).multilineTextAlignment(.trailing).font(IslandFont.label.monospacedDigit())
        .frame(width: 34)
      Text("s").font(IslandFont.label).foregroundStyle(IslandInk.tertiary)
    }
    .padding(.horizontal, 9).frame(height: 24)
    .background(IslandFill.raised, in: Capsule())
  }
}
