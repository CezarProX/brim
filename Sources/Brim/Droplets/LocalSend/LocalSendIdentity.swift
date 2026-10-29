import CryptoKit
import Foundation
import Security

/// The self-signed certificate LocalSend uses for HTTPS. It is generated once on this Mac with
/// the system `openssl`, kept as a PKCS#12 file in Application Support, and loaded in memory.
enum LocalSendIdentity {
  struct Material {
    let identity: SecIdentity
    /// SHA-256 of the certificate (DER), lowercase hex: the device fingerprint for HTTPS.
    let fingerprint: String
  }

  enum Failure: Error, LocalizedError {
    case generate, load
    var errorDescription: String? {
      self == .generate ? "Couldn’t create a certificate for LocalSend." : "Couldn’t load the LocalSend certificate."
    }
  }

  static var directory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Brim/LocalSend", isDirectory: true)
  }

  static func load() async throws -> Material {
    let folder = directory
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let p12 = folder.appendingPathComponent("identity.p12")
    let passphrase = passphraseValue()
    if !FileManager.default.fileExists(atPath: p12.path) { try await generate(into: folder, p12: p12, passphrase: passphrase) }
    return try material(from: p12, passphrase: passphrase)
  }

  static func sha256Hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

  static func fingerprint(of certificate: SecCertificate) -> String {
    sha256Hex(SecCertificateCopyData(certificate) as Data)
  }

  private static func passphraseValue() -> String {
    let key = "localSendIdentityPass"
    if let value = UserDefaults.standard.string(forKey: key) { return value }
    let value = (0..<24).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    UserDefaults.standard.set(value, forKey: key)
    return value
  }

  private static func generate(into folder: URL, p12: URL, passphrase: String) async throws {
    let key = folder.appendingPathComponent("key.pem").path
    let cert = folder.appendingPathComponent("cert.pem").path
    defer {
      try? FileManager.default.removeItem(atPath: key)
      try? FileManager.default.removeItem(atPath: cert)
    }
    let openssl = "/usr/bin/openssl"
    guard
      let made = await DropletProcess.run(
        openssl, ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert, "-days", "3650", "-subj", "/CN=Brim LocalSend"]),
      made.status == 0,
      let packed = await DropletProcess.run(
        openssl, ["pkcs12", "-export", "-inkey", key, "-in", cert, "-out", p12.path, "-passout", "pass:\(passphrase)"]),
      packed.status == 0
    else { throw Failure.generate }
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: p12.path)
  }

  private static func material(from p12: URL, passphrase: String) throws -> Material {
    guard let data = try? Data(contentsOf: p12) else { throw Failure.load }
    var items: CFArray?
    var options: [String: Any] = [kSecImportExportPassphrase as String: passphrase]
    // Keep the identity out of the user's keychain where the OS supports it (macOS 15+).
    if #available(macOS 15, *) { options[kSecImportToMemoryOnly as String] = true }
    guard SecPKCS12Import(data as CFData, options as CFDictionary, &items) == errSecSuccess,
      let first = (items as? [[String: Any]])?.first,
      let identityRef = first[kSecImportItemIdentity as String]
    else { throw Failure.load }
    let identity = identityRef as! SecIdentity  // CF type check is the cast itself
    var certificate: SecCertificate?
    guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else { throw Failure.load }
    return Material(identity: identity, fingerprint: fingerprint(of: certificate))
  }
}
