import AppKit
import SwiftUI

/// One Make GIF window per recording. A window is forgotten when it closes, so opening it again
/// starts fresh with the current upload rather than reusing a view that has already cleaned up.
@MainActor
enum GIFMakerWindow {
    private static var windows: [String: NSWindow] = [:]
    private static var closeObservers: [String: NSObjectProtocol] = [:]

    static func show(file: UploadedFile, model: AppModel) {
        let window = windows[file.id] ?? makeWindow(file: file, model: model)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    static func close(_ file: UploadedFile) {
        windows[file.id]?.close()
    }

    private static func makeWindow(file: UploadedFile, model: AppModel) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Make GIF"
        window.contentView = NSHostingView(rootView: GIFMakerView(file: file, model: model))
        window.contentMinSize = NSSize(width: 520, height: 460)
        window.isReleasedWhenClosed = false
        window.center()

        let id = file.id
        windows[id] = window
        closeObservers[id] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated { forget(id) }
        }
        return window
    }

    private static func forget(_ id: String) {
        windows.removeValue(forKey: id)
        if let observer = closeObservers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
