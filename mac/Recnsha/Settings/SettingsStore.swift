import Foundation

/// Preferences stored in UserDefaults. The upload token is stored in the Keychain instead.
struct SettingsStore {
    private enum Key {
        static let serverAddress = "serverAddress"
        static let delaySeconds = "delaySeconds"
        static let requestedScreenAccess = "requestedScreenAccess"
        static let copyFormat = "copyFormat"

        static func shortcut(_ action: HotKeyAction) -> String { "shortcut.\(action.rawValue)" }
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var serverAddress: String {
        get { defaults.string(forKey: Key.serverAddress) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: Key.serverAddress) }
    }

    var serverURL: URL? {
        ServerAddress.validate(serverAddress)
    }

    var delaySeconds: Int {
        get { defaults.integer(forKey: Key.delaySeconds) }
        nonmutating set { defaults.set(newValue, forKey: Key.delaySeconds) }
    }

    var copyFormat: CopyFormat {
        get { defaults.string(forKey: Key.copyFormat).flatMap(CopyFormat.init(rawValue:)) ?? .pageLink }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.copyFormat) }
    }

    var hasRequestedScreenAccess: Bool {
        get { defaults.bool(forKey: Key.requestedScreenAccess) }
        nonmutating set { defaults.set(newValue, forKey: Key.requestedScreenAccess) }
    }

    /// The default shortcut until the user changes it; nil once they clear it.
    func shortcut(for action: HotKeyAction) -> Shortcut? {
        guard let data = defaults.data(forKey: Key.shortcut(action)) else { return action.defaultShortcut }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }

    /// Stores empty data for a cleared shortcut, so it is not replaced by the default.
    func setShortcut(_ shortcut: Shortcut?, for action: HotKeyAction) {
        let data = shortcut.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        defaults.set(data, forKey: Key.shortcut(action))
    }
}
