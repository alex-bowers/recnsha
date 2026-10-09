import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Recnsha

@MainActor
struct GIFMakerTests {
    @Test func limitsSegmentsToSixSecondsInsideTheVideo() {
        #expect(GIFMaker.segment(start: 2, length: 10, videoDuration: 20) == 2...8)
        #expect(GIFMaker.segment(start: 18, length: 6, videoDuration: 20) == 14...20)
        #expect(GIFMaker.segment(start: -1, length: 3, videoDuration: 20) == 0...3)
        #expect(GIFMaker.segment(start: 1, length: 6, videoDuration: 4) == 0...4)
    }

    @Test func spacesFramesEvenly() {
        let times = GIFMaker.frameTimes(for: 2...8, framesPerSecond: 12)
        #expect(times.count == 72)
        #expect(times.first == 2)
        #expect(abs((times.last ?? 0) - (8 - 1.0 / 12)) < 0.0001)
    }

    @Test func encodesALoopingGIF() throws {
        let frames = try (0..<3).map { _ in try makeFrame() }

        let data = try GIFMaker.encode(frames, framesPerSecond: 12)

        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == "com.compuserve.gif")
        #expect(CGImageSourceGetCount(source) == 3)

        let frame = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        let frameGIF = frame?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
        let delay = try #require(frameGIF?[kCGImagePropertyGIFDelayTime as String] as? Double)
        #expect(abs(delay - 1.0 / 12) < 0.01)

        let file = CGImageSourceCopyProperties(source, nil) as? [String: Any]
        let fileGIF = file?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
        #expect(fileGIF?[kCGImagePropertyGIFLoopCount as String] as? Int == 0)
    }

    private func makeFrame() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0, green: 0.5, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return try #require(context.makeImage())
    }
}
