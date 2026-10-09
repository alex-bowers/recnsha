import AppKit
import SwiftUI

/// Settings lives in an AppKit window so the model can open it at any time, including at launch.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(model: AppModel) {
        let window = Self.window ?? makeWindow(model: model)
        Self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private static func makeWindow(model: AppModel) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
        window.title = "Recnsha Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
