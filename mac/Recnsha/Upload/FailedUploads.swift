import Foundation

/// Keeps captures whose upload failed so they can be retried. Nothing else is stored locally.
struct FailedUploads {
    let directory: URL

    static var standard: FailedUploads {
        FailedUploads(directory: URL.applicationSupportDirectory.appending(path: "Recnsha/Failed Uploads", directoryHint: .isDirectory))
    }

    static func contentType(forExtension fileExtension: String) -> String? {
        switch fileExtension.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "mp4": "video/mp4"
        default: nil
        }
    }

    func save(_ data: Data, fileExtension: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(UUID().uuidString).\(fileExtension)")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Moves a file, such as a finished recording, into the folder.
    func keep(fileAt source: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(UUID().uuidString).\(source.pathExtension)")
        try FileManager.default.moveItem(at: source, to: url)
        return url
    }

    func files() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { Self.contentType(forExtension: $0.pathExtension) != nil }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func remove(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
