@preconcurrency import AVFoundation
import AppKit
import Observation

@MainActor
@Observable
final class AppModel {
    static let delayOptions = [0, 3, 5, 10]
    private static let recentLimit = 10
    private static let pageSize = 40

    static func delayLabel(_ seconds: Int) -> String {
        seconds == 0 ? "No delay" : "\(seconds) seconds"
    }

    /// Uploads newest first, shared by the menu and the Library. More pages load on demand.
    private(set) var uploads: [UploadedFile] = []
    private(set) var nextCursor: Int?
    private(set) var isLoadingUploads = false
    private(set) var uploadsError: String?
    private(set) var isUploading = false
    private(set) var isRecording = false
    /// Set while uploads are being deleted.
    private(set) var deletionProgress: DeletionProgress?

    struct DeletionProgress: Equatable {
        var done: Int
        let total: Int
    }
    private(set) var failedCount = 0
    private(set) var shortcuts: [HotKeyAction: Shortcut] = [:]
    private(set) var shortcutErrors: [HotKeyAction: String] = [:]
    var delaySeconds: Int {
        didSet { settings.delaySeconds = delaySeconds }
    }
    var copyFormat: CopyFormat {
        didSet { settings.copyFormat = copyFormat }
    }

    var recent: [UploadedFile] {
        Array(uploads.prefix(Self.recentLimit))
    }

    let settings: SettingsStore
    @ObservationIgnored private let failedUploads: FailedUploads
    @ObservationIgnored private let notifier = Notifier()
    @ObservationIgnored private var isCapturing = false
    @ObservationIgnored private var recorder: ScreenRecorder?
    @ObservationIgnored private let recordingIndicator = RecordingIndicator()

    init(settings: SettingsStore = SettingsStore(), failedUploads: FailedUploads = .standard) {
        self.settings = settings
        self.failedUploads = failedUploads
        delaySeconds = settings.delaySeconds
        copyFormat = settings.copyFormat
        failedCount = failedUploads.files().count
        for action in HotKeyAction.allCases {
            shortcuts[action] = settings.shortcut(for: action)
        }

        // Unit tests run inside the app; keep them free of hot keys, windows and network calls.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.start() }
        }
        NotificationCenter.default.addObserver(forName: .recnshaReopened, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.openLibrary() }
        }
    }

    private func start() {
        // Library thumbnails are full-size images; files never change, so cache generously.
        URLCache.shared = URLCache(memoryCapacity: 50_000_000, diskCapacity: 200_000_000)
        notifier.configure()
        registerShortcuts()
        if makeClient() == nil {
            SettingsWindow.show(model: self)
        } else {
            Task { await reloadUploads() }
        }
    }

    /// Opens the Library, or Settings when Recnsha is not set up yet.
    func openLibrary() {
        if makeClient() == nil {
            SettingsWindow.show(model: self)
        } else {
            LibraryWindow.show(model: self)
        }
    }

    // MARK: Shortcuts

    func registerShortcuts() {
        HotKeyAction.allCases.forEach(register)
    }

    /// Stops global shortcuts while the user records a new one, so the old one does not fire.
    func suspendShortcuts() {
        for action in HotKeyAction.allCases {
            HotKeyCenter.shared.unregister(id: action.hotKeyID)
        }
    }

    func setShortcut(_ shortcut: Shortcut?, for action: HotKeyAction) {
        if let shortcut, let other = HotKeyAction.allCases.first(where: { $0 != action && shortcuts[$0] == shortcut }) {
            shortcutErrors[action] = "\(shortcut.displayString) is already used for \(other.title.lowercased())."
            return
        }
        settings.setShortcut(shortcut, for: action)
        shortcuts[action] = shortcut
        register(action)
    }

    private func register(_ action: HotKeyAction) {
        guard let shortcut = shortcuts[action] else {
            HotKeyCenter.shared.unregister(id: action.hotKeyID)
            shortcutErrors[action] = nil
            return
        }
        let registered = HotKeyCenter.shared.register(shortcut, id: action.hotKeyID) { [weak self] in
            self?.perform(action)
        }
        shortcutErrors[action] = registered ? nil : "Another app is already using \(shortcut.displayString)."
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .screenshot:
            Task { await captureScreenshot() }
        case .record:
            Task { await toggleRecording() }
        case .library:
            openLibrary()
        }
    }

    // MARK: Capture and upload

    func captureScreenshot() async {
        guard !isCapturing else { return }
        guard let client = makeClient() else {
            SettingsWindow.show(model: self)
            return
        }
        guard ScreenPermission.ensure(settings: settings) else { return }

        isCapturing = true
        defer { isCapturing = false }

        guard let selection = await SelectionOverlay.select() else { return }
        await Countdown.run(seconds: delaySeconds, near: selection.displayRect)

        do {
            let image = try await Capturer.capture(selection)
            let png = try ImageEncoder.png(image)
            await upload(png, fileExtension: "png", using: client)
        } catch {
            Toast.show("Capture failed", systemImage: "exclamationmark.triangle.fill", hideAfter: .seconds(4))
            notifier.post(title: "Capture failed", body: error.localizedDescription)
        }
    }

    private func upload(_ data: Data, fileExtension: String, using client: APIClient) async {
        guard let contentType = FailedUploads.contentType(forExtension: fileExtension) else { return }
        isUploading = true
        defer { isUploading = false }
        Toast.show("Uploading…", systemImage: "icloud.and.arrow.up", hideAfter: nil)

        do {
            let file = try await client.upload(data, contentType: contentType)
            didUpload(file)
        } catch {
            uploadFailed(error) { _ = try failedUploads.save(data, fileExtension: fileExtension) }
        }
    }

    /// Keeps the capture for Retry Failed Uploads and tells the user.
    private func uploadFailed(_ error: Error, keep: () throws -> Void) {
        Toast.show("Upload failed", systemImage: "exclamationmark.triangle.fill", hideAfter: .seconds(4))
        do {
            try keep()
            failedCount = failedUploads.files().count
            notifier.post(title: "Upload failed", body: "\(error.localizedDescription) The capture was kept. Choose Retry Failed Uploads from the menu.")
        } catch {
            notifier.post(title: "Upload failed", body: "\(error.localizedDescription) The capture could not be kept.")
        }
    }

    // MARK: Recording

    func toggleRecording() async {
        if isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    private func startRecording() async {
        guard !isCapturing else { return }
        guard makeClient() != nil else {
            SettingsWindow.show(model: self)
            return
        }
        guard ScreenPermission.ensure(settings: settings) else { return }

        isCapturing = true
        defer { isCapturing = false }

        guard let selection = await SelectionOverlay.select() else { return }
        await Countdown.run(seconds: delaySeconds, near: selection.displayRect)

        let recorder = ScreenRecorder()
        recorder.onUnexpectedStop = { [weak self] in
            Task { await self?.stopRecording() }
        }
        do {
            try await recorder.start(area: selection.displayRect)
            self.recorder = recorder
            isRecording = true
            recordingIndicator.show(around: selection.displayRect, startedAt: .now) { [weak self] in
                Task { await self?.stopRecording() }
            }
        } catch {
            recordingFailed(error)
        }
    }

    func stopRecording() async {
        guard let recorder else { return }
        self.recorder = nil
        isRecording = false
        recordingIndicator.hide()
        do {
            let fileURL = try await recorder.stop()
            await uploadRecording(at: fileURL)
        } catch {
            await keepPartialRecording(from: recorder, after: error)
        }
    }

    /// Keeps whatever was recorded for Retry Failed Uploads, if it plays; otherwise reports the failure.
    private func keepPartialRecording(from recorder: ScreenRecorder, after error: Error) async {
        guard let fileURL = recorder.outputURL else {
            recordingFailed(error)
            return
        }
        let duration = try? await AVURLAsset(url: fileURL).load(.duration)
        guard let duration, duration.seconds > 0, (try? failedUploads.keep(fileAt: fileURL)) != nil else {
            try? FileManager.default.removeItem(at: fileURL)
            recordingFailed(error)
            return
        }
        failedCount = failedUploads.files().count
        Toast.show("Recording stopped early", systemImage: "exclamationmark.triangle.fill", hideAfter: .seconds(4))
        notifier.post(
            title: "Recording stopped early",
            body: "\(error.localizedDescription) What was recorded was kept. Choose Retry Failed Uploads from the menu."
        )
    }

    private func recordingFailed(_ error: Error) {
        Toast.show("Recording failed", systemImage: "exclamationmark.triangle.fill", hideAfter: .seconds(4))
        notifier.post(title: "Recording failed", body: error.localizedDescription)
    }

    private func uploadRecording(at fileURL: URL) async {
        guard let client = makeClient() else {
            uploadFailed(APIError.notConfigured) { _ = try failedUploads.keep(fileAt: fileURL) }
            return
        }
        isUploading = true
        defer { isUploading = false }
        Toast.show("Uploading…", systemImage: "icloud.and.arrow.up", hideAfter: nil)

        do {
            let file = try await client.uploadInParts(fileAt: fileURL, contentType: "video/mp4")
            try? FileManager.default.removeItem(at: fileURL)
            didUpload(file)
        } catch {
            uploadFailed(error) { _ = try failedUploads.keep(fileAt: fileURL) }
        }
    }

    func retryFailedUploads() async {
        guard let client = makeClient() else {
            SettingsWindow.show(model: self)
            return
        }
        isUploading = true
        defer {
            isUploading = false
            failedCount = failedUploads.files().count
        }

        for url in failedUploads.files() {
            guard let contentType = FailedUploads.contentType(forExtension: url.pathExtension) else { continue }
            do {
                let file = contentType == "video/mp4"
                    ? try await client.uploadInParts(fileAt: url, contentType: contentType)
                    : try await client.upload(Data(contentsOf: url), contentType: contentType)
                try? failedUploads.remove(url)
                didUpload(file)
            } catch {
                notifier.post(title: "Retry failed", body: error.localizedDescription)
                return
            }
        }
    }

    private func didUpload(_ file: UploadedFile) {
        copy(file, as: copyFormat)
        notifier.post(title: copyFormat.confirmation, body: file.text(for: copyFormat), url: file.page)
        uploads.removeAll { $0.id == file.id }
        uploads.insert(file, at: 0)
    }

    // MARK: Uploads list

    /// Loads the newest page, replacing the list.
    func reloadUploads() async {
        guard let client = makeClient(), !isLoadingUploads else { return }
        isLoadingUploads = true
        defer { isLoadingUploads = false }
        do {
            let page = try await client.listUploads(limit: Self.pageSize)
            uploads = page.uploads
            nextCursor = page.nextCursor
            uploadsError = nil
        } catch {
            uploadsError = error.localizedDescription
        }
    }

    /// Appends the next page of older uploads, if there is one.
    func loadMoreUploads() async {
        guard let client = makeClient(), let cursor = nextCursor, !isLoadingUploads else { return }
        isLoadingUploads = true
        defer { isLoadingUploads = false }
        do {
            let page = try await client.listUploads(limit: Self.pageSize, before: cursor)
            let known = Set(uploads.map(\.id))
            uploads.append(contentsOf: page.uploads.filter { !known.contains($0.id) })
            nextCursor = page.nextCursor
            uploadsError = nil
        } catch {
            uploadsError = error.localizedDescription
        }
    }

    /// Uploads a GIF for a recording, updates the lists and copies the recording again.
    func attachGIF(_ data: Data, to file: UploadedFile) async throws {
        guard let client = makeClient() else { throw APIError.notConfigured }
        let updated = try await client.uploadGIF(data, forUpload: file.id)
        if let index = uploads.firstIndex(where: { $0.id == updated.id }) {
            uploads[index] = updated
        }
        copy(updated, as: copyFormat)
    }

    func copy(_ file: UploadedFile, as format: CopyFormat) {
        Clipboard.copy(file.text(for: format))
        Toast.show(format.confirmation, systemImage: "checkmark.circle.fill")
    }

    func open(_ file: UploadedFile) {
        NSWorkspace.shared.open(file.page)
    }

    /// Asks once, then deletes the uploads. Returns the IDs that still exist: all of them if cancelled,
    /// otherwise those that failed.
    @discardableResult
    func delete(_ files: [UploadedFile]) async -> Set<String> {
        let ids = files.map(\.id)
        guard !ids.isEmpty, deletionProgress == nil else { return Set(ids) }

        let single = ids.count == 1
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = single ? "Delete this upload?" : "Delete \(ids.count) uploads?"
        alert.informativeText = (single ? "The link" : "Their links") + " will stop working for everyone. This cannot be undone."
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return Set(ids) }
        guard let client = makeClient() else {
            SettingsWindow.show(model: self)
            return Set(ids)
        }

        deletionProgress = DeletionProgress(done: 0, total: ids.count)
        defer { deletionProgress = nil }
        let result = await BulkDelete.run(ids: ids, using: client) { done in
            deletionProgress?.done = done
        }

        let deleted = Set(result.deleted)
        uploads.removeAll { deleted.contains($0.id) }

        if result.failed.isEmpty {
            Toast.show(single ? "Deleted" : "Deleted \(deleted.count) uploads", systemImage: "trash")
        } else {
            let failure = NSAlert()
            failure.messageText = single
                ? "The upload couldn't be deleted"
                : "\(result.failed.count) of \(ids.count) uploads couldn't be deleted"
            failure.informativeText = (result.failed.values.first ?? "") + (single ? "" : " They are still selected, so you can try again.")
            NSApp.activate()
            failure.runModal()
        }
        return Set(result.failed.keys)
    }

    // MARK: Settings

    func testConnection() async -> String {
        guard let client = makeClient() else {
            return "Enter a valid server address and save a token first."
        }
        do {
            _ = try await client.recentUploads(limit: 1)
            await reloadUploads()
            return "Connected."
        } catch {
            return error.localizedDescription
        }
    }

    func makeClient() -> APIClient? {
        guard let url = settings.serverURL, let token = Keychain.readToken(), !token.isEmpty else { return nil }
        return APIClient(baseURL: url, token: token)
    }
}
