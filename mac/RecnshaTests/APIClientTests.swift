import Foundation
import Testing
@testable import Recnsha

let sampleUploadJSON = """
{"id":"AbCdEfGhIjKl","kind":"image","size":10,"createdAt":1791460000000,\
"page":"https://share.example.com/AbCdEfGhIjKl","file":"https://share.example.com/AbCdEfGhIjKl.png",\
"gif":null,"markdown":"![Screenshot](https://share.example.com/AbCdEfGhIjKl.png)"}
"""

/// Answers requests with canned responses and records each request.
nonisolated final class StubURLProtocol: URLProtocol {
    struct Recorded {
        let method: String
        let path: String
        let body: Data
    }

    nonisolated(unsafe) private static var responder: (URLRequest) -> (Int, String) = { _ in (200, "") }
    nonisolated(unsafe) static var requests: [Recorded] = []
    nonisolated(unsafe) static var lastRequest: URLRequest?

    static func respond(status: Int, body: String) {
        respond { _ in (status, body) }
    }

    static func respond(with responder: @escaping (URLRequest) -> (Int, String)) {
        self.responder = responder
        requests = []
        lastRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.readAll) ?? Data()
        Self.lastRequest = request
        Self.requests.append(Recorded(method: request.httpMethod ?? "GET", path: request.url?.path() ?? "", body: body))

        let (status, text) = Self.responder(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

@Suite(.serialized)
@MainActor
struct APIClientTests {
    let client: APIClient

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        client = APIClient(
            baseURL: URL(string: "https://share.example.com")!,
            token: "secret",
            session: URLSession(configuration: configuration)
        )
    }

    @Test func uploadsWithTokenAndContentType() async throws {
        StubURLProtocol.respond(status: 201, body: sampleUploadJSON)

        let file = try await client.upload(Data([1, 2, 3]), contentType: "image/png")

        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://share.example.com/api/uploads")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "image/png")
        #expect(file.id == "AbCdEfGhIjKl")
        #expect(file.kind == .image)
        #expect(file.page == URL(string: "https://share.example.com/AbCdEfGhIjKl"))
    }

    @Test func reportsARejectedToken() async {
        StubURLProtocol.respond(status: 401, body: #"{"error":"Unauthorised"}"#)
        await #expect(throws: APIError.unauthorised) {
            try await client.upload(Data([1]), contentType: "image/png")
        }
    }

    @Test func reportsServerErrors() async {
        StubURLProtocol.respond(status: 415, body: #"{"error":"Unsupported content type"}"#)
        await #expect(throws: APIError.server(status: 415, message: "Unsupported content type")) {
            try await client.upload(Data([1]), contentType: "image/png")
        }
    }

    @Test func listsRecentUploads() async throws {
        StubURLProtocol.respond(status: 200, body: #"{"uploads":[\#(sampleUploadJSON)],"nextCursor":null}"#)

        let uploads = try await client.recentUploads(limit: 10)

        #expect(StubURLProtocol.lastRequest?.url?.absoluteString == "https://share.example.com/api/uploads?limit=10")
        #expect(uploads.map(\.id) == ["AbCdEfGhIjKl"])
    }

    @Test func pagesThroughUploads() async throws {
        StubURLProtocol.respond(status: 200, body: #"{"uploads":[\#(sampleUploadJSON)],"nextCursor":42}"#)

        let page = try await client.listUploads(limit: 40, before: 99)

        #expect(StubURLProtocol.lastRequest?.url?.absoluteString == "https://share.example.com/api/uploads?limit=40&cursor=99")
        #expect(page.uploads.map(\.id) == ["AbCdEfGhIjKl"])
        #expect(page.nextCursor == 42)
    }

    private func multipartResponder(failingPart: Int? = nil) -> (URLRequest) -> (Int, String) {
        { request in
            let path = request.url?.path() ?? ""
            switch (request.httpMethod ?? "", path) {
            case ("POST", "/api/uploads/multipart"):
                return (201, #"{"id":"AbCdEfGhIjKl"}"#)
            case ("PUT", _) where path.hasPrefix("/api/uploads/AbCdEfGhIjKl/parts/"):
                let number = Int(path.split(separator: "/").last ?? "") ?? 0
                if number == failingPart { return (500, #"{"error":"Internal error"}"#) }
                return (200, #"{"partNumber":\#(number),"etag":"etag-\#(number)"}"#)
            case ("POST", "/api/uploads/AbCdEfGhIjKl/complete"):
                return (200, sampleUploadJSON)
            case ("DELETE", "/api/uploads/AbCdEfGhIjKl"):
                return (204, "")
            default:
                return (404, #"{"error":"Not found"}"#)
            }
        }
    }

    private func makeFile(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
        try Data(contents.utf8).write(to: url)
        return url
    }

    @Test func uploadsLargeFilesInParts() async throws {
        let fileURL = try makeFile("abcdefghij")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        StubURLProtocol.respond(with: multipartResponder())

        let file = try await client.uploadInParts(fileAt: fileURL, contentType: "video/mp4", partSize: 4)

        let requests = StubURLProtocol.requests
        #expect(requests.map { "\($0.method) \($0.path)" } == [
            "POST /api/uploads/multipart",
            "PUT /api/uploads/AbCdEfGhIjKl/parts/1",
            "PUT /api/uploads/AbCdEfGhIjKl/parts/2",
            "PUT /api/uploads/AbCdEfGhIjKl/parts/3",
            "POST /api/uploads/AbCdEfGhIjKl/complete",
        ])
        #expect(try JSONDecoder().decode([String: String].self, from: requests[0].body) == ["contentType": "video/mp4"])
        #expect(requests[1...3].map { String(decoding: $0.body, as: UTF8.self) } == ["abcd", "efgh", "ij"])

        struct Completion: Decodable { let parts: [UploadedPart] }
        let completion = try JSONDecoder().decode(Completion.self, from: requests[4].body)
        #expect(completion.parts == [
            UploadedPart(partNumber: 1, etag: "etag-1"),
            UploadedPart(partNumber: 2, etag: "etag-2"),
            UploadedPart(partNumber: 3, etag: "etag-3"),
        ])
        #expect(file.id == "AbCdEfGhIjKl")
    }

    @Test func deletesTheUnfinishedUploadWhenAPartFails() async throws {
        let fileURL = try makeFile("abcdefghij")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        StubURLProtocol.respond(with: multipartResponder(failingPart: 2))

        await #expect(throws: APIError.server(status: 500, message: "Internal error")) {
            try await client.uploadInParts(fileAt: fileURL, contentType: "video/mp4", partSize: 4)
        }
        let last = try #require(StubURLProtocol.requests.last)
        #expect("\(last.method) \(last.path)" == "DELETE /api/uploads/AbCdEfGhIjKl")
    }

    @Test func refusesEmptyFiles() async throws {
        let fileURL = try makeFile("")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        StubURLProtocol.respond(with: multipartResponder())

        await #expect(throws: APIError.emptyFile) {
            try await client.uploadInParts(fileAt: fileURL, contentType: "video/mp4", partSize: 4)
        }
    }

    @Test func uploadsGIFsForRecordings() async throws {
        StubURLProtocol.respond(status: 200, body: sampleUploadJSON)

        _ = try await client.uploadGIF(Data("GIF89a".utf8), forUpload: "AbCdEfGhIjKl")

        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path() == "/api/uploads/AbCdEfGhIjKl/gif")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "image/gif")
    }

    @Test func deletesManyUploadsInOrderWithProgress() async {
        StubURLProtocol.respond(status: 204, body: "")
        var progress: [Int] = []

        let result = await BulkDelete.run(ids: ["aaaaaaaaaaaa", "bbbbbbbbbbbb", "cccccccccccc"], using: client) { progress.append($0) }

        #expect(StubURLProtocol.requests.map { "\($0.method) \($0.path)" } == [
            "DELETE /api/uploads/aaaaaaaaaaaa",
            "DELETE /api/uploads/bbbbbbbbbbbb",
            "DELETE /api/uploads/cccccccccccc",
        ])
        #expect(progress == [1, 2, 3])
        #expect(result.deleted == ["aaaaaaaaaaaa", "bbbbbbbbbbbb", "cccccccccccc"])
        #expect(result.failed.isEmpty)
    }

    @Test func carriesOnAfterAFailedDeleteAndTreatsMissingAsDeleted() async {
        StubURLProtocol.respond { request in
            switch request.url?.lastPathComponent {
            case "bbbbbbbbbbbb": (500, #"{"error":"Internal error"}"#)
            case "cccccccccccc": (404, #"{"error":"Not found"}"#)
            default: (204, "")
            }
        }

        let result = await BulkDelete.run(ids: ["aaaaaaaaaaaa", "bbbbbbbbbbbb", "cccccccccccc"], using: client)

        #expect(result.deleted == ["aaaaaaaaaaaa", "cccccccccccc"])
        #expect(result.failed == ["bbbbbbbbbbbb": "The server returned 500: Internal error."])
    }

    @Test func deletesUploads() async throws {
        StubURLProtocol.respond(status: 204, body: "")

        try await client.delete(id: "AbCdEfGhIjKl")

        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.absoluteString == "https://share.example.com/api/uploads/AbCdEfGhIjKl")
    }
}
