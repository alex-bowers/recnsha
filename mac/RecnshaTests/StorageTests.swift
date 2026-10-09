import CoreGraphics
import Foundation
import Testing
@testable import Recnsha

@MainActor
struct StorageTests {
    @Test func encodesPNG() throws {
        let context = try #require(CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try #require(context.makeImage())

        let data = try ImageEncoder.png(image)

        #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    @Test func keepsAndRemovesFailedUploads() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FailedUploads(directory: directory)
        #expect(store.files().isEmpty)

        let saved = try store.save(Data([1, 2, 3]), fileExtension: "png")
        #expect(store.files().map(\.lastPathComponent) == [saved.lastPathComponent])

        try store.remove(saved)
        #expect(store.files().isEmpty)
    }

    @Test func movesFailedRecordingsIntoTheFolder() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
        try Data([1, 2, 3]).write(to: source)
        let store = FailedUploads(directory: directory)

        let kept = try store.keep(fileAt: source)

        #expect(!FileManager.default.fileExists(atPath: source.path()))
        #expect(kept.pathExtension == "mp4")
        #expect(store.files().map(\.lastPathComponent) == [kept.lastPathComponent])
    }

    @Test func mapsExtensionsToContentTypes() {
        #expect(FailedUploads.contentType(forExtension: "PNG") == "image/png")
        #expect(FailedUploads.contentType(forExtension: "mp4") == "video/mp4")
        #expect(FailedUploads.contentType(forExtension: "txt") == nil)
    }

    @Test func titlesUploadsForTheMenu() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let file = UploadedFile(
            id: "AbCdEfGhIjKl", kind: .image, size: 10,
            createdAt: (now.timeIntervalSince1970 - 300) * 1000,
            page: URL(string: "https://share.example.com/AbCdEfGhIjKl")!,
            file: URL(string: "https://share.example.com/AbCdEfGhIjKl.png")!,
            gif: nil, markdown: ""
        )
        #expect(file.menuTitle(relativeTo: now, locale: Locale(identifier: "en_GB")) == "Screenshot, 5 minutes ago")
    }
}
