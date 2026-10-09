import AppKit
import Carbon.HIToolbox

/// Actions that can be triggered by a global shortcut.
enum HotKeyAction: String, CaseIterable, Identifiable {
    case screenshot
    case record
    case library

    var id: String { rawValue }

    /// Identifies the action in Carbon hot key events. Never reuse a number.
    var hotKeyID: UInt32 {
        switch self {
        case .screenshot: 1
        case .library: 2
        case .record: 3
        }
    }

    var title: String {
        switch self {
        case .screenshot: "Capture screenshot"
        case .library: "Open library"
        case .record: "Start or stop recording"
        }
    }

    var defaultShortcut: Shortcut {
        switch self {
        case .screenshot: Shortcut(keyCode: UInt32(kVK_ANSI_1), modifiers: [.control, .shift])
        case .library: Shortcut(keyCode: UInt32(kVK_ANSI_L), modifiers: [.control, .shift])
        case .record: Shortcut(keyCode: UInt32(kVK_ANSI_2), modifiers: [.control, .shift])
        }
    }
}
