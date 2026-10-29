import AVFoundation
import AppKit
import SwiftUI

// MARK: Keep Awake

/// One big switch like a Control Center module, the time left as the headline, durations underneath.
struct KeepAwakeView: View {
  @ObservedObject var model: KeepAwakeModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let options: [(String, Int?)] = [("15 min", 15), ("1 hour", 60), ("2 hours", 120), ("Until off", nil)]

  var body: some View {
    VStack(alignment: .leading, spacing: IslandSpace.l) {
      HStack(spacing: IslandSpace.l) {
        Button {
          withAnimation(NotchMotion.press(reduceMotion: reduceMotion)) {
            if model.isActive { model.stop() } else { model.start(minutes: nil) }
          }
        } label: {
          Image(systemName: model.isActive ? "cup.and.heat.waves.fill" : "cup.and.saucer.fill")
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(model.isActive ? Color.black : IslandInk.primary)
            .frame(width: 76, height: 76)
            .background(model.isActive ? Color.yellow : IslandFill.raised, in: Circle())
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.pulse, isActive: model.isActive && !reduceMotion)
        }
        .buttonStyle(IslandPressStyle(pressedScale: 0.9))
        .accessibilityLabel(model.isActive ? "Allow sleep" : "Keep awake")
        VStack(alignment: .leading, spacing: 0) {
          Text("Keep Awake").font(IslandFont.headline).foregroundStyle(IslandInk.secondary)
          TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(headline(at: context.date))
              .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
              .foregroundStyle(model.isActive ? Color.yellow : IslandInk.tertiary)
              .contentTransition(.numericText(countsDown: true))
          }
          Text(caption).font(IslandFont.label).foregroundStyle(IslandInk.tertiary)
        }
        Spacer(minLength: 0)
      }
      HStack(spacing: 6) {
        ForEach(options, id: \.0) { option in
          Button(option.0) {
            withAnimation(NotchMotion.press(reduceMotion: reduceMotion)) { model.start(minutes: option.1) }
          }
          .buttonStyle(IslandPillStyle(compact: true))
        }
      }
    }
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: model.isActive)
  }

  private func headline(at now: Date) -> String {
    guard model.isActive else { return "Off" }
    guard let until = model.until else { return "On" }
    return CompactTimerReadout.format(max(0, until.timeIntervalSince(now)))
  }

  private var caption: String {
    if let until = model.until { return "Your Mac stays awake until \(until.formatted(date: .omitted, time: .shortened))" }
    return model.isActive ? "Your Mac stays awake until you turn this off" : "Your Mac sleeps on its usual schedule"
  }
}

// MARK: Notes

private let notesYellow = Color(red: 1, green: 0.8, blue: 0.2)

/// Apple Notes in miniature: a yellow-accented list beside the editor.
struct NotesView: View {
  @ObservedObject var model: NotesModel
  @State private var draft = ""
  @FocusState private var editing: Bool

  var body: some View {
    Group {
      if model.notes.isEmpty {
        empty
      } else {
        HStack(alignment: .top, spacing: IslandSpace.m) {
          sidebar.frame(width: 150)
          editor
        }
      }
    }
    .onAppear { draft = model.selected?.text ?? "" }
    // Whatever changes the selection (a delete, a sync, another window), the editor must show that
    // note; a stale draft would otherwise be written over it on the next keystroke.
    .onChange(of: model.selectedID) { _, _ in draft = model.selected?.text ?? "" }
  }

  private var empty: some View {
    VStack(spacing: IslandSpace.s) {
      Spacer(minLength: 0)
      Image(systemName: "note.text").font(.system(size: 30, weight: .regular)).foregroundStyle(notesYellow)
      Text("No Notes").font(IslandFont.title)
      Text("Jot something down. Notes stay on this Mac.").font(IslandFont.label).foregroundStyle(IslandInk.tertiary)
      Button("New Note", action: newNote)
        .buttonStyle(IslandPillStyle(prominent: true, tint: notesYellow, compact: true))
        .padding(.top, 4)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity)
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Notes").font(IslandFont.headline).foregroundStyle(notesYellow)
        Spacer()
        Button(action: newNote) {
          Image(systemName: "square.and.pencil").font(.system(size: 13, weight: .medium))
            .foregroundStyle(notesYellow).frame(width: 24, height: 24)
        }
        .buttonStyle(IslandPressStyle()).help("New Note").accessibilityLabel("New Note")
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          ForEach(model.notes) { note in
            Button {
              model.selectedID = note.id
              draft = note.text
            } label: {
              VStack(alignment: .leading, spacing: 1) {
                Text(note.title).font(IslandFont.label.weight(.semibold)).lineLimit(1)
                Text(note.edited, format: .relative(presentation: .named))
                  .font(IslandFont.caption).foregroundStyle(IslandInk.tertiary)
              }
              .padding(.horizontal, 8).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
              .background(
                model.selectedID == note.id ? notesYellow.opacity(0.22) : .clear,
                in: RoundedRectangle(cornerRadius: IslandRadius.small, style: .continuous))
            }
            .buttonStyle(IslandPressStyle(pressedScale: 0.97))
            .contextMenu {
              Button("Delete", role: .destructive) { model.delete(note.id) }
            }
          }
        }
      }
      .scrollIndicators(.hidden)
    }
  }

  @ViewBuilder
  private var editor: some View {
    if let note = model.selected {
      TextEditor(text: $draft)
        .font(.system(size: 13))
        .scrollContentBackground(.hidden)
        .focused($editing)
        .padding(8)
        .overlay(alignment: .topLeading) {
          if draft.isEmpty {
            Text("Start typing…").font(.system(size: 13)).foregroundStyle(IslandInk.tertiary)
              .padding(.horizontal, 13).padding(.vertical, 8).allowsHitTesting(false)
          }
        }
        .glassCard(radius: IslandRadius.medium)
        .onChange(of: draft) { _, text in
          guard text != note.text else { return }
          model.update(note.id, text: text)
        }
        .id(note.id)
    } else {
      VStack(spacing: 6) {
        Image(systemName: "note.text").font(.system(size: 22)).foregroundStyle(IslandInk.tertiary)
        Text("Select a note").font(IslandFont.label).foregroundStyle(IslandInk.tertiary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func newNote() {
    model.create()
    draft = ""
    editing = true
  }
}

// MARK: System stats

/// Three gauges like Activity Monitor's summary: the value inside the ring, what it means underneath.
struct SystemStatsView: View {
  @ObservedObject var model: SystemStatsModel

  var body: some View {
    let memory = Double(model.memoryUsed) / Double(max(1, model.memoryTotal))
    let disk = 1 - Double(model.diskFree) / Double(max(1, model.diskTotal))
    HStack(alignment: .top, spacing: 0) {
      gauge("CPU", symbol: "cpu", value: model.hasCPUReading ? model.cpu : nil, tint: .teal) {
        if model.cpuHistory.count > 1 {
          Sparkline(values: model.cpuHistory, tint: .teal).frame(width: 64, height: 14)
        } else {
          Text("\(ProcessInfo.processInfo.activeProcessorCount) cores")
        }
      }
      gauge("Memory", symbol: "memorychip", value: model.memoryTotal > 0 ? memory : nil, tint: .purple) {
        Text("\(bytes(Int64(model.memoryUsed), .memory)) of \(bytes(Int64(model.memoryTotal), .memory))")
      }
      gauge("Disk", symbol: "internaldrive", value: model.diskTotal > 0 ? disk : nil, tint: .orange) {
        Text("\(bytes(model.diskFree, .file)) free")
      }
    }
    .onAppear { model.attach() }
    .onDisappear { model.detach() }
  }

  private func bytes(_ value: Int64, _ style: ByteCountFormatter.CountStyle) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: style)
  }

  private func gauge<Detail: View>(_ title: String, symbol: String, value: Double?, tint: Color,
                                   @ViewBuilder detail: () -> Detail) -> some View {
    let color = (value ?? 0) >= 0.9 ? Color.red : tint
    return VStack(spacing: 6) {
      ZStack {
        IslandRing(progress: value ?? 0, tint: color, lineWidth: 7).padding(3.5)
        VStack(spacing: 0) {
          Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
          Text(value.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
            .font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
            .contentTransition(.numericText())
        }
      }
      .frame(width: 78, height: 78)
      Text(title).font(IslandFont.headline)
      detail().font(IslandFont.caption).foregroundStyle(IslandInk.tertiary).lineLimit(1)
    }
    .frame(maxWidth: .infinity)
    .animation(.spring(duration: 0.4, bounce: 0), value: value)
    .accessibilityElement(children: .combine)
  }
}

private struct Sparkline: View {
  let values: [Double]
  let tint: Color

  var body: some View {
    Canvas { context, size in
      guard values.count > 1 else { return }
      let step = size.width / CGFloat(values.count - 1)
      var line = Path()
      for (index, value) in values.enumerated() {
        let point = CGPoint(x: CGFloat(index) * step, y: size.height * (1 - CGFloat(value)))
        index == 0 ? line.move(to: point) : line.addLine(to: point)
      }
      var fill = line
      fill.addLine(to: CGPoint(x: size.width, y: size.height))
      fill.addLine(to: CGPoint(x: 0, y: size.height))
      fill.closeSubpath()
      context.fill(fill, with: .linearGradient(
        Gradient(colors: [tint.opacity(0.35), tint.opacity(0)]), startPoint: .zero,
        endPoint: CGPoint(x: 0, y: size.height)))
      context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
    }
    .accessibilityHidden(true)
  }
}
