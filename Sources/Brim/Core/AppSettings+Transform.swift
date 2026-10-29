import Foundation

/// Settings for the file tray, Transform and the floating trays.
extension AppSettings {
  private enum TransformKey {
    static let destination = "transformDestination"
    static let reveal = "transformRevealInFinder"
    static let trash = "transformTrashOriginals"
    static let keepInTray = "transformKeepResultsInTray"
    static let imageQuality = "transformImageQuality"
    static let imageFormat = "transformImageFormat"
    static let videoQuality = "transformVideoQuality"
    static let pdfQuality = "transformPDFQuality"
    static let userPresets = "transformUserPresets"
    static let quickActions = "quickActionExtras"
    static let retention = "trayRetention"
    static let multipleTrays = "floatingTrayMultiple"
    static let autoHide = "floatingTrayAutoHideSeconds"
    static let switcher = "floatingTraySwitcher"
    static let shake = "floatingTrayShakeSensitivity"
  }

  static let maximumFloatingTrays = 4
  static let maximumQuickActionExtras = 3

  private func raw<T: RawRepresentable>(_ key: String, default value: T) -> T where T.RawValue == String {
    (defaults.string(forKey: key)).flatMap(T.init(rawValue:)) ?? value
  }

  // MARK: Transform

  var transformDestination: TransformDestination {
    get { raw(TransformKey.destination, default: .nextToOriginal) }
    set { defaults.set(newValue.rawValue, forKey: TransformKey.destination) }
  }

  var transformRevealInFinder: Bool {
    get { defaults.object(forKey: TransformKey.reveal) as? Bool ?? false }
    set { defaults.set(newValue, forKey: TransformKey.reveal) }
  }

  /// Off by default. Originals are never overwritten either way.
  var transformTrashOriginals: Bool {
    get { defaults.object(forKey: TransformKey.trash) as? Bool ?? false }
    set { defaults.set(newValue, forKey: TransformKey.trash) }
  }

  var transformKeepResultsInTray: Bool {
    get { defaults.object(forKey: TransformKey.keepInTray) as? Bool ?? false }
    set { defaults.set(newValue, forKey: TransformKey.keepInTray) }
  }

  var transformImageQuality: Double {
    get { min(1, max(0.1, defaults.object(forKey: TransformKey.imageQuality) as? Double ?? 0.72)) }
    set { defaults.set(newValue, forKey: TransformKey.imageQuality) }
  }

  var transformImageFormat: TransformImageFormat {
    get { raw(TransformKey.imageFormat, default: .automatic) }
    set { defaults.set(newValue.rawValue, forKey: TransformKey.imageFormat) }
  }

  var transformVideoQuality: TransformQuality {
    get { raw(TransformKey.videoQuality, default: .balanced) }
    set { defaults.set(newValue.rawValue, forKey: TransformKey.videoQuality) }
  }

  var transformPDFQuality: TransformQuality {
    get { raw(TransformKey.pdfQuality, default: .balanced) }
    set { defaults.set(newValue.rawValue, forKey: TransformKey.pdfQuality) }
  }

  var transformOutputPolicy: TransformOutputPolicy {
    TransformOutputPolicy(
      destination: transformDestination, moveOriginalsToTrash: transformTrashOriginals && !trayProtectOriginals,
      revealInFinder: transformRevealInFinder)
  }

  /// Options the Transform panel starts from, from the user's defaults.
  var transformDefaultOptions: TransformOptions {
    var options = TransformOptions()
    options.imageQuality = transformImageQuality
    options.imageFormat = transformImageFormat
    options.videoQuality = transformVideoQuality
    options.pdfQuality = transformPDFQuality
    return options
  }

  var transformUserPresets: [TransformPreset] {
    get {
      defaults.data(forKey: TransformKey.userPresets)
        .flatMap { try? JSONDecoder().decode([TransformPreset].self, from: $0) } ?? []
    }
    set {
      defaults.set(try? JSONEncoder().encode(newValue.filter { !$0.isBuiltIn }), forKey: TransformKey.userPresets)
    }
  }

  // MARK: Quick actions

  /// The tiles after the always-present Drop and Transform, in order.
  var quickActionExtras: [DropTarget] {
    get {
      let stored = defaults.stringArray(forKey: TransformKey.quickActions) ?? DropTarget.defaultExtras.map(\.rawValue)
      return DropTarget.sanitizedExtras(stored.compactMap(DropTarget.init(rawValue:)))
    }
    set {
      defaults.set(DropTarget.sanitizedExtras(newValue).map(\.rawValue), forKey: TransformKey.quickActions)
    }
  }

  /// Every tile, Drop and Transform first.
  var quickActionTargets: [DropTarget] { DropTarget.required + quickActionExtras }

  // MARK: File tray

  var trayRetention: FileTrayRetention {
    get { raw(TransformKey.retention, default: .never) }
    set { defaults.set(newValue.rawValue, forKey: TransformKey.retention) }
  }

  var floatingTrayMultiple: Bool {
    get { defaults.object(forKey: TransformKey.multipleTrays) as? Bool ?? true }
    set { defaults.set(newValue, forKey: TransformKey.multipleTrays) }
  }

  /// Seconds an idle, empty floating tray waits before closing. 0 keeps it open.
  var floatingTrayAutoHideSeconds: Int {
    get { max(0, defaults.object(forKey: TransformKey.autoHide) as? Int ?? 0) }
    set { defaults.set(max(0, newValue), forKey: TransformKey.autoHide) }
  }

  var floatingTraySwitcher: Bool {
    get { defaults.object(forKey: TransformKey.switcher) as? Bool ?? true }
    set { defaults.set(newValue, forKey: TransformKey.switcher) }
  }

  /// 1 (hard to trigger) … 5 (easy), default 3.
  var shakeSensitivity: Int {
    get { min(5, max(1, defaults.object(forKey: TransformKey.shake) as? Int ?? 3)) }
    set { defaults.set(min(5, max(1, newValue)), forKey: TransformKey.shake) }
  }
}
