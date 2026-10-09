import CoreGraphics
import Testing
@testable import Recnsha

@MainActor
struct DisplayAreaTests {
    private let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let external = CGRect(x: 1512, y: -200, width: 2560, height: 1440)

    @Test func returnsTheAreaRelativeToItsDisplay() {
        let result = DisplayArea.locate(CGRect(x: 1612, y: -100, width: 400, height: 300), inDisplays: [builtIn, external])
        #expect(result?.displayIndex == 1)
        #expect(result?.sourceRect == CGRect(x: 100, y: 100, width: 400, height: 300))
    }

    @Test func usesTheDisplayHoldingTheCentreAndClipsToIt() {
        // Mostly on the built-in display, crossing onto the external one.
        let result = DisplayArea.locate(CGRect(x: 1000, y: 100, width: 600, height: 200), inDisplays: [builtIn, external])
        #expect(result?.displayIndex == 0)
        #expect(result?.sourceRect == CGRect(x: 1000, y: 100, width: 512, height: 200))
    }

    @Test func rejectsAreasOffEveryDisplay() {
        #expect(DisplayArea.locate(CGRect(x: -900, y: 5000, width: 50, height: 50), inDisplays: [builtIn, external]) == nil)
    }
}
