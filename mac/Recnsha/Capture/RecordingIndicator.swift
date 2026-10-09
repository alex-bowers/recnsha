import AppKit
import SwiftUI

/// A red border around the recorded area and a floating control with the elapsed time and a Stop button.
/// Both are Recnsha windows, so they are not in the recording.
@MainActor
final class RecordingIndicator {
    private var panels: [NSPanel] = []

    func show(around displayRect: CGRect, startedAt: Date, onStop: @escaping () -> Void) {
        hide()
        let area = Geometry.flip(displayRect, primaryHeight: Geometry.primaryHeight)
        panels.append(FloatingPanel.make(frame: area.insetBy(dx: -3, dy: -3), contentView: NSHostingView(rootView: RecordingBorder())))

        let controls = NSHostingView(rootView: RecordingControls(startedAt: startedAt, onStop: onStop))
        let size = controls.fittingSize
        let visible = (NSScreen.screens.first { $0.frame.intersects(area) } ?? NSScreen.main)?.visibleFrame ?? .zero
        var origin = CGPoint(x: area.midX - size.width / 2, y: area.minY - size.height - 12)
        if origin.y < visible.minY { origin.y = area.maxY + 12 }
        if origin.y + size.height > visible.maxY { origin.y = area.minY + 12 }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        panels.append(FloatingPanel.make(frame: CGRect(origin: origin, size: size), contentView: controls, interactive: true))

        for panel in panels { panel.orderFrontRegardless() }
    }

    func hide() {
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
    }
}

private struct RecordingBorder: View {
    var body: some View {
        Rectangle()
            .strokeBorder(.red, lineWidth: 2)
            .accessibilityHidden(true)
    }
}

private struct RecordingControls: View {
    let startedAt: Date
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                Text(Duration.seconds(max(0, context.date.timeIntervalSince(startedAt))).formatted(.time(pattern: .minuteSecond)))
                    .monospacedDigit()
                    .accessibilityLabel("Recording time")
            }
            Button("Stop", action: onStop)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityLabel("Stop recording")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: .capsule)
        .fixedSize()
    }
}
