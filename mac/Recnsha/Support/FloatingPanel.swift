import AppKit

/// Borderless, transparent panels that float above other windows on every Space without taking focus.
/// Used for the toast, the countdown and the recording indicator.
@MainActor
enum FloatingPanel {
    /// Non-interactive panels let clicks pass through; interactive ones accept clicks and get a shadow.
    static func make(frame: CGRect, contentView: NSView, level: NSWindow.Level = .statusBar, interactive: Bool = false) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = level
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = interactive
        panel.ignoresMouseEvents = !interactive
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = contentView
        return panel
    }
}
