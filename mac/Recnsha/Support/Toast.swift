import AppKit
import SwiftUI

/// A short message at the bottom of the screen. Unlike notifications, it cannot be turned off
/// by notification settings or Focus, so every capture gets visible feedback.
@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?

    /// Shows `message`, replacing any current toast. Pass `hideAfter: nil` to keep it until replaced.
    static func show(_ message: String, systemImage: String, hideAfter delay: Duration? = .seconds(2)) {
        hideTask?.cancel()
        panel?.orderOut(nil)

        let content = NSHostingView(rootView: ToastView(message: message, systemImage: systemImage))
        let size = content.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let origin = CGPoint(x: visible.midX - size.width / 2, y: visible.minY + 40)

        let panel = FloatingPanel.make(frame: CGRect(origin: origin, size: size), contentView: content)
        panel.orderFrontRegardless()
        Self.panel = panel

        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )

        guard let delay else { return }
        hideTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }
}

private struct ToastView: View {
    let message: String
    let systemImage: String

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.black.opacity(0.8), in: .capsule)
            .fixedSize()
    }
}
