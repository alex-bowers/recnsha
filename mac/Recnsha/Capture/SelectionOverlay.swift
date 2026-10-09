import AppKit
import Carbon.HIToolbox

enum Selection: Equatable {
    /// An area in display space, in points.
    case area(CGRect)
    case window(WindowInfo)

    var displayRect: CGRect {
        switch self {
        case .area(let rect): rect
        case .window(let window): window.frame
        }
    }
}

/// Covers every screen. Drag to select an area, click to select the window under the pointer,
/// press Esc or right-click to cancel.
@MainActor
final class SelectionOverlay {
    private static let minimumAreaSize: CGFloat = 4

    private let windows: [WindowInfo]
    private var panels: [OverlayPanel] = []
    private var continuation: CheckedContinuation<Selection?, Never>?
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private(set) var hoveredWindow: WindowInfo?

    /// Returns nil if the user cancels.
    static func select() async -> Selection? {
        let overlay = SelectionOverlay(windows: WindowList.current())
        let selection = await withCheckedContinuation { continuation in
            overlay.show(continuation: continuation)
        }
        // Give the window server time to remove the overlay before anything is captured.
        try? await Task.sleep(for: .milliseconds(150))
        return selection
    }

    private init(windows: [WindowInfo]) {
        self.windows = windows
    }

    /// The dragged rectangle in AppKit coordinates.
    var dragRect: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        return Geometry.rect(from: dragStart, to: dragCurrent)
    }

    var hoveredRect: CGRect? {
        hoveredWindow.map { Geometry.flip($0.frame, primaryHeight: Geometry.primaryHeight) }
    }

    private func show(continuation: CheckedContinuation<Selection?, Never>) {
        self.continuation = continuation
        // Do not activate the app: macOS would switch to the desktop (Space) holding one of
        // Recnsha's windows, such as the Library. Non-activating panels can take key input regardless.
        for screen in NSScreen.screens {
            let panel = OverlayPanel(screen: screen, overlay: self)
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        let mouse = NSEvent.mouseLocation
        (panels.first { $0.frame.contains(mouse) } ?? panels.first)?.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.push()
        mouseMoved(to: mouse)
    }

    func mouseDown(at point: CGPoint) {
        dragStart = point
        dragCurrent = point
        redraw()
    }

    func mouseDragged(to point: CGPoint) {
        dragCurrent = point
        redraw()
    }

    func mouseUp(at point: CGPoint) {
        dragCurrent = point
        if let rect = dragRect, rect.width >= Self.minimumAreaSize, rect.height >= Self.minimumAreaSize {
            finish(.area(Geometry.flip(rect, primaryHeight: Geometry.primaryHeight).integral))
        } else if let hoveredWindow {
            finish(.window(hoveredWindow))
        } else {
            dragStart = nil
            dragCurrent = nil
            redraw()
        }
    }

    func mouseMoved(to point: CGPoint) {
        let displayPoint = Geometry.flip(point, primaryHeight: Geometry.primaryHeight)
        let window = WindowList.topmost(at: displayPoint, in: windows)
        if window != hoveredWindow {
            hoveredWindow = window
            redraw()
        }
    }

    func cancel() {
        finish(nil)
    }

    private func redraw() {
        for panel in panels { panel.contentView?.needsDisplay = true }
    }

    private func finish(_ selection: Selection?) {
        guard let continuation else { return }
        self.continuation = nil
        NSCursor.pop()
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
        continuation.resume(returning: selection)
    }
}

private final class OverlayPanel: NSPanel {
    init(screen: NSScreen, overlay: SelectionOverlay) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        setFrame(screen.frame, display: false)
        let view = OverlayView(overlay: overlay, screenOrigin: screen.frame.origin)
        contentView = view
        initialFirstResponder = view
    }

    override var canBecomeKey: Bool { true }
}

private final class OverlayView: NSView {
    private weak var overlay: SelectionOverlay?
    private let screenOrigin: CGPoint

    init(overlay: SelectionOverlay, screenOrigin: CGPoint) {
        self.overlay = overlay
        self.screenOrigin = screenOrigin
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseDown(with event: NSEvent) { overlay?.mouseDown(at: screenPoint(event)) }
    override func mouseDragged(with event: NSEvent) { overlay?.mouseDragged(to: screenPoint(event)) }
    override func mouseUp(with event: NSEvent) { overlay?.mouseUp(at: screenPoint(event)) }
    override func mouseMoved(with event: NSEvent) { overlay?.mouseMoved(to: screenPoint(event)) }
    override func rightMouseDown(with event: NSEvent) { overlay?.cancel() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            overlay?.cancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()
        guard let overlay else { return }

        if let rect = overlay.dragRect {
            let local = rect.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
            NSColor.clear.setFill()
            local.fill(using: .copy)
            NSColor.white.setStroke()
            NSBezierPath(rect: local.insetBy(dx: 0.5, dy: 0.5)).stroke()
            drawSizeLabel("\(Int(rect.width)) × \(Int(rect.height))", below: local)
        } else if let rect = overlay.hoveredRect {
            let local = rect.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
            NSColor.clear.setFill()
            local.fill(using: .copy)
            NSColor.systemBlue.withAlphaComponent(0.2).setFill()
            local.fill()
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(rect: local.insetBy(dx: 1, dy: 1))
            path.lineWidth = 2
            path.stroke()
        }
    }

    private func drawSizeLabel(_ text: String, below rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.75),
        ]
        (text as NSString).draw(at: CGPoint(x: rect.minX, y: max(rect.minY - 18, 2)), withAttributes: attributes)
    }

    private func screenPoint(_ event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
    }
}
