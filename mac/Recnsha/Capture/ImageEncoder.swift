import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CaptureError: LocalizedError {
    case noDisplay
    case windowNotFound
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .noDisplay: "The selected area is not on a display."
        case .windowNotFound: "That window closed before it could be captured."
        case .encodingFailed: "The screenshot could not be converted to PNG."
        }
    }
}

enum ImageEncoder {
    static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CaptureError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CaptureError.encodingFailed }
        return data as Data
    }
}
