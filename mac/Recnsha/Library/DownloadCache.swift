import AppKit
import UniformTypeIdentifiers

/// Keeps local copies of recently used uploads so they can be dragged out of the Library as files,
/// for example into a GitHub comment, which attaches them. Only the most recent files are kept.
@MainActor
final class DownloadCache {
    static let shared = DownloadCache(
        directory: URL.cachesDirectory.appending(path: "Recnsha/Downloads", directoryHint: .isDirectory)
    )

    private let directory: URL
    private let maximumFiles: Int
    private let downloader: (URL) async throws -> URL
    private var inFlight: [String: Task<URL, Error>] = [:]

    init(directory: URL, maximumFiles: Int = 20, downloader: @escaping (URL) async throws -> URL = DownloadCache.download) {
        self.directory = directory
        self.maximumFiles = maximumFiles
        self.downloader = downloader
    }

    /// The local copy, if it has been downloaded.
    func cachedURL(for file: UploadedFile) -> URL? {
        let url = localURL(for: file)
        return FileManager.default.fileExists(atPath: url.path()) ? url : nil
    }

    /// Returns the local copy, downloading it first if needed. Concurrent requests share one download.
    @discardableResult
    func fetch(_ file: UploadedFile) async throws -> URL {
        if let cached = cachedURL(for: file) { return cached }
        if let running = inFlight[file.id] { return try await running.value }

        let destination = localURL(for: file)
        let task = Task { [downloader, directory] in
            let downloaded = try await downloader(file.file)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: downloaded, to: destination)
            return destination
        }
        inFlight[file.id] = task
        defer { inFlight[file.id] = nil }

        let url = try await task.value
        removeOldFiles()
        return url
    }

    /// Removes local copies, for example of deleted uploads.
    func discard(_ files: [UploadedFile]) {
        for file in files {
            try? FileManager.default.removeItem(at: localURL(for: file))
        }
    }

    /// Starts downloading in the background, so a drag can hand over a real file straight away.
    func prefetch(_ file: UploadedFile) {
        Task { _ = try? await fetch(file) }
    }

    /// A drag item for the upload's file. A cached file is handed over directly, which browsers accept.
    /// Otherwise the file is promised and delivered once downloaded, which apps such as Finder accept.
    func dragItem(for file: UploadedFile) -> NSItemProvider {
        if let url = cachedURL(for: file), let provider = NSItemProvider(contentsOf: url) {
            return provider
        }
        let provider = NSItemProvider()
        provider.suggestedName = localURL(for: file).deletingPathExtension().lastPathComponent
        let type = UTType(filenameExtension: file.file.pathExtension) ?? .data
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
            Task { @MainActor in
                do {
                    completion(try await self.fetch(file), false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return nil
        }
        return provider
    }

    private func localURL(for file: UploadedFile) -> URL {
        let name = file.kind == .video ? "Recording" : "Screenshot"
        return directory.appending(path: "\(name)-\(file.id).\(file.file.pathExtension)")
    }

    private func removeOldFiles() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
        let newestFirst = files.sorted {
            let first = (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            let second = (try? $1.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            return first > second
        }
        for file in newestFirst.dropFirst(maximumFiles) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    nonisolated static func download(_ url: URL) async throws -> URL {
        let (downloaded, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.invalidResponse }
        return downloaded
    }
}
