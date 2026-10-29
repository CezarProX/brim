import AVFoundation
import Foundation

/// What the mirror shows: one state, one clear next step.
enum CameraMirrorState: Equatable {
  case needsAccess  // first run: ask with a button, never on open
  case denied  // switched off in Privacy & Security
  case noCamera
  case starting
  case live
  case busy  // another app holds the camera
}

struct CameraChoice: Identifiable, Equatable {
  let id: String
  let name: String
}

/// Camera access as the model needs it; tests use a fake.
struct CameraSource {
  var authorization: () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .video) }
  var requestAccess: () async -> Bool = { await AVCaptureDevice.requestAccess(for: .video) }
  var cameras: () -> [CameraChoice] = CameraSource.discover

  static func discover() -> [CameraChoice] {
    AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
      mediaType: .video, position: .unspecified
    ).devices.map { CameraChoice(id: $0.uniqueID, name: $0.localizedName) }
  }
}

/// Camera preview that runs only while the Mirror tool is visible. Nothing is recorded or saved.
@MainActor
final class CameraMirrorModel: ObservableObject {
  static let shared = CameraMirrorModel()
  static let deviceKey = "cameraMirrorDeviceID"

  let session = AVCaptureSession()
  @Published private(set) var state: CameraMirrorState = .starting
  @Published private(set) var cameras: [CameraChoice] = []
  @Published private(set) var selectedID: String?

  private let source: CameraSource
  private let defaults: UserDefaults
  private var observers: [NSObjectProtocol] = []
  private var visible = false
  private var isPreview = false

  init(source: CameraSource = CameraSource(), defaults: UserDefaults = .standard) {
    self.source = source
    self.defaults = defaults
  }

  var running: Bool { state == .live }
  var selectedName: String? { cameras.first { $0.id == selectedID }?.name }

  /// Called when the mirror appears. Starts the camera only if access was already given.
  func appear() async {
    visible = true
    if isPreview { return }
    observe()
    refreshCameras()
    switch source.authorization() {
    case .authorized: await start()
    case .notDetermined: state = .needsAccess
    default: state = .denied
    }
  }

  /// The one button on the first-run card.
  func allowAccess() async {
    state = .starting
    guard await source.requestAccess() else { state = .denied; return }
    await start()
  }

  func retry() async { await start() }

  func choose(_ id: String) async {
    defaults.set(id, forKey: Self.deviceKey)
    selectedID = id
    await start()
  }

  func disappear() {
    visible = false
    for token in observers { NotificationCenter.default.removeObserver(token) }
    observers = []
    let session = session
    Task.detached { session.stopRunning() }
    if state == .live || state == .busy { state = .starting }
  }

  /// Fixed content for previews and render tests.
  func loadPreview(state: CameraMirrorState, cameras: [CameraChoice] = []) {
    isPreview = true
    self.state = state
    self.cameras = cameras
    selectedID = cameras.first?.id
  }

  // MARK: Internals

  private func refreshCameras() {
    cameras = source.cameras()
    let saved = defaults.string(forKey: Self.deviceKey)
    selectedID = cameras.first { $0.id == saved }?.id ?? cameras.first?.id
  }

  private func start() async {
    refreshCameras()
    guard let id = selectedID, let device = AVCaptureDevice(uniqueID: id) else { state = .noCamera; return }
    state = .starting
    session.beginConfiguration()
    for input in session.inputs { session.removeInput(input) }
    session.sessionPreset = .high
    guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
      session.commitConfiguration()
      state = .busy
      return
    }
    session.addInput(input)
    session.commitConfiguration()
    let session = session
    await Task.detached { session.startRunning() }.value
    guard visible else { Task.detached { session.stopRunning() }; return }
    state = session.isRunning ? .live : .busy
  }

  private func observe() {
    guard observers.isEmpty else { return }
    let center = NotificationCenter.default
    let names: [Notification.Name] = [
      AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification,
    ]
    for name in names {
      observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in
          guard let self, self.visible, self.source.authorization() == .authorized else { return }
          await self.start()
        }
      })
    }
    for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
      observers.append(center.addObserver(forName: name, object: session, queue: .main) { [weak self] _ in
        Task { @MainActor in if self?.visible == true { self?.state = .busy } }
      })
    }
  }
}
