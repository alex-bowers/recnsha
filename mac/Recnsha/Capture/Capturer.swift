@preconcurrency import ScreenCaptureKit

enum Capturer {
    static func capture(_ selection: Selection) async throws -> CGImage {
        switch selection {
        case .area(let rect):
            // Capturing through a display filter keeps the display's native (Retina) resolution.
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let located = DisplayArea.locate(rect, inDisplays: content.displays.map(\.frame)) else {
                throw CaptureError.noDisplay
            }
            let display = content.displays[located.displayIndex]
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let scale = DisplayArea.pixelScale(of: display.displayID)
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = located.sourceRect
            configuration.width = Int((located.sourceRect.width * scale).rounded())
            configuration.height = Int((located.sourceRect.height * scale).rounded())
            configuration.showsCursor = false
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)

        case .window(let info):
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.windowID == info.id }) else {
                throw CaptureError.windowNotFound
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            configuration.width = Int(filter.contentRect.width * scale)
            configuration.height = Int(filter.contentRect.height * scale)
            configuration.showsCursor = false
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        }
    }
}
