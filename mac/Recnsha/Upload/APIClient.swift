import Foundation

enum APIError: LocalizedError, Equatable {
    case unauthorised
    case server(status: Int, message: String)
    case invalidResponse
    case emptyFile
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .unauthorised:
            "The server rejected the upload token. Check it in Settings."
        case .server(let status, let message):
            "The server returned \(status): \(message)."
        case .invalidResponse:
            "The server sent a response Recnsha could not read."
        case .emptyFile:
            "The file is empty."
        case .notConfigured:
            "Recnsha isn't set up. Add the server address and upload token in Settings."
        }
    }
}

/// Talks to the share server's /api routes. See server/README.md.
struct APIClient {
    let baseURL: URL
    let token: String
    var session: URLSession = .shared

    func upload(_ data: Data, contentType: String) async throws -> UploadedFile {
        var request = makeRequest(path: "api/uploads", method: "POST")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (body, response) = try await session.upload(for: request, from: data)
        return try decode(UploadedFile.self, body: body, response: response, expecting: 201)
    }

    /// One page of uploads, newest first. Pass the previous page's `nextCursor` as `before` to continue.
    func listUploads(limit: Int, before cursor: Int? = nil) async throws -> UploadPage {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: String(cursor))) }
        let request = makeRequest(path: "api/uploads", method: "GET", query: query)
        let (body, response) = try await session.data(for: request)
        return try decode(UploadPage.self, body: body, response: response, expecting: 200)
    }

    func recentUploads(limit: Int) async throws -> [UploadedFile] {
        try await listUploads(limit: limit).uploads
    }

    func delete(id: String) async throws {
        let request = makeRequest(path: "api/uploads/\(id)", method: "DELETE")
        let (body, response) = try await session.data(for: request)
        try check(body: body, response: response, expecting: 204)
    }

    /// Uploads a file in parts, as the server requires for anything over 50 MB.
    /// If any step fails, the unfinished upload is deleted before the error is rethrown.
    func uploadInParts(fileAt url: URL, contentType: String, partSize: Int = 20 * 1024 * 1024) async throws -> UploadedFile {
        var start = makeRequest(path: "api/uploads/multipart", method: "POST")
        start.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (startBody, startResponse) = try await session.upload(for: start, from: JSONEncoder().encode(["contentType": contentType]))
        let id = try decode(StartedUpload.self, body: startBody, response: startResponse, expecting: 201).id

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            var parts: [UploadedPart] = []
            while let chunk = try handle.read(upToCount: partSize), !chunk.isEmpty {
                var request = makeRequest(path: "api/uploads/\(id)/parts/\(parts.count + 1)", method: "PUT")
                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                let (body, response) = try await session.upload(for: request, from: chunk)
                parts.append(try decode(UploadedPart.self, body: body, response: response, expecting: 200))
            }
            guard !parts.isEmpty else { throw APIError.emptyFile }

            var complete = makeRequest(path: "api/uploads/\(id)/complete", method: "POST")
            complete.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (body, response) = try await session.upload(for: complete, from: JSONEncoder().encode(Completion(parts: parts)))
            return try decode(UploadedFile.self, body: body, response: response, expecting: 200)
        } catch {
            try? await delete(id: id)
            throw error
        }
    }

    /// Adds or replaces a recording's GIF preview.
    func uploadGIF(_ data: Data, forUpload id: String) async throws -> UploadedFile {
        var request = makeRequest(path: "api/uploads/\(id)/gif", method: "PUT")
        request.setValue("image/gif", forHTTPHeaderField: "Content-Type")
        let (body, response) = try await session.upload(for: request, from: data)
        return try decode(UploadedFile.self, body: body, response: response, expecting: 200)
    }

    private func makeRequest(path: String, method: String, query: [URLQueryItem] = []) -> URLRequest {
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func check(body: Data, response: URLResponse, expecting status: Int) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 { throw APIError.unauthorised }
        guard http.statusCode == status else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw APIError.server(status: http.statusCode, message: message)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, body: Data, response: URLResponse, expecting status: Int) throws -> T {
        try check(body: body, response: response, expecting: status)
        do {
            return try JSONDecoder().decode(type, from: body)
        } catch {
            throw APIError.invalidResponse
        }
    }
}

struct UploadPage: Decodable {
    let uploads: [UploadedFile]
    let nextCursor: Int?
}

private struct ErrorBody: Decodable {
    let error: String
}

struct UploadedPart: Codable, Equatable {
    let partNumber: Int
    let etag: String
}

private struct StartedUpload: Decodable {
    let id: String
}

private struct Completion: Encodable {
    let parts: [UploadedPart]
}
