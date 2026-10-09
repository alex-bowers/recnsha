import Foundation

/// An upload as returned by the share server.
struct UploadedFile: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case image
        case video
    }

    let id: String
    let kind: Kind
    let size: Int
    /// Milliseconds since 1970.
    let createdAt: Double
    let page: URL
    let file: URL
    let gif: URL?
    let markdown: String

    var createdDate: Date {
        Date(timeIntervalSince1970: createdAt / 1000)
    }

    func menuTitle(relativeTo now: Date, locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        let name = kind == .image ? "Screenshot" : "Recording"
        return "\(name), \(formatter.localizedString(for: createdDate, relativeTo: now))"
    }
}
