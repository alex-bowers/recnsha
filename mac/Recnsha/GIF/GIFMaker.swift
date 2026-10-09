@preconcurrency import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum GIFError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        "The GIF could not be created."
    }
}

/// Turns a segment of a recording into a looping GIF.
enum GIFMaker {
    static let maximumDuration: Double = 6
    static let framesPerSecond = 12
    static let maximumWidth: CGFloat = 640

    /// Clamps a requested segment so it lies inside the video and lasts at most `maximumDuration`.
    static func segment(start: Double, length: Double, videoDuration: Double) -> ClosedRange<Double> {
        let length = max(min(length, maximumDuration, videoDuration), 0)
        let start = min(max(start, 0), max(videoDuration - length, 0))
        return start...(start + length)
    }

    static func frameTimes(for segment: ClosedRange<Double>, framesPerSecond: Int) -> [Double] {
        let count = max(Int(((segment.upperBound - segment.lowerBound) * Double(framesPerSecond)).rounded()), 1)
        return (0..<count).map { segment.lowerBound + Double($0) / Double(framesPerSecond) }
    }

    static func encode(_ frames: [CGImage], framesPerSecond: Int) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frames.count, nil) else {
            throw GIFError.encodingFailed
        }
        let loopForever = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(destination, loopForever as CFDictionary)
        let frameDelay = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(framesPerSecond)]]
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameDelay as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw GIFError.encodingFailed }
        return data as Data
    }

    static func makeGIF(from videoURL: URL, segment: ClosedRange<Double>) async throws -> Data {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
        generator.appliesPreferredTrackTransform = true
        // Limits the width; the large height bound keeps the aspect ratio for any shape of recording.
        generator.maximumSize = CGSize(width: maximumWidth, height: maximumWidth * 10)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        var frames: [CGImage] = []
        for seconds in frameTimes(for: segment, framesPerSecond: framesPerSecond) {
            let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
            frames.append(image)
        }
        return try encode(frames, framesPerSecond: framesPerSecond)
    }
}
