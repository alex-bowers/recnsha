import Carbon.HIToolbox

/// Registers system-wide shortcuts with Carbon, the only public API for global hot keys.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    /// "RNSH": tags hot key events as Recnsha's.
    private static let signature: OSType = 0x524E_5348

    private var references: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?

    private init() {}

    /// Returns false when another app already owns the shortcut exclusively.
    func register(_ shortcut: Shortcut, id: UInt32, handler: @escaping () -> Void) -> Bool {
        installEventHandlerIfNeeded()
        unregister(id: id)

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.carbonModifiers, hotKeyID,
            GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference
        )
        guard status == noErr, let reference else { return false }

        references[id] = reference
        handlers[id] = handler
        return true
    }

    func unregister(id: UInt32) {
        if let reference = references.removeValue(forKey: id) {
            UnregisterEventHotKey(reference)
        }
        handlers[id] = nil
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr else { return status }
            // Carbon delivers hot key events on the main thread.
            MainActor.assumeIsolated {
                HotKeyCenter.shared.handlers[hotKeyID.id]?()
            }
            return noErr
        }, 1, &eventType, nil, &eventHandler)
    }
}
