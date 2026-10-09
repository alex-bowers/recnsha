import ImageIO
import SwiftUI

/// Decodes a small version of an image, so a Library card never holds a full-size screenshot in memory.
nonisolated enum ThumbnailDecoder {
    static func thumbnail(from data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}

/// A Library thumbnail. The file comes through the shared URL cache; only a downsampled copy is kept.
struct Thumbnail: View {
    let url: URL

    /// Twice the widest Library card, for Retina displays.
    private static let maxPixelSize = 640

    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else if failed {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        image = nil
        failed = false
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                failed = true
                return
            }
            let maxPixelSize = Self.maxPixelSize
            // Decoding a large PNG is slow, so it runs off the main thread.
            let decoded = await Task.detached(priority: .utility) {
                ThumbnailDecoder.thumbnail(from: data, maxPixelSize: maxPixelSize)
            }.value
            image = decoded
            failed = decoded == nil
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}
