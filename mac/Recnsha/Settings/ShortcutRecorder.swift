import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A button that records the next key combination typed. Esc cancels.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    var onRecordingChange: (Bool) -> Void = { _ in }

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Button(buttonTitle) {
                    isRecording ? stopRecording() : startRecording()
                }
                .accessibilityHint("Activate, then type the new key combination. Escape cancels.")

                if shortcut != nil, !isRecording {
                    Button("Clear") { shortcut = nil }
                }
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var buttonTitle: String {
        if isRecording { return "Type shortcut…" }
        return shortcut?.displayString ?? "Record Shortcut"
    }

    private func startRecording() {
        message = nil
        isRecording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            let candidate = Shortcut(keyCode: UInt32(event.keyCode), modifiers: event.modifierFlags)
            if candidate.isValid {
                shortcut = candidate
                stopRecording()
            } else {
                message = "Include ⌘ or ⌃ in the shortcut."
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording {
            isRecording = false
            onRecordingChange(false)
        }
    }
}
