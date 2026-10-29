// ClipyImporter.swift
// Brim
//
// Reads Clipy's clip files (NSKeyedArchiver plists named *.data) and exported snippet XML without
// knowing Clipy's classes: the archive's object table is scanned for the text it holds.
// Everything is read-only.

import Foundation

enum ClipyImporter {
    static var folders: [URL] {
        let home = ClipboardImporters.home
        return ["Library/Application Support/Clipy", "Library/Application Support/com.clipy-app.Clipy"]
            .map { home.appendingPathComponent($0) }
    }

    static func importHistory(from folders: [URL] = folders, limit: Int = 500) -> ClipboardImportResult {
        let files = FileManager.default
        var found: [(URL, Date)] = []
        for folder in folders {
            guard let walker = files.enumerator(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for case let url as URL in walker where ["data", "xml"].contains(url.pathExtension.lowercased()) {
                found.append((url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now))
            }
        }
        guard !found.isEmpty else { return .unavailable("Clipy’s history wasn’t found on this Mac.") }
        var items: [ClipboardImportItem] = []
        for (url, date) in found.sorted(by: { $0.1 > $1.1 }).prefix(limit) {
            guard let data = try? Data(contentsOf: url), data.count < 2_000_000 else { continue }
            let texts = url.pathExtension.lowercased() == "xml" ? snippets(inXML: data) : [text(inKeyedArchive: data)].compactMap { $0 }
            items += texts.map { ClipboardImportItem(text: $0, date: date, copies: 1, isPinned: false, sourceApp: nil) }
        }
        return items.isEmpty ? .unavailable("Clipy’s files were found but held no readable text.") : .items(items)
    }

    /// The copied text in a keyed archive: its longest plain string that isn't a type name or class marker.
    static func text(inKeyedArchive data: Data) -> String? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let objects = plist["$objects"] as? [Any] else { return nil }
        let strings = objects.compactMap { $0 as? String }.filter { value in
            value != "$null" && !value.hasPrefix("$") && !value.hasPrefix("public.") && !value.hasPrefix("com.apple.")
                && !value.hasPrefix("NS") && !value.hasPrefix("dyn.") && !value.hasSuffix("PboardType")
                && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return strings.max { $0.count < $1.count }
    }

    /// Snippet contents from Clipy's exported XML (`<snippet><title/><content/></snippet>`).
    static func snippets(inXML data: Data) -> [String] {
        let parser = SnippetParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.shouldResolveExternalEntities = false
        xml.parse()
        return parser.contents
    }

    private final class SnippetParser: NSObject, XMLParserDelegate {
        var contents: [String] = []
        private var inContent = false
        private var buffer = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            if name == "content" { inContent = true; buffer = "" }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if inContent { buffer += string } }
        func parser(_ parser: XMLParser, foundCDATA data: Data) {
            if inContent { buffer += String(decoding: data, as: UTF8.self) }
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            guard name == "content" else { return }
            inContent = false
            if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { contents.append(buffer) }
        }
    }
}
