import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import Recnsha

@MainActor
struct ServerAddressTests {
    @Test(arguments: [
        ("https://share.example.com", "https://share.example.com"),
        ("  https://share.example.com/  ", "https://share.example.com"),
        ("http://localhost:8787", "http://localhost:8787"),
        ("http://127.0.0.1:8787/", "http://127.0.0.1:8787"),
    ])
    func acceptsValidAddresses(input: String, expected: String) {
        #expect(ServerAddress.validate(input)?.absoluteString == expected)
    }

    @Test(arguments: [
        "",
        "share.example.com",
        "http://share.example.com",
        "ftp://share.example.com",
        "https://share.example.com/path",
        "https://share.example.com/?debug=1",
        "https://user:secret@share.example.com",
    ])
    func rejectsInvalidAddresses(input: String) {
        #expect(ServerAddress.validate(input) == nil)
    }
}

@MainActor
struct SettingsStoreTests {
    let store = SettingsStore(defaults: UserDefaults(suiteName: "RecnshaTests-\(UUID().uuidString)")!)

    @Test func usesTheDefaultShortcutUntilChanged() {
        #expect(store.shortcut(for: .screenshot) == HotKeyAction.screenshot.defaultShortcut)
    }

    @Test func storesAndClearsShortcuts() {
        let shortcut = Shortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: [.command, .control])
        store.setShortcut(shortcut, for: .screenshot)
        #expect(store.shortcut(for: .screenshot) == shortcut)

        store.setShortcut(nil, for: .screenshot)
        #expect(store.shortcut(for: .screenshot) == nil)
    }

    @Test func storesServerAddressAndDelay() {
        #expect(store.serverURL == nil)
        store.serverAddress = "https://share.example.com/"
        store.delaySeconds = 5
        #expect(store.serverURL == URL(string: "https://share.example.com"))
        #expect(store.delaySeconds == 5)
    }

    @Test func storesTheCopyFormat() {
        #expect(store.copyFormat == .pageLink)
        store.copyFormat = .markdown
        #expect(store.copyFormat == .markdown)
    }
}
