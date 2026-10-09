import CoreGraphics

/// Works out which display an area is on and where it sits on that display.
enum DisplayArea {
    /// `rect` and `frames` are in display space. Returns the display holding the area's centre
    /// (or, failing that, the first it overlaps) and the area clipped to it, relative to its top-left corner.
    static func locate(_ rect: CGRect, inDisplays frames: [CGRect]) -> (displayIndex: Int, sourceRect: CGRect)? {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        guard let index = frames.firstIndex(where: { $0.contains(centre) }) ?? frames.firstIndex(where: { $0.intersects(rect) }) else {
            return nil
        }
        let frame = frames[index]
        return (index, rect.intersection(frame).offsetBy(dx: -frame.minX, dy: -frame.minY))
    }

    /// Pixels per point for a display: 2 on Retina displays, 1 on standard ones.
    static func pixelScale(of displayID: CGDirectDisplayID) -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(displayID), mode.width > 0 else { return 1 }
        return CGFloat(mode.pixelWidth) / CGFloat(mode.width)
    }
}
