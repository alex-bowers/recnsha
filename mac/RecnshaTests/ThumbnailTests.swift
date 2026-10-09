import CoreGraphics
import Foundation
import Testing
@testable import Recnsha

@MainActor
struct ThumbnailTests {
    private func png(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try ImageEncoder.png(try #require(context.makeImage()))
    }

    @Test func shrinksLargeImagesKeepingTheirShape() throws {
        let thumbnail = try #require(ThumbnailDecoder.thumbnail(from: try png(width: 2000, height: 1000), maxPixelSize: 640))
        #expect(thumbnail.width == 640)
        #expect(thumbnail.height == 320)
    }

    @Test func leavesSmallImagesAtTheirSize() throws {
        let thumbnail = try #require(ThumbnailDecoder.thumbnail(from: try png(width: 100, height: 50), maxPixelSize: 640))
        #expect(thumbnail.width == 100)
        #expect(thumbnail.height == 50)
    }

    @Test func rejectsDataThatIsNotAnImage() {
        #expect(ThumbnailDecoder.thumbnail(from: Data("not an image".utf8), maxPixelSize: 640) == nil)
    }
}
