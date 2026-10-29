import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The timer widget: a ruler over a play button and the big orange time.
struct TimerWidget: View {
  @ObservedObject var model: FocusTimerModel
  @State private var minutes = 25

  var body: some View {
    VStack(spacing: 8) {
      if model.isActive {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          IslandRing(progress: model.remaining(at: context.date) / max(1, model.duration), lineWidth: 4)
            .frame(width: 44, height: 44)
            .overlay {
              Image(systemName: model.isPaused ? "pause.fill" : "timer").font(.system(size: 13, weight: .bold))
                .foregroundStyle(IslandTint.timer)
            }
        }
        .frame(height: 48)
      } else {
        TimerDial(minutes: $minutes)
      }
      HStack(spacing: 8) {
        Button {
          if model.isActive {
            model.isPaused ? model.resume() : model.pause()
          } else {
            model.start(minutes: minutes)
          }
        } label: {
          Image(systemName: model.isActive && !model.isPaused ? "pause.fill" : "play.fill")
            .font(.system(size: 12, weight: .bold)).foregroundStyle(IslandTint.timer)
            .frame(width: 30, height: 30).background(IslandTint.timer.opacity(0.2), in: Circle())
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(IslandPressStyle(pressedScale: 0.88))
        .accessibilityLabel(model.isActive && !model.isPaused ? "Pause" : "Start")
        if model.isActive {
          Button(action: model.stop) {
            Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
              .frame(width: 30, height: 30).background(IslandFill.raised, in: Circle())
          }
          .buttonStyle(IslandPressStyle(pressedScale: 0.88))
          .accessibilityLabel("Stop")
        }
        Spacer(minLength: 0)
        TimelineView(.periodic(from: .now, by: 1)) { context in
          Text(model.isActive ? CompactTimerReadout.format(model.remaining(at: context.date)) : TimerDialMath.label(minutes: minutes))
            .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
            .foregroundStyle(IslandTint.timer)
            .contentTransition(.numericText(countsDown: model.isActive))
            .lineLimit(1).minimumScaleFactor(0.6)
        }
      }
    }
  }
}

/// The notes widget: "Edited 14:08", copy, open-in-window and delete, the formatting bar and the
/// note itself, edited in place. It is the same note the floating Notes window shows.
struct NotesWidget: View {
  @ObservedObject var model: NotesModel
  @StateObject private var controller = NoteEditorController()

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Text(model.selected.map { "Edited \($0.edited.formatted(date: .omitted, time: .shortened))" } ?? "Notes")
          .font(IslandFont.label.weight(.semibold)).foregroundStyle(IslandInk.secondary).lineLimit(1)
        Spacer(minLength: 0)
        if let note = model.selected {
          IslandGlyphButton(symbol: "doc.on.doc", label: "Copy note", size: 24) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(note.text, forType: .string)
          }
          IslandGlyphButton(symbol: "macwindow", label: "Open in window", size: 24) {
            NotesWindowController.shared.show(noteID: note.id)
            NotchShelfController.shared.dismissShelf()
          }
        }
        IslandGlyphButton(
          symbol: model.selected == nil ? "plus" : "trash",
          label: model.selected == nil ? "New note" : "Delete note", size: 24
        ) {
          if let note = model.selected { model.delete(note.id) } else { model.create() }
        }
      }
      if let note = model.selected {
        NoteFormatBar(controller: controller)
        NoteRichEditor(markdown: NotesBinding.markdown(for: note.id, in: model), controller: controller, style: .island)
          .id(note.id)
      }
    }
  }
}

enum IslandClock {
  static func greeting(at date: Date, calendar: Calendar = .current) -> String {
    switch calendar.component(.hour, from: date) {
    case 5..<12: return "Good morning"
    case 12..<18: return "Good afternoon"
    default: return "Good evening"
    }
  }

  static func relative(_ start: Date, now: Date = .now) -> String {
    let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
    let time = start.formatted(date: .omitted, time: .shortened)
    if minutes <= 0 { return "Now · \(time)" }
    if minutes < 60 { return "in \(minutes) min · \(time)" }
    return "at \(time)"
  }
}

/// The latest captures as a small pile of photos: the newest whole and on top,
/// older ones peeking out behind it. Nothing is cropped.
@MainActor
struct CapturePile: View {
  @ObservedObject var store: ShelfStore
  @State private var hovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let entries = Array(store.entries.prefix(3))
    ZStack {
      ForEach(Array(entries.enumerated().reversed()), id: \.element.id) { index, entry in
        photo(entry, index: index)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onHover { hovered = $0 }
    .animation(NotchMotion.press(reduceMotion: reduceMotion), value: hovered)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: entries.map(\.id))
  }

  private func photo(_ entry: ShelfEntry, index: Int) -> some View {
    // Fan the pile out a little more under the pointer.
    let spread: Double = hovered && !reduceMotion ? 1.6 : 1
    let angle = index == 0 ? 0 : Double(index == 1 ? -5 : 5) * spread
    let offset = CGFloat(index == 0 ? 0 : (index == 1 ? -10 : 10)) * spread
    return Button { NotchShelfController.shared.edit(entry) } label: {
      Group {
        if let thumbnail = store.thumbnail(for: entry) {
          Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
        } else {
          Image(systemName: "photo").foregroundStyle(IslandInk.tertiary).frame(width: 60, height: 40)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.75)
      }
      .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
      .frame(maxWidth: 150, maxHeight: 86)
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.96))
    .rotationEffect(.degrees(angle))
    .offset(x: offset, y: index == 0 ? 0 : -4)
    .scaleEffect(index == 0 ? 1 : 0.9)
    .zIndex(Double(3 - index))
    .allowsHitTesting(index == 0)
    .help("Edit screenshot from \(entry.date.formatted())")
    .onDrag {
      (try? Data(contentsOf: store.fileURL(for: entry))).map {
        ImageDragExport.provider(for: $0, date: entry.date)
          ?? NSItemProvider(item: $0 as NSData, typeIdentifier: UTType.png.identifier)
      } ?? NSItemProvider()
    }
  }
}
