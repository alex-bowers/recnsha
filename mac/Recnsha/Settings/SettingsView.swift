import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    @State private var address = ""
    @State private var tokenDraft = ""
    @State private var hasToken = false
    @State private var tokenError: String?
    @State private var connectionStatus: String?
    @State private var isTesting = false
    @State private var launchAtLogin = false
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Server") {
                TextField("Server address", text: $address, prompt: Text("https://share.example.com"))
                    .onChange(of: address) { _, newValue in model.settings.serverAddress = newValue }
                if !address.isEmpty, ServerAddress.validate(address) == nil {
                    errorText("Enter an https:// address with no path, such as https://share.example.com.")
                }

                SecureField("Upload token", text: $tokenDraft, prompt: Text(hasToken ? "Saved in Keychain" : "Paste your token"))
                HStack {
                    Button("Save Token", action: saveToken)
                        .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove Token", role: .destructive) {
                        Keychain.deleteToken()
                        hasToken = false
                    }
                    .disabled(!hasToken)
                    Spacer()
                    Button("Test Connection") {
                        Task {
                            isTesting = true
                            connectionStatus = await model.testConnection()
                            isTesting = false
                        }
                    }
                    .disabled(isTesting)
                }
                if let tokenError { errorText(tokenError) }
                if let connectionStatus {
                    Text(connectionStatus).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Shortcuts") {
                ForEach(HotKeyAction.allCases) { action in
                    LabeledContent(action.title) {
                        ShortcutRecorder(shortcut: shortcutBinding(for: action)) { recording in
                            recording ? model.suspendShortcuts() : model.registerShortcuts()
                        }
                    }
                    if let error = model.shortcutErrors[action] { errorText(error) }
                }
            }

            Section("Capture") {
                Picker("Delay before capture", selection: $model.delaySeconds) {
                    ForEach(AppModel.delayOptions, id: \.self) { seconds in
                        Text(AppModel.delayLabel(seconds)).tag(seconds)
                    }
                }
                Picker("After capture, copy", selection: $model.copyFormat) {
                    ForEach(CopyFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
            }

            Section("General") {
                Toggle("Open at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if let loginError { errorText(loginError) }
            }
        }
        .formStyle(.grouped)
        // A grouped form scrolls, so it has no natural height; give the window a fixed size.
        .frame(width: 480, height: 640)
        .onAppear(perform: load)
    }

    private func shortcutBinding(for action: HotKeyAction) -> Binding<Shortcut?> {
        Binding(
            get: { model.shortcuts[action] },
            set: { model.setShortcut($0, for: action) }
        )
    }

    private func errorText(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.red)
    }

    private func load() {
        address = model.settings.serverAddress
        hasToken = Keychain.readToken() != nil
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func saveToken() {
        do {
            try Keychain.saveToken(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines))
            tokenDraft = ""
            hasToken = true
            tokenError = nil
            Task { await model.reloadUploads() }
        } catch {
            tokenError = error.localizedDescription
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
