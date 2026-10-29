// LocalizedText.swift
// Brim
//
// SwiftUI's `Text("literal")` is localized automatically, but `Text(someString)` is not. Most of the
// island builds its copy in enums and helpers (`title`, `note(_:)`), so this module-level overload
// routes those through the same string table. A string with no entry (a track title, a file name)
// renders unchanged, so dynamic content is safe.

import SwiftUI

extension Text {
  /// Shadows SwiftUI's `Text.init<S: StringProtocol>(_:)` so string-typed copy is looked up in
  /// Localizable.strings. Literals still pick `LocalizedStringKey` and keep their interpolation.
  init<S: StringProtocol>(_ content: S) {
    self.init(verbatim: L10n.tr(String(content)))
  }
}

// The same lookup for the other controls that take a plain-string title. Each overload shadows the
// SwiftUI one of the same shape, so existing call sites localize without being touched.

extension Toggle where Label == Text {
  init<S: StringProtocol>(_ title: S, isOn: Binding<Bool>) {
    self.init(isOn: isOn) { Text(verbatim: L10n.tr(String(title))) }
  }
}

extension Label where Title == Text, Icon == Image {
  init<S: StringProtocol>(_ title: S, systemImage name: String) {
    self.init { Text(verbatim: L10n.tr(String(title))) } icon: { Image(systemName: name) }
  }
}

extension Button where Label == Text {
  init<S: StringProtocol>(_ title: S, action: @escaping @MainActor () -> Void) {
    self.init(action: action) { Text(verbatim: L10n.tr(String(title))) }
  }

  init<S: StringProtocol>(_ title: S, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
    self.init(role: role, action: action) { Text(verbatim: L10n.tr(String(title))) }
  }
}

extension Menu where Label == Text {
  init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
    self.init(content: content) { Text(verbatim: L10n.tr(String(title))) }
  }
}
