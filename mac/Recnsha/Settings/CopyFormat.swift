import Foundation

/// What Recnsha copies to the clipboard after a capture.
enum CopyFormat: String, CaseIterable, Identifiable {
    case pageLink
    case markdown
    case imageLink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pageLink: "Share page link"
        case .markdown: "Markdown"
        case .imageLink: "Direct image link"
        }
    }

    /// Shown in the toast after copying.
    var confirmation: String {
        switch self {
        case .pageLink: "Link copied"
        case .markdown: "Markdown copied"
        case .imageLink: "Image link copied"
        }
    }
}

extension UploadedFile {
    func text(for format: CopyFormat) -> String {
        switch format {
        case .pageLink:
            page.absoluteString
        case .markdown:
            markdown
        case .imageLink:
            // A recording's GIF is the closest thing to an image; fall back to the video itself.
            (kind == .video ? gif ?? file : file).absoluteString
        }
    }
}
