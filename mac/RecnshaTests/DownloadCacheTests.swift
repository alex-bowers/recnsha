import Foundation
import Testing
@testable import Recnsha

@MainActor
struct DownloadCacheTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "DownloadCacheTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    private func makeFile(id: String, kind: UploadedFile.Kind = .video) -> UploadedFile {
        let fileExtension = kind == .video ? "mp4" : "png"
        return UploadedFile(
            id: id, kind: kind, size: 3, createdAt: 0,
            page: URL(string: "https://share.example.com/\(id)")!,
            file: URL(string: "https://share.example.com/\(id).\(fileExtension)")!,
            gif: nil, markdown: ""
        )
    }

    /// A downloader that writes a small file and counts how often it is called.
    private final class FakeDownloader {
        var calls = 0
        func download(_ url: URL) async throws -> URL {
            calls += 1
            let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try Data(url.lastPathComponent.utf8).write(to: temporary)
            return temporary
        }
    }

    @Test func downloadsOnceAndNamesFilesByKind() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let downloader = FakeDownloader()
        let cache = DownloadCache(directory: directory, maximumFiles: 5, downloader: downloader.download)
        let video = makeFile(id: "AbCdEfGhIjKl")
        #expect(cache.cachedURL(for: video) == nil)

        let first = try await cache.fetch(video)
        let second = try await cache.fetch(video)

        #expect(first == second)
        #expect(downloader.calls == 1)
        #expect(first.lastPathComponent == "Recording-AbCdEfGhIjKl.mp4")
        #expect(cache.cachedURL(for: video) == first)
        #expect(try String(contentsOf: first, encoding: .utf8) == "AbCdEfGhIjKl.mp4")

        let screenshot = try await cache.fetch(makeFile(id: "ScReEnShOt01", kind: .image))
        #expect(screenshot.lastPathComponent == "Screenshot-ScReEnShOt01.png")
    }

    @Test func keepsOnlyTheMostRecentFiles() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let downloader = FakeDownloader()
        let cache = DownloadCache(directory: directory, maximumFiles: 2, downloader: downloader.download)
        let files = ["aaaaaaaaaaaa", "bbbbbbbbbbbb", "cccccccccccc"].map { makeFile(id: $0) }

        for file in files {
            _ = try await cache.fetch(file)
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(cache.cachedURL(for: files[0]) == nil)
        #expect(cache.cachedURL(for: files[1]) != nil)
        #expect(cache.cachedURL(for: files[2]) != nil)

        cache.discard([files[2]])
        #expect(cache.cachedURL(for: files[2]) == nil)
    }
}
