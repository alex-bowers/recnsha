import AppKit
import SwiftUI

/// Shows a countdown at the bottom of the screen being captured, then hides it before capture.
@MainActor
enum Countdown {
    static func run(seconds: Int, near displayRect: CGRect) async {
        guard seconds > 0 else { return }

        let appKitRect = Geometry.flip(displayRect, primaryHeight: Geometry.primaryHeight)
        let screen = NSScreen.screens.first { $0.frame.intersects(appKitRect) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let size = CGSize(width: 96, height: 96)
        let origin = CGPoint(x: visible.midX - size.width / 2, y: visible.minY + 40)

        let state = CountdownState(remaining: seconds)
        let panel = FloatingPanel.make(
            frame: CGRect(origin: origin, size: size),
            contentView: NSHostingView(rootView: CountdownView(state: state)),
            level: .screenSaver
        )
        panel.orderFrontRegardless()

        for remaining in stride(from: seconds, through: 1, by: -1) {
            state.remaining = remaining
            try? await Task.sleep(for: .seconds(1))
        }

        panel.orderOut(nil)
        try? await Task.sleep(for: .milliseconds(150))
    }
}

@MainActor
@Observable
private final class CountdownState {
    var remaining: Int

    init(remaining: Int) {
        self.remaining = remaining
    }
}

private struct CountdownView: View {
    let state: CountdownState

    var body: some View {
        Text(state.remaining, format: .number)
            .font(.system(size: 48, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: 96, height: 96)
            .background(.black.opacity(0.75), in: .rect(cornerRadius: 20))
            .accessibilityLabel("Capturing in \(state.remaining) seconds")
    }
}
