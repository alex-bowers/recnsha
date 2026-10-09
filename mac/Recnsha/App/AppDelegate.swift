import AppKit

extension Notification.Name {
    /// Posted when Recnsha is opened again while already running.
    static let recnshaReopened = Notification.Name("RecnshaReopened")
}

/// Opening Recnsha again while it runs shows Settings, because the menu-bar icon can be
/// hidden by the notch or by System Settings › Menu Bar.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .recnshaReopened, object: nil)
        return false
    }
}
