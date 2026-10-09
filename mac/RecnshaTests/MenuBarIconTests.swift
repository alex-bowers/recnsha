import AppKit
import Testing
@testable import Recnsha

@MainActor
struct MenuBarIconTests {
    @Test func drawsTheCameraOnTheOneTimesPixelGrid() {
        #expect(MenuBarIcon.cameraPixels.allSatisfy { $0.count == MenuBarIcon.cameraPixels[0].count })
        #expect(MenuBarIcon.cameraPixels[0].count == 19)
        #expect(MenuBarIcon.cameraPixels.count == 15)
    }

    @Test func offersOneTimesAndRetinaVersions() throws {
        let image = MenuBarIcon.camera()
        let pixelSizes = image.representations.map { "\($0.pixelsWide)x\($0.pixelsHigh)" }

        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 19, height: 15))
        #expect(pixelSizes.contains("19x15"))
        #expect(pixelSizes.contains("38x30"))
    }

    @Test func drawsTheOneTimesCameraTheRightWayUp() throws {
        let rep = try #require(MenuBarIcon.camera().representations.first { $0.pixelsWide == 19 } as? NSBitmapImageRep)
        // Row 1 is the top bump, so its left edge is clear; upside down it would be the solid body.
        #expect(rep.colorAt(x: 0, y: 1)?.alphaComponent == 0)
        #expect(rep.colorAt(x: 9, y: 0)?.alphaComponent == 1)
        #expect(rep.colorAt(x: 0, y: 3)?.alphaComponent == 1)
    }

    @Test func drawsTheRetinaCamera() throws {
        let rep = try #require(MenuBarIcon.camera().representations.first { $0.pixelsWide == 38 } as? NSBitmapImageRep)
        let solid = (0..<rep.pixelsHigh).flatMap { y in (0..<rep.pixelsWide).map { x in (x, y) } }
            .filter { (rep.colorAt(x: $0.0, y: $0.1)?.alphaComponent ?? 0) > 0.5 }
        // The camera body covers well over a third of the icon.
        #expect(solid.count > rep.pixelsWide * rep.pixelsHigh / 3)
    }
}
