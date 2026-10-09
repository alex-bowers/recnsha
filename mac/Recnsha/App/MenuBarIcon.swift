import AppKit

/// The menu-bar icon. SF Symbols are drawn between pixels on standard (1×) displays and look soft,
/// so the camera carries a hand-placed 1× version alongside the symbol for Retina displays.
/// macOS picks the version that suits each display.
enum MenuBarIcon {
    /// The camera on a 19 × 15 pixel grid: "#" is solid, "." is clear.
    static let cameraPixels = [
        ".......#####.......",
        "......#######......",
        ".#################.",
        "###################",
        "###############.###",
        "########...########",
        "#######.###.#######",
        "######.#####.######",
        "######.#####.######",
        "######.#####.######",
        "#######.###.#######",
        "########...########",
        "###################",
        "###################",
        ".#################.",
    ]

    static func camera() -> NSImage {
        let size = NSSize(width: cameraPixels[0].count, height: cameraPixels.count)
        let image = NSImage(size: size)
        image.addRepresentation(oneTimesCamera(size: size))
        if let retina = retinaSymbol("camera.fill", size: size) {
            image.addRepresentation(retina)
        }
        image.isTemplate = true
        image.accessibilityDescription = "Recnsha"
        return image
    }

    /// A plain symbol, for the short-lived recording and uploading states.
    static func symbol(_ name: String) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Recnsha")?
            .withSymbolConfiguration(configuration) ?? NSImage()
        image.isTemplate = true
        return image
    }

    private static func oneTimesCamera(size: NSSize) -> NSBitmapImageRep {
        let rep = bitmap(pixelsWide: Int(size.width), pixelsHigh: Int(size.height), size: size)
        // The colour must match the bitmap's RGB colour space; a grey colour such as .black is silently ignored.
        let solid = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1)
        for (y, row) in cameraPixels.enumerated() {
            for (x, pixel) in row.enumerated() where pixel == "#" {
                rep.setColor(solid, atX: x, y: y)
            }
        }
        return rep
    }

    private static func retinaSymbol(_ name: String, size: NSSize) -> NSBitmapImageRep? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else {
            return nil
        }
        let rep = bitmap(pixelsWide: Int(size.width) * 2, pixelsHigh: Int(size.height) * 2, size: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // Fit the symbol inside the icon's size, keeping its shape.
        let scale = min(size.width / symbol.size.width, size.height / symbol.size.height)
        let drawn = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        let origin = NSPoint(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2)
        symbol.draw(in: NSRect(origin: origin, size: drawn))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func bitmap(pixelsWide: Int, pixelsHigh: Int, size: NSSize) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = size
        return rep
    }
}
