// Uploader.swift
// Brim
//
// Minimal multipart/form-data uploader used to POST a screenshot to the
// user-configured upload service (default: https://0x0.st) and parse back
// the resulting URL.

import Foundation

enum Uploader {

    enum UploadError: Error, LocalizedError {
        case invalidServiceURL(String)
        case serverError(status: Int, body: String)
        case emptyResponseBody
        case invalidResponseURL(String)
        case network(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .invalidServiceURL(let raw):
                return "The upload service URL \"\(raw)\" is invalid."
            case .serverError(let status, let body):
                let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedBody.isEmpty
                    ? "Upload failed with status \(status)."
                    : "Upload failed with status \(status): \(trimmedBody)"
            case .emptyResponseBody:
                return "The upload service returned an empty response."
            case .invalidResponseURL(let raw):
                return "The upload service returned an unrecognized response: \"\(raw)\"."
            case .network(let underlying):
                return "Network error while uploading: \(underlying.localizedDescription)"
            }
        }
    }

    private static let timeoutInterval: TimeInterval = 30
    private static let userAgent = "Brim/1.0"
    private static let fieldName = "file"
    private static let uploadFileName = "screenshot.png"

    /// Uploads `pngData` as multipart/form-data to `serviceURLString`, and
    /// returns the parsed URL from the plain-text response body.
    static func upload(pngData: Data, to serviceURLString: String) async throws -> URL {
        guard let serviceURL = URL(string: serviceURLString) else {
            throw UploadError.invalidServiceURL(serviceURLString)
        }

        let boundary = "Brim-\(UUID().uuidString)"
        var request = URLRequest(url: serviceURL, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(boundary: boundary, fieldName: fieldName, fileName: uploadFileName, data: pngData)

        let session = URLSession(configuration: sessionConfiguration())

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UploadError.network(underlying: error)
        }

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw UploadError.serverError(status: httpResponse.statusCode, body: body)
        }

        guard let rawBody = String(data: data, encoding: .utf8) else {
            throw UploadError.emptyResponseBody
        }

        let trimmed = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw UploadError.emptyResponseBody
        }

        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else {
            throw UploadError.invalidResponseURL(trimmed)
        }

        return url
    }

    private static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeoutInterval
        configuration.timeoutIntervalForResource = timeoutInterval
        return configuration
    }

    private static func multipartBody(boundary: String, fieldName: String, fileName: String, data: Data) -> Data {
        var body = Data()
        let lineBreak = "\r\n"

        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\(lineBreak)"
                .data(using: .utf8)!
        )
        body.append("Content-Type: image/png\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append(data)
        body.append(lineBreak.data(using: .utf8)!)
        body.append("--\(boundary)--\(lineBreak)".data(using: .utf8)!)

        return body
    }
}
