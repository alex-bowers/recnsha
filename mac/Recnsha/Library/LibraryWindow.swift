import AppKit
import SwiftUI

/// The Library lives in an AppKit window so it can be opened from a shortcut, the menu or a reopen.
@MainActor
enum LibraryWindow {
    private static var window: NSWindow?

    static func show(model: AppModel) {
        let window = Self.window ?? makeWindow(model: model)
        Self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private static func makeWindow(model: AppModel) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Recnsha Library"
        window.contentView = NSHostingView(rootView: LibraryView(model: model))
        window.contentMinSize = NSSize(width: 480, height: 360)
        window.isReleasedWhenClosed = false
        window.center()
        // Restores the size and position the user last chose.
        window.setFrameAutosaveName("RecnshaLibrary")
        return window
    }
}
