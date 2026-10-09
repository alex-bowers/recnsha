@preconcurrency import AVFoundation
import AVKit
import SwiftUI

/// Choose a segment of a recording, preview it, and upload it as the recording's GIF.
struct GIFMakerView: View {
    let file: UploadedFile
    let model: AppModel

    @State private var player: AVPlayer?
    @State private var videoURL: URL?
    @State private var duration: Double = 0
    @State private var start: Double = 0
    @State private var length: Double = GIFMaker.maximumDuration
    @State private var status: String?
    @State private var statusIsError = false
    @State private var isWorking = false

    private var segment: ClosedRange<Double> {
        GIFMaker.segment(start: start, length: length, videoDuration: duration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    ProgressView("Downloading recording…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: 280)
            .clipShape(.rect(cornerRadius: 8))

            if duration > 0 {
                LabeledContent("Start") {
                    HStack {
                        Slider(value: $start, in: 0...max(duration - 0.5, 0.5))
                            .accessibilityLabel("Start")
                        Text(Self.seconds(segment.lowerBound))
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                LabeledContent("Length") {
                    HStack {
                        Slider(value: $length, in: 0.5...max(min(GIFMaker.maximumDuration, duration), 0.5))
                            .accessibilityLabel("Length")
                        Text(Self.seconds(segment.upperBound - segment.lowerBound))
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                Text("GIFs are up to \(Int(GIFMaker.maximumDuration)) seconds long, \(GIFMaker.framesPerSecond) frames per second and \(Int(GIFMaker.maximumWidth)) pixels wide.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if let status {
                    Text(status).foregroundStyle(statusIsError ? .red : .secondary)
                }
                Spacer()
                Button("Preview Segment", action: preview)
                    .disabled(player == nil || isWorking)
                Button("Create GIF") { Task { await createGIF() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(videoURL == nil || isWorking)
            }
        }
        .padding(16)
        .task { await load() }
        .onChange(of: start) { seekToStart() }
        .onDisappear(perform: cleanUp)
    }

    private static func seconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " s"
    }

    private func load() async {
        guard videoURL == nil else { return }
        do {
            let (downloaded, response) = try await URLSession.shared.download(from: file.file)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.invalidResponse }
            let url = URL.temporaryDirectory.appending(path: "GIF-source-\(file.id).mp4")
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: downloaded, to: url)

            let seconds = try await AVURLAsset(url: url).load(.duration).seconds
            videoURL = url
            duration = seconds
            length = min(GIFMaker.maximumDuration, seconds)
            player = AVPlayer(url: url)
        } catch {
            show("Couldn't download the recording: \(error.localizedDescription)", isError: true)
        }
    }

    private func seekToStart() {
        guard let player else { return }
        player.pause()
        player.seek(to: CMTime(seconds: segment.lowerBound, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func preview() {
        guard let player else { return }
        player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: segment.upperBound, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: segment.lowerBound, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor in player.play() }
        }
    }

    private func createGIF() async {
        guard let videoURL else { return }
        isWorking = true
        defer { isWorking = false }
        player?.pause()
        do {
            show("Making GIF…", isError: false)
            let data = try await GIFMaker.makeGIF(from: videoURL, segment: segment)
            show("Uploading GIF…", isError: false)
            try await model.attachGIF(data, to: file)
            GIFMakerWindow.close(file)
        } catch {
            show(error.localizedDescription, isError: true)
        }
    }

    private func show(_ message: String, isError: Bool) {
        status = message
        statusIsError = isError
    }

    private func cleanUp() {
        player?.pause()
        player = nil
        if let videoURL { try? FileManager.default.removeItem(at: videoURL) }
        videoURL = nil
        duration = 0
    }
}
