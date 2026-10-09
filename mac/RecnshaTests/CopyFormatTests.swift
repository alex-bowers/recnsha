import Foundation
import Testing
@testable import Recnsha

@MainActor
struct CopyFormatTests {
    private func makeFile(kind: UploadedFile.Kind, gif: Bool = false) -> UploadedFile {
        let base = "https://share.example.com/AbCdEfGhIjKl"
        let fileExtension = kind == .image ? "png" : "mp4"
        return UploadedFile(
            id: "AbCdEfGhIjKl", kind: kind, size: 10, createdAt: 0,
            page: URL(string: base)!,
            file: URL(string: "\(base).\(fileExtension)")!,
            gif: gif ? URL(string: "\(base).gif")! : nil,
            markdown: "![Screenshot](\(base).\(fileExtension))"
        )
    }

    @Test func copiesThePageLink() {
        #expect(makeFile(kind: .image).text(for: .pageLink) == "https://share.example.com/AbCdEfGhIjKl")
    }

    @Test func copiesTheServerMarkdown() {
        #expect(makeFile(kind: .image).text(for: .markdown) == "![Screenshot](https://share.example.com/AbCdEfGhIjKl.png)")
    }

    @Test func copiesTheDirectImageLink() {
        #expect(makeFile(kind: .image).text(for: .imageLink) == "https://share.example.com/AbCdEfGhIjKl.png")
        #expect(makeFile(kind: .video, gif: true).text(for: .imageLink) == "https://share.example.com/AbCdEfGhIjKl.gif")
        #expect(makeFile(kind: .video).text(for: .imageLink) == "https://share.example.com/AbCdEfGhIjKl.mp4")
    }
}
