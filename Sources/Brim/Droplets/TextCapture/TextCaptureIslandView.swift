// TextCaptureIslandView.swift
// Brim
//
// Text Capture in the open island: capture buttons on the left, result or history on the right.

import SwiftUI

struct TextCaptureIslandView: View {
  @ObservedObject private var model: TextCaptureModel
  @ObservedObject private var history: TextCaptureHistory
  @State private var tab = Tab.result
  @State private var query = ""
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @MainActor init(model: TextCaptureModel? = nil, history: TextCaptureHistory? = nil) {
    self.model = model ?? .shared
    self.history = history ?? .shared
  }

  enum Tab: String, CaseIterable { case result = "Result", history = "History" }

  var body: some View {
    HStack(spacing: IslandSpace.m) {
      actions.frame(width: 176)
      DropletCard {
        VStack(spacing: 0) {
          header
          Divider().overlay(IslandFill.hairline)
          Group {
            switch tab {
            case .result: resultPane
            case .history: historyPane
            }
          }
          .transition(.opacity)
        }
      }
    }
    .padding(IslandSpace.s)
    .frame(minWidth: 520, minHeight: 190)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: tab)
    .onChange(of: model.result) { _, new in if new != nil { tab = .result } }
  }

  // MARK: Left column

  private var actions: some View {
    VStack(spacing: IslandSpace.s) {
      captureButton("Select area", symbol: "viewfinder", tint: .teal, prominent: true) { Task { await model.captureArea() } }
      captureButton("Image or PDF…", symbol: "doc.viewfinder", tint: .white, prominent: false) { Task { await model.chooseFile() } }
      Spacer(minLength: 0)
      statusLine
    }
  }

  private func captureButton(_ title: String, symbol: String, tint: Color, prominent: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
        Text(title).font(IslandFont.headline)
        Spacer(minLength: 0)
      }
      .foregroundStyle(prominent ? Color.black : IslandInk.primary)
      .padding(.horizontal, 12).frame(maxWidth: .infinity).frame(height: 44)
      .background(prominent ? tint : IslandFill.raised, in: RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous))
    }
    .buttonStyle(IslandPressStyle())
    .disabled(model.isWorking)
  }

  @ViewBuilder private var statusLine: some View {
    if model.isWorking {
      HStack(spacing: 6) {
        ProgressView().controlSize(.small)
        Text(model.progress ?? "Reading…").font(IslandFont.body).foregroundStyle(IslandInk.secondary)
      }
    } else if model.needsScreenAccess {
      VStack(alignment: .leading, spacing: 6) {
        Text("Screen Recording is off for Brim.").font(IslandFont.body).foregroundStyle(IslandInk.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Button("Open Settings") {
          if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
          }
        }
        .buttonStyle(AppPrimaryButtonStyle(tint: .teal))
      }
    } else if let notice = model.notice {
      Label(notice, systemImage: "exclamationmark.circle").font(IslandFont.body).foregroundStyle(IslandInk.secondary)
    } else {
      Text("Reads text, QR codes and barcodes on this Mac. Nothing is uploaded.")
        .font(IslandFont.body).foregroundStyle(IslandInk.tertiary).fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: Right column

  private var header: some View {
    HStack {
      Picker("", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
        .pickerStyle(.segmented).labelsHidden().frame(width: 150)
      Spacer()
      if tab == .history {
        TextField("Search", text: $query).textFieldStyle(.plain).font(IslandFont.body)
          .padding(.horizontal, 10).frame(width: 140, height: 28)
          .background(IslandFill.subtle, in: Capsule())
        DropletIconButton(symbol: "trash", help: "Clear history") { history.clear() }
      }
    }
    .padding(.horizontal, IslandSpace.s).padding(.vertical, 6)
  }

  @ViewBuilder private var resultPane: some View {
    if let result = model.result {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(Array(result.payloads.enumerated()), id: \.offset) { _, payload in CodeRow(payload: payload, model: model) }
        if !result.text.isEmpty {
          ScrollView {
            Text(result.text).font(.system(size: 13)).foregroundStyle(IslandInk.primary)
              .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
          }
          HStack {
            Text(summary(result)).font(IslandFont.body).foregroundStyle(IslandInk.tertiary)
            Spacer()
            Button { model.copy(result.text) } label: { Label("Copy", systemImage: "doc.on.doc") }
              .buttonStyle(AppPrimaryButtonStyle(tint: .teal))
          }
        } else { Spacer(minLength: 0) }
      }
      .padding(IslandSpace.s)
    } else {
      VStack(spacing: 6) {
        Image(systemName: "text.viewfinder").font(.system(size: 28, weight: .light)).foregroundStyle(.teal)
        Text("Copy text from anywhere").font(IslandFont.title).foregroundStyle(IslandInk.primary)
        Text("Press Select area, drag over a web page, image, video or app, and the text is copied. QR codes and barcodes work too.")
          .font(IslandFont.body).foregroundStyle(IslandInk.secondary).multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 320)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func summary(_ result: TextCaptureResult) -> String {
    let words = result.text.split(whereSeparator: { $0.isWhitespace }).count
    let pages = result.pages.map { " · \($0) page\($0 == 1 ? "" : "s")" } ?? ""
    return "\(words) word\(words == 1 ? "" : "s")\(pages)"
  }

  private var historyPane: some View {
    let entries = TextCaptureHistoryPolicy.search(history.entries, query: query)
    return Group {
      if entries.isEmpty {
        Text(history.entries.isEmpty ? "Captures appear here (last 100)." : "No matches")
          .font(IslandFont.body).foregroundStyle(IslandInk.tertiary).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(spacing: 2) {
            ForEach(entries) { entry in HistoryRow(entry: entry, model: model, history: history, onOpen: { tab = .result }) }
          }
          .padding(IslandSpace.xs)
        }
      }
    }
  }
}

private struct CodeRow: View {
  let payload: CodePayload
  let model: TextCaptureModel

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: payload.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.teal)
        .frame(width: 32, height: 32).background(Color.teal.opacity(0.18), in: RoundedRectangle(cornerRadius: IslandRadius.small))
      VStack(alignment: .leading, spacing: 1) {
        Text(payload.title).font(IslandFont.headline).foregroundStyle(IslandInk.primary).lineLimit(1)
        Text(payload.detail).font(IslandFont.body).foregroundStyle(IslandInk.secondary).lineLimit(1)
      }
      Spacer(minLength: 0)
      Button("Copy") { model.copy(payload.copyValue) }.buttonStyle(AppSecondaryButtonStyle())
      if let url = payload.openURL {
        Button("Open") { model.open(url) }.buttonStyle(AppPrimaryButtonStyle(tint: .teal))
      }
    }
    .padding(6)
    .glassCard(radius: IslandRadius.small + 2)
  }
}

private struct HistoryRow: View {
  let entry: TextCaptureEntry
  let model: TextCaptureModel
  let history: TextCaptureHistory
  let onOpen: () -> Void
  @State private var hovered = false

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.teal).frame(width: 18)
      Text(entry.firstLine).font(IslandFont.body).foregroundStyle(IslandInk.primary).lineLimit(1)
      Spacer(minLength: 4)
      Text(entry.date, style: .relative).font(IslandFont.body).foregroundStyle(IslandInk.tertiary).lineLimit(1)
      if hovered {
        Button { history.remove(entry) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
          .buttonStyle(.plain).foregroundStyle(IslandInk.secondary).help("Remove")
      }
    }
    .padding(.horizontal, 8).frame(height: 28)
    .background(hovered ? IslandFill.hover : .clear, in: RoundedRectangle(cornerRadius: IslandRadius.small, style: .continuous))
    .contentShape(Rectangle())
    .onHover { hovered = $0 }
    .onTapGesture {
      model.copy(entry.text)
      model.show(entry)
      onOpen()
    }
    .help("Click to copy and show")
  }

  private var icon: String {
    if entry.kind == .code { return CodePayload.classify(entry.text, symbology: entry.symbology ?? "QR code").symbol }
    return entry.source == .pdf ? "doc.text" : "text.alignleft"
  }
}
