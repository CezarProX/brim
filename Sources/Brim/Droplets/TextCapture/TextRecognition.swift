// TextRecognition.swift
// Brim
//
// On-device Vision: text recognition (auto or chosen language, optional correction) and
// QR / barcode detection. Everything runs locally.

import CoreGraphics
import Foundation
import Vision

struct DetectedCode: Equatable, Sendable {
  let payload: String
  let symbology: String
}

enum TextRecognition {
  /// Recognized text in reading order (top to bottom, then left to right).
  static func recognizeText(
    in image: CGImage, language: String = "auto", correction: Bool = true
  ) -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = correction
    if language == "auto" {
      request.automaticallyDetectsLanguage = true
    } else {
      request.automaticallyDetectsLanguage = false
      request.recognitionLanguages = [language]
    }
    do { try VNImageRequestHandler(cgImage: image).perform([request]) } catch { return "" }
    let observations = (request.results ?? []).sorted {
      let dy = $0.boundingBox.midY - $1.boundingBox.midY
      return abs(dy) > 0.012 ? dy > 0 : $0.boundingBox.minX < $1.boundingBox.minX
    }
    return observations
      .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
  }

  static func detectCodes(in image: CGImage) -> [DetectedCode] {
    let request = VNDetectBarcodesRequest()
    do { try VNImageRequestHandler(cgImage: image).perform([request]) } catch { return [] }
    var seen = Set<String>()
    return (request.results ?? []).compactMap { observation in
      guard let payload = observation.payloadStringValue, !payload.isEmpty, seen.insert(payload).inserted else { return nil }
      return DetectedCode(payload: String(payload.prefix(4000)), symbology: symbologyName(observation.symbology))
    }
  }

  static func symbologyName(_ symbology: VNBarcodeSymbology) -> String {
    switch symbology {
    case .qr: "QR code"
    case .ean13: "EAN-13"
    case .ean8: "EAN-8"
    case .upce: "UPC-E"
    case .code128: "Code 128"
    case .code39: "Code 39"
    case .code93: "Code 93"
    case .itf14: "ITF-14"
    case .pdf417: "PDF417"
    case .aztec: "Aztec"
    case .dataMatrix: "Data Matrix"
    default: symbology.rawValue.replacingOccurrences(of: "VNBarcodeSymbology", with: "")
    }
  }

  /// Languages Vision can read, as (code, display name), sorted by name.
  static func supportedLanguages() -> [(code: String, name: String)] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    let codes = (try? request.supportedRecognitionLanguages()) ?? ["en-US"]
    return codes.map { code in (code, Locale.current.localizedString(forIdentifier: code) ?? code) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }
}
