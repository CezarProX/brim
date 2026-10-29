import Foundation

enum TransformError: LocalizedError, Equatable {
  case unsupported(String)
  case unreadable(String)
  case failed(String)
  case cancelled

  var errorDescription: String? {
    switch self {
    case .unsupported(let what): "\(what) isn’t supported for this file."
    case .unreadable(let name): "Couldn’t read \(name)."
    case .failed(let message): message
    case .cancelled: "Cancelled."
    }
  }
}

/// What an operation needs to place its results and report progress.
struct TransformContext: Sendable {
  var policy: TransformOutputPolicy
  /// Overrides the Downloads folder (tests).
  var downloads: URL?
  var progress: @Sendable (Double) -> Void = { _ in }

  func output(for source: URL, suffix: String, fileExtension: String) -> URL {
    let folder = TransformNaming.folder(for: source, policy: policy, downloads: downloads)
    return TransformNaming.outputURL(for: source, suffix: suffix, fileExtension: fileExtension, in: folder)
  }

  func checkCancelled() throws {
    if Task.isCancelled { throw TransformError.cancelled }
  }
}
