import Foundation
import ImageIO

/// The official thumbnail of the YouTube video that is playing, cropped to a square cover.
enum YouTubeThumbnail {
    static func videoID(from page: String) -> String? {
        guard let components = URLComponents(string: page), components.scheme == "https",
              ["music.youtube.com", "www.youtube.com"].contains(components.host ?? ""),
              components.path == "/watch",
              let id = components.queryItems?.first(where: { $0.name == "v" })?.value,
              id.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil else { return nil }
        return id
    }

    static func artworkURL(videoID: String) -> String? {
        guard videoID.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil else { return nil }
        return "https://i.ytimg.com/vi/\(videoID)/maxresdefault.jpg"
    }

    /// The square at the center of the picture; 4:3 thumbnails letterbox a 16:9 frame.
    static func squareCrop(width: Int, height: Int) -> CGRect {
        let letterboxed = abs(Double(width) / Double(max(1, height)) - 4.0 / 3.0) < 0.05
        let pictureHeight = letterboxed ? Int((Double(width) * 9 / 16).rounded()) : height
        let side = min(width, pictureHeight)
        return CGRect(x: (width - side) / 2, y: (height - pictureHeight) / 2 + (pictureHeight - side) / 2,
                      width: side, height: side)
    }

    static func isThumbnail(_ url: URL) -> Bool { url.host == "i.ytimg.com" && url.path.hasPrefix("/vi/") }

    /// Crops fetched thumbnail bytes to the square cover, as PNG.
    static func crop(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let square = image.cropping(to: squareCrop(width: image.width, height: image.height)) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, square, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

/// Resolves only the album link exposed by the live player. No title search or guessed cover.
enum NowPlayingAlbumArtwork {
    static func permitsRedirect(_ target: URL, requestedAlbum: URL) -> Bool {
        if NowPlayingSnapshot.safeAlbumURL(target.absoluteString) == requestedAlbum { return true }
        // In some regions YouTube sends a read-only consent interstitial redirect before the album.
        // We never submit its form or accept an agreement; a rendered interstitial simply yields no art.
        guard target.scheme == "https", target.host == "consent.youtube.com", target.path == "/m",
              target.user == nil, target.password == nil, target.port == nil,
              let continuation = URLComponents(url: target, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "continue" })?.value else { return false }
        return NowPlayingSnapshot.safeAlbumURL(continuation) == requestedAlbum
    }

    static func imageURL(html: String, expectedAlbum: String) -> URL? {
        guard html.utf8.count <= 1_500_000, !expectedAlbum.isEmpty,
              let tags = try? NSRegularExpression(pattern: #"<meta\b[^>]{0,8192}>"#, options: .caseInsensitive),
              let attributes = try? NSRegularExpression(pattern: #"\b(property|name|content)\s*=\s*(['"])(.*?)\2"#,
                                                        options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        var metadata: [String: String] = [:]
        for tag in tags.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let tagRange = Range(tag.range, in: html) else { continue }
            let text = String(html[tagRange])
            var fields: [String: String] = [:]
            for match in attributes.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let key = Range(match.range(at: 1), in: text), let value = Range(match.range(at: 3), in: text) else { continue }
                fields[String(text[key]).lowercased()] = decodeEntities(String(text[value]))
            }
            if let property = fields["property"] ?? fields["name"], let content = fields["content"] {
                metadata[property.lowercased()] = content
            }
        }
        guard let title = metadata["og:title"], normalized(title) == normalized(expectedAlbum),
              let image = metadata["og:image"] else { return nil }
        return NowPlayingSnapshot.safeArtworkURL(image)
    }

    private static func normalized(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func decodeEntities(_ value: String) -> String {
        var decoded = value
        if let regex = try? NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#) {
            for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
                guard let digits = Range(match.range(at: 1), in: value), let full = Range(match.range, in: decoded) else { continue }
                let raw = String(value[digits])
                let number = raw.hasPrefix("x") ? UInt32(raw.dropFirst(), radix: 16) : UInt32(raw)
                if let number, let scalar = UnicodeScalar(number) { decoded.replaceSubrange(full, with: String(scalar)) }
            }
        }
        for (entity, replacement) in [("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }
        return decoded
    }
}

/// Spotify's `artwork url` is the 300 px rendition; the same image id with the `b273` prefix is 640 px.
enum SpotifyArtwork {
    static func highResolution(_ url: URL) -> URL {
        guard url.host == "i.scdn.co", url.path.hasPrefix("/image/") else { return url }
        let id = url.lastPathComponent
        for small in ["ab67616d00001e02", "ab67616d00004851"] where id.hasPrefix(small) {
            let upgraded = "ab67616d0000b273" + id.dropFirst(small.count)
            return url.deletingLastPathComponent().appendingPathComponent(upgraded)
        }
        return url
    }
}

/// Decoded covers by image URL, so a repeat of a song (or a retry) never refetches and the cover
/// is never blank for a track already seen. Keyed by URL, which identifies the exact picture.
private let coverCache: NSCache<NSString, NSData> = {
    let cache = NSCache<NSString, NSData>()
    cache.countLimit = 24
    cache.totalCostLimit = 40_000_000
    return cache
}()

final class NowPlayingArtwork: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let requestedAlbum: URL?
    init(requestedAlbum: URL?) { self.requestedAlbum = requestedAlbum }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        let valid = request.url.flatMap {
            if let requestedAlbum { return NowPlayingAlbumArtwork.permitsRedirect($0, requestedAlbum: requestedAlbum) ? $0 : nil }
            return NowPlayingSnapshot.safeArtworkURL($0.absoluteString)
        } != nil
        completionHandler(valid ? request : nil)
    }

    static func load(_ snapshot: NowPlayingSnapshot) async -> Data? {
        if let raw = snapshot.artworkURL, let original = NowPlayingSnapshot.safeArtworkURL(raw) {
            let url = SpotifyArtwork.highResolution(original)
            if let cached = coverCache.object(forKey: url.absoluteString as NSString) { return cached as Data }
            let data = await loadImage(url, fallback: original)
            if let data { coverCache.setObject(data as NSData, forKey: url.absoluteString as NSString, cost: data.count) }
            return data
        }
        return await loadAlbumPage(snapshot)
    }

    private static func loadImage(_ url: URL, fallback original: URL) async -> Data? {
        if url != original {
            if let data = await fetch(url, albumPage: false) { return data }
            return await fetch(original, albumPage: false)
        }
        guard YouTubeThumbnail.isThumbnail(url) else { return await fetch(url, albumPage: false) }
        // Not every video has a full-resolution thumbnail; the high-quality one always exists.
        var data = await fetch(url, albumPage: false)
        if data == nil {
            data = await fetch(url.deletingLastPathComponent().appendingPathComponent("hqdefault.jpg"), albumPage: false)
        }
        return data.flatMap(YouTubeThumbnail.crop)
    }

    private static func loadAlbumPage(_ snapshot: NowPlayingSnapshot) async -> Data? {
        guard let raw = snapshot.albumURL, let url = NowPlayingSnapshot.safeAlbumURL(raw),
              let data = await fetch(url, albumPage: true), !Task.isCancelled,
              let html = String(data: data, encoding: .utf8),
              let artwork = NowPlayingAlbumArtwork.imageURL(html: html, expectedAlbum: snapshot.album) else { return nil }
        return await fetch(artwork, albumPage: false)
    }

    private static func fetch(_ url: URL, albumPage: Bool) async -> Data? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 7
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: NowPlayingArtwork(requestedAlbum: albumPage ? url : nil), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        if albumPage {
            // YouTube Music returns an unsupported-browser page to the URLSession user-agent.
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        }
        let limit = albumPage ? 1_500_000 : 5_000_000
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  response.expectedContentLength <= limit,
                  albumPage ? response.mimeType == "text/html" : response.mimeType?.hasPrefix("image/") == true else { return nil }
            var data = Data()
            for try await byte in bytes {
                guard data.count < limit, !Task.isCancelled else { return nil }
                data.append(byte)
            }
            return data
        } catch { return nil } // Optional artwork never interrupts the current song or its controls.
    }
}
