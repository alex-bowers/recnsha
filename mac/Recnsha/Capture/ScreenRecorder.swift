@preconcurrency import ScreenCaptureKit

enum RecordingError: LocalizedError {
    case noDisplay
    case notRecording
    case timedOut

    var errorDescription: String? {
        switch self {
        case .noDisplay: "The selected area is not on a display."
        case .notRecording: "No recording is in progress."
        case .timedOut: "The recording did not finish saving."
        }
    }
}

/// Records an area of one display to an MP4 file. Recnsha's own windows are left out.
@MainActor
final class ScreenRecorder: NSObject {
    private static let stopTimeout: Duration = .seconds(10)

    /// Called when the system ends the recording, for example because a display was disconnected.
    var onUnexpectedStop: (() -> Void)?
    /// The MP4 being written. Still set after a failure, so whatever was recorded can be kept.
    private(set) var outputURL: URL?

    private var stream: SCStream?
    private var finish: CheckedContinuation<Void, Error>?
    /// Set when the recording output finished or failed while nobody was waiting in `stop()`.
    private var didFinish = false
    private var failure: Error?

    /// Starts recording `displayRect`, given in display space.
    func start(area displayRect: CGRect) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let located = DisplayArea.locate(displayRect, inDisplays: content.displays.map(\.frame)) else {
            throw RecordingError.noDisplay
        }
        let display = content.displays[located.displayIndex]

        let ownProcess = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownProcess }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let area = located.sourceRect
        let scale = DisplayArea.pixelScale(of: display.displayID)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = area
        configuration.width = Self.even(area.width * scale)
        configuration.height = Self.even(area.height * scale)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.showsCursor = true
        configuration.capturesAudio = false

        let url = URL.temporaryDirectory.appending(path: "Recording-\(UUID().uuidString).mp4")
        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = url
        recordingConfiguration.outputFileType = .mp4
        recordingConfiguration.videoCodecType = .h264
        let output = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addRecordingOutput(output)
        didFinish = false
        failure = nil
        try await stream.startCapture()
        self.stream = stream
        outputURL = url
    }

    /// Stops recording and returns the finished MP4. Returns at once if the recording already finished.
    func stop() async throws -> URL {
        guard let outputURL else { throw RecordingError.notRecording }
        let stream = self.stream
        self.stream = nil

        if !didFinish, failure == nil {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                finish = continuation
                // Errors are ignored: the stream may have stopped already, and the recording output reports the outcome.
                Task { try? await stream?.stopCapture() }
                Task {
                    try? await Task.sleep(for: Self.stopTimeout)
                    complete(with: RecordingError.timedOut)
                }
            }
        }
        if let failure { throw failure }
        return outputURL
    }

    fileprivate func complete(with error: Error?) {
        if let finish {
            self.finish = nil
            if let error {
                finish.resume(throwing: error)
            } else {
                finish.resume()
            }
        } else if let error {
            failure = failure ?? error
        } else {
            didFinish = true
        }
    }

    /// H.264 needs even dimensions.
    private static func even(_ value: CGFloat) -> Int {
        max(2, Int(value) / 2 * 2)
    }
}

extension ScreenRecorder: nonisolated SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in self.onUnexpectedStop?() }
    }
}

extension ScreenRecorder: nonisolated SCRecordingOutputDelegate {
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.complete(with: nil) }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        let failure = error as NSError
        Task { @MainActor in self.complete(with: failure) }
    }
}
