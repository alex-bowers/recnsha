import CoreGraphics
import Testing
@testable import Recnsha

@MainActor
struct GeometryTests {
    @Test func flipsRectsBetweenCoordinateSpaces() {
        let appKit = CGRect(x: 10, y: 700, width: 100, height: 200)
        let display = Geometry.flip(appKit, primaryHeight: 1000)
        #expect(display == CGRect(x: 10, y: 100, width: 100, height: 200))
        #expect(Geometry.flip(display, primaryHeight: 1000) == appKit)
    }

    @Test func flipsPoints() {
        #expect(Geometry.flip(CGPoint(x: 5, y: 900), primaryHeight: 1000) == CGPoint(x: 5, y: 100))
    }

    @Test func normalisesDragsInAnyDirection() {
        let rect = Geometry.rect(from: CGPoint(x: 50, y: 80), to: CGPoint(x: 10, y: 20))
        #expect(rect == CGRect(x: 10, y: 20, width: 40, height: 60))
    }

    @Test func picksTheFrontmostWindowUnderThePointer() {
        let front = WindowInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let back = WindowInfo(id: 2, frame: CGRect(x: 0, y: 0, width: 500, height: 500))
        let windows = [front, back]

        #expect(WindowList.topmost(at: CGPoint(x: 50, y: 50), in: windows) == front)
        #expect(WindowList.topmost(at: CGPoint(x: 200, y: 200), in: windows) == back)
        #expect(WindowList.topmost(at: CGPoint(x: 600, y: 600), in: windows) == nil)
    }
}
