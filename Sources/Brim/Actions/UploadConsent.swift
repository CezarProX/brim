import Foundation

/// Decides when an upload must first be confirmed: the first time screenshots go to a host, so the
/// user learns where they go and that the link is public.
enum UploadConsent {
  /// The host to confirm, or nil when the user already agreed to it (or the URL has no host,
  /// which the uploader rejects on its own).
  static func hostNeedingConsent(serviceURL: String, acknowledged: String?) -> String? {
    guard let host = URL(string: serviceURL.trimmingCharacters(in: .whitespaces))?.host?.lowercased(), !host.isEmpty
    else { return nil }
    return host == acknowledged?.lowercased() ? nil : host
  }
}
