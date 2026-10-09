import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import Recnsha

@MainActor
struct ShortcutTests {
    @Test func displaysModifiersInAppleOrder() {
        let shortcut = Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: [.command, .option])
        #expect(shortcut.displayString == "⌥⌘A")
        #expect(HotKeyAction.screenshot.defaultShortcut.displayString == "⌃⇧1")
    }

    @Test func givesEveryActionADistinctValidDefault() {
        let defaults = HotKeyAction.allCases.map(\.defaultShortcut)
        #expect(defaults.allSatisfy { $0.isValid })
        #expect(Set(defaults.map(\.displayString)).count == defaults.count)
        #expect(HotKeyAction.library.defaultShortcut.displayString == "⌃⇧L")
        #expect(HotKeyAction.record.defaultShortcut.displayString == "⌃⇧2")
    }

    @Test func requiresCommandOrControl() {
        #expect(Shortcut(keyCode: UInt32(kVK_ANSI_1), modifiers: [.control]).isValid)
        #expect(Shortcut(keyCode: UInt32(kVK_ANSI_1), modifiers: [.command, .shift]).isValid)
        #expect(!Shortcut(keyCode: UInt32(kVK_ANSI_1), modifiers: [.option, .shift]).isValid)
        #expect(!Shortcut(keyCode: UInt32(kVK_ANSI_1), modifiers: []).isValid)
    }

    @Test func ignoresUnsupportedModifierFlags() {
        let shortcut = Shortcut(keyCode: UInt32(kVK_ANSI_1), modifiers: [.command, .capsLock, .function])
        #expect(shortcut.modifiers == [.command])
    }

    @Test func convertsModifiersForCarbon() {
        let shortcut = Shortcut(keyCode: UInt32(kVK_ANSI_1), modifiers: [.control, .shift])
        #expect(shortcut.carbonModifiers == UInt32(controlKey | shiftKey))
    }

    @Test func survivesEncoding() throws {
        let shortcut = Shortcut(keyCode: UInt32(kVK_F5), modifiers: [.command, .control])
        let decoded = try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(shortcut))
        #expect(decoded == shortcut)
        #expect(decoded.displayString == "⌃⌘F5")
    }
}
