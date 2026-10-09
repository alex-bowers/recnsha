import AppKit
import SwiftUI

@main
struct RecnshaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(nsImage: menuBarIcon)
        }
    }

    /// Built once: the camera is drawn from fixed pixels and does not change.
    private static let cameraIcon = MenuBarIcon.camera()

    private var menuBarIcon: NSImage {
        if model.isRecording { return MenuBarIcon.symbol("record.circle") }
        if model.isUploading { return MenuBarIcon.symbol("icloud.and.arrow.up") }
        return Self.cameraIcon
    }
}
