import SwiftUI

struct MenuContent: View {
    @Bindable var model: AppModel

    var body: some View {
        Button(title("Capture Screenshot", for: .screenshot)) {
            Task { await model.captureScreenshot() }
        }

        Button(title(model.isRecording ? "Stop Recording" : "Record Screen", for: .record)) {
            Task { await model.toggleRecording() }
        }

        Picker("Delay", selection: $model.delaySeconds) {
            ForEach(AppModel.delayOptions, id: \.self) { seconds in
                Text(AppModel.delayLabel(seconds)).tag(seconds)
            }
        }

        Divider()

        Button(title("Library…", for: .library)) { model.openLibrary() }
            .keyboardShortcut("l")

        if model.recent.isEmpty {
            Text("No recent uploads")
        } else {
            Section("Recent Uploads") {
                ForEach(model.recent) { file in
                    Menu(file.menuTitle(relativeTo: .now)) {
                        Button("Copy Link") { model.copy(file, as: .pageLink) }
                        Button("Copy Markdown") { model.copy(file, as: .markdown) }
                        Button("Copy Image Link") { model.copy(file, as: .imageLink) }
                        Button("Open in Browser") { model.open(file) }
                        if file.kind == .video {
                            Button("Make GIF…") { GIFMakerWindow.show(file: file, model: model) }
                        }
                        Divider()
                        Button("Delete…") { Task { await model.delete([file]) } }
                    }
                }
            }
        }

        if model.failedCount > 0 {
            Button("Retry Failed Uploads (\(model.failedCount))") {
                Task { await model.retryFailedUploads() }
            }
        }

        Divider()

        Button("Settings…") { SettingsWindow.show(model: model) }
            .keyboardShortcut(",")
        Button("Quit Recnsha") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Adds the action's global shortcut to a menu title, for example "Library… (⌃⇧L)".
    private func title(_ text: String, for action: HotKeyAction) -> String {
        guard let shortcut = model.shortcuts[action] else { return text }
        return "\(text) (\(shortcut.displayString))"
    }
}
