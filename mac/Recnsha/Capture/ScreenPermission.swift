import AppKit
import CoreGraphics

enum ScreenPermission {
    /// True when Recnsha may capture the screen. Otherwise asks macOS once, then explains how to grant access.
    @MainActor
    static func ensure(settings: SettingsStore) -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }

        if !settings.hasRequestedScreenAccess {
            settings.hasRequestedScreenAccess = true
            return CGRequestScreenCaptureAccess()
        }

        let alert = NSAlert()
        alert.messageText = "Allow screen recording"
        alert.informativeText = "Recnsha needs permission to capture your screen. Turn on Recnsha in System Settings › Privacy & Security › Screen & System Audio Recording, then quit and reopen Recnsha."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }
}
