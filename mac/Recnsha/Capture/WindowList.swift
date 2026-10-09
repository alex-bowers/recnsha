import AppKit

struct WindowInfo: Equatable {
    let id: CGWindowID
    /// Frame in display space.
    let frame: CGRect
}

enum WindowList {
    /// Normal on-screen windows from front to back, excluding Recnsha's own windows.
    static func current() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let entries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownProcess = ProcessInfo.processInfo.processIdentifier

        return entries.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  (entry[kCGWindowOwnerPID as String] as? pid_t) != ownProcess,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width > 1, frame.height > 1
            else { return nil }
            return WindowInfo(id: id, frame: frame)
        }
    }

    /// The frontmost window containing a display-space point. `windows` must be ordered front to back.
    static func topmost(at point: CGPoint, in windows: [WindowInfo]) -> WindowInfo? {
        windows.first { $0.frame.contains(point) }
    }
}
