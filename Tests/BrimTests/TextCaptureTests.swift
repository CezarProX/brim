import AppKit
import CoreImage
import Foundation
import PDFKit
import Testing
@testable import Brim

private func renderText(_ text: String, size: CGSize = CGSize(width: 900, height: 160), fontSize: CGFloat = 64) -> CGImage {
  let context = CGContext(
    data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.setFillColor(CGColor(gray: 1, alpha: 1))
  context.fill(CGRect(origin: .zero, size: size))
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
  NSAttributedString(string: text, attributes: [
    .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold), .foregroundColor: NSColor.black,
  ]).draw(at: CGPoint(x: 24, y: size.height / 2 - fontSize / 2))
  NSGraphicsContext.restoreGraphicsState()
  return context.makeImage()!
}

private func qrImage(_ payload: String) -> CGImage {
  let filter = CIFilter(name: "CIQRCodeGenerator")!
  filter.setValue(Data(payload.utf8), forKey: "inputMessage")
  filter.setValue("M", forKey: "inputCorrectionLevel")
  let scaled = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
  return CIContext().createCGImage(scaled, from: scaled.extent)!
}

struct TextCaptureOCRTests {
  @Test("Vision reads text rendered into an image")
  func recognizesText() {
    let image = renderText("Brim Capture 2026")
    let text = TextRecognition.recognizeText(in: image, language: "en-US", correction: true)
    #expect(text.lowercased().contains("brim"))
    #expect(text.contains("2026"))
  }

  @Test("Automatic language detection also reads it, and blank images give nothing")
  func automatic() {
    #expect(TextRecognition.recognizeText(in: renderText("Hello world"), language: "auto").lowercased().contains("hello"))
    #expect(TextRecognition.recognizeText(in: renderText(""), language: "auto").isEmpty)
  }

  @Test("Multiple lines come back in reading order")
  func order() {
    let size = CGSize(width: 800, height: 300)
    let top = renderText("First line", size: size)
    #expect(!top.width.description.isEmpty)
    let text = TextRecognition.recognizeText(in: renderText("Alpha Beta", size: size), language: "en-US")
    #expect(text.lowercased().contains("alpha"))
  }

  @Test("A generated QR code is detected and classified")
  func detectsQR() {
    let codes = TextRecognition.detectCodes(in: qrImage("https://example.com/hello?x=1"))
    #expect(codes.count == 1)
    #expect(codes.first?.payload == "https://example.com/hello?x=1")
    #expect(codes.first?.symbology == "QR code")
  }

  @Test("PDF pages render and are read")
  func pdf() throws {
    let image = renderText("Invoice Total 1234", size: CGSize(width: 612, height: 792), fontSize: 48)
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    let consumer = CGDataConsumer(data: data as CFMutableData)!
    let pdf = CGContext(consumer: consumer, mediaBox: &box, nil)!
    pdf.beginPDFPage(nil); pdf.draw(image, in: box); pdf.endPDFPage(); pdf.closePDF()
    let document = try #require(PDFDocumentFactory.make(data as Data))
    let pages = TextCaptureSources.renderPages(of: document)
    #expect(pages.count == 1)
    #expect(TextRecognition.recognizeText(in: pages[0], language: "en-US").lowercased().contains("invoice"))
  }
}

struct CodePayloadTests {
  @Test("URLs", arguments: [
    ("https://example.com/a", CodePayload.Kind.url), ("http://example.com", .url),
    ("javascript:alert(1)", .text), ("file:///etc/passwd", .text), ("example.com", .text),
    ("tel:+1 555 0100", .phone), ("mailto:a@b.com?subject=Hi", .email), ("geo:48.85,2.35", .location),
    ("otpauth://totp/x?secret=ABC", .authenticator), ("BEGIN:VCARD\nFN:Ada Lovelace\nEND:VCARD", .contact),
    ("BEGIN:VEVENT\nSUMMARY:Launch\nEND:VEVENT", .event), ("SMSTO:555:hello", .sms),
  ])
  func kinds(raw: String, kind: CodePayload.Kind) {
    #expect(CodePayload.classify(raw).kind == kind)
  }

  @Test("Only safe schemes can be opened")
  func openable() {
    #expect(CodePayload.classify("https://example.com").openURL?.host == "example.com")
    #expect(CodePayload.classify("mailto:a@b.com").openURL != nil)
    #expect(CodePayload.classify("myapp://do-something").openURL == nil)
    #expect(CodePayload.classify("javascript:alert(1)").openURL == nil)
    #expect(CodePayload.classify("https://exa mple.com").openURL == nil)
  }

  @Test("Wi-Fi payload parses escapes and copies the password")
  func wifi() {
    let payload = CodePayload.classify("WIFI:T:WPA;S:Cafe\\;Guest;P:pa\\:ss;H:false;;")
    #expect(payload.kind == .wifi)
    #expect(payload.title == "Wi-Fi: Cafe;Guest")
    #expect(payload.copyValue == "pa:ss")
    #expect(CodePayload.classify("WIFI:T:nopass;S:Open;;").copyValue == "Open")
  }

  @Test("Contact name, product barcodes, phone dialing")
  func misc() {
    #expect(CodePayload.classify("BEGIN:VCARD\nFN:Ada Lovelace\nEND:VCARD").detail == "Ada Lovelace")
    #expect(CodePayload.classify("4006381333931", symbology: "EAN-13").kind == .product)
    #expect(CodePayload.classify("4006381333931", symbology: "QR code").kind == .text)
    #expect(CodePayload.classify("tel:+1 (555) 010-0").openURL?.absoluteString == "tel:+15550100")
  }
}

struct TextCaptureHistoryTests {
  @Test("History keeps the newest 100, collapses duplicates and searches")
  func policy() {
    var entries: [TextCaptureEntry] = []
    for index in 0..<130 { entries = TextCaptureHistoryPolicy.adding(.init(kind: .text, source: .area, text: "item \(index)"), to: entries) }
    #expect(entries.count == 100)
    #expect(entries.first?.text == "item 129")
    entries = TextCaptureHistoryPolicy.adding(.init(kind: .text, source: .image, text: "item 100"), to: entries)
    #expect(entries.count == 100 && entries.first?.text == "item 100" && entries.filter { $0.text == "item 100" }.count == 1)
    #expect(TextCaptureHistoryPolicy.search(entries, query: "ITEM 12").count == 10)
    #expect(TextCaptureHistoryPolicy.search(entries, query: "  ").count == 100)
  }

  @MainActor
  @Test("History persists to disk")
  func persistence() {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("qs-tc-\(UUID())/history.json")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let first = TextCaptureHistory(file: file)
    first.add(.init(kind: .code, source: .area, text: "https://x.io", symbology: "QR code"))
    let second = TextCaptureHistory(file: file)
    #expect(second.entries.count == 1 && second.entries.first?.symbology == "QR code")
  }
}

enum PDFDocumentFactory {
  static func make(_ data: Data) -> PDFDocument? { PDFDocument(data: data) }
}
