import SwiftUI

/// A grid of every upload, newest first, with copy, open and delete actions.
struct LibraryView: View {
    @Bindable var model: AppModel

    @State private var isSelecting = false
    @State private var selection: Set<String> = []
    /// The last card clicked, where a Shift-click range starts.
    @State private var anchorID: String?

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.uploads.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.uploads) { file in
                            LibraryItem(
                                file: file,
                                model: model,
                                isSelecting: isSelecting,
                                isSelected: selection.contains(file.id)
                            ) { extendingRange in
                                select(file, extendingRange: extendingRange)
                            }
                            .onAppear {
                                if file.id == model.uploads.last?.id {
                                    Task { await model.loadMoreUploads() }
                                }
                            }
                        }
                    }
                    .padding(16)
                    footer
                }
            }
        }
        .task {
            if model.uploads.isEmpty { await model.reloadUploads() }
        }
    }

    private var header: some View {
        HStack {
            if let progress = model.deletionProgress {
                ProgressView(value: Double(progress.done), total: Double(progress.total)) {
                    Text("Deleting \(progress.done) of \(progress.total)…")
                }
                .frame(maxWidth: 260)
                Spacer()
            } else if isSelecting {
                Text("\(selection.count) selected")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Select All") { selection = Set(model.uploads.map(\.id)) }
                    .keyboardShortcut("a")
                Button("Deselect All") { selection.removeAll() }
                    .disabled(selection.isEmpty)
                Button("Delete (\(selection.count))…", role: .destructive) {
                    Task { await deleteSelection() }
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(selection.isEmpty)
                Button("Done", action: endSelecting)
                    .keyboardShortcut(.cancelAction)
            } else {
                Text(model.uploads.isEmpty ? "No uploads loaded" : "\(model.uploads.count) uploads")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("After capture, copy", selection: $model.copyFormat) {
                    ForEach(CopyFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .fixedSize()
                Button("Select") { isSelecting = true }
                    .disabled(model.uploads.isEmpty)
                Button {
                    Task { await model.reloadUploads() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .disabled(model.isLoadingUploads)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Toggles a card, or with Shift selects every card between the last one clicked and this one.
    private func select(_ file: UploadedFile, extendingRange: Bool) {
        let ids = model.uploads.map(\.id)
        if extendingRange, let anchorID, let from = ids.firstIndex(of: anchorID), let to = ids.firstIndex(of: file.id) {
            selection.formUnion(ids[min(from, to)...max(from, to)])
        } else if selection.contains(file.id) {
            selection.remove(file.id)
        } else {
            selection.insert(file.id)
        }
        anchorID = file.id
    }

    private func deleteSelection() async {
        let files = model.uploads.filter { selection.contains($0.id) }
        let remaining = await model.delete(files)
        // Keep failed (or cancelled) uploads selected so they can be retried.
        selection = remaining
        if selection.isEmpty { endSelecting() }
    }

    private func endSelecting() {
        isSelecting = false
        selection.removeAll()
        anchorID = nil
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.isLoadingUploads {
            ProgressView("Loading uploads…")
        } else if let error = model.uploadsError {
            ContentUnavailableView {
                Label("Couldn't load uploads", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { Task { await model.reloadUploads() } }
            }
        } else {
            ContentUnavailableView(
                "No uploads yet",
                systemImage: "photo.on.rectangle",
                description: Text("Capture a screenshot and it will appear here.")
            )
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.isLoadingUploads {
            ProgressView()
                .padding(.bottom, 16)
        } else if let error = model.uploadsError {
            VStack(spacing: 8) {
                Text(error).foregroundStyle(.red)
                Button("Try Again") { Task { await model.loadMoreUploads() } }
            }
            .padding(.bottom, 16)
        } else if model.nextCursor != nil {
            Button("Load More") { Task { await model.loadMoreUploads() } }
                .padding(.bottom, 16)
        }
    }
}

private struct LibraryItem: View {
    let file: UploadedFile
    let model: AppModel
    let isSelecting: Bool
    let isSelected: Bool
    /// Called when the card is clicked in selection mode; the flag is true for Shift-click.
    let onSelect: (Bool) -> Void

    private var title: String { file.menuTitle(relativeTo: .now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if isSelecting {
                    onSelect(NSEvent.modifierFlags.contains(.shift))
                } else {
                    model.open(file)
                }
            } label: {
                Color.clear
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .overlay { thumbnail }
                    .overlay(alignment: .bottomLeading) { videoBadge }
                    .overlay(alignment: .topTrailing) { checkbox }
                    .background(.quaternary)
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor, lineWidth: isSelected ? 3 : 0)
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            HStack(spacing: 6) {
                Text(title)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if !isSelecting {
                    itemButtons
                }
            }
        }
        .contextMenu {
            if !isSelecting { actions }
        }
    }

    private var accessibilityLabel: String {
        if isSelecting { return title }
        return file.kind == .video ? "\(title). Open video in browser" : "\(title). Open in browser"
    }

    @ViewBuilder
    private var checkbox: some View {
        if isSelecting {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, isSelected ? Color.accentColor : .black.opacity(0.4))
                .shadow(radius: 2)
                .padding(8)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var itemButtons: some View {
        Button { model.copy(file, as: model.copyFormat) } label: {
            Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help("Copy \(model.copyFormat.title.lowercased())")
        .accessibilityLabel("Copy \(model.copyFormat.title.lowercased())")

        Menu { actions } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions")
        .accessibilityLabel("More actions")
    }

    @ViewBuilder
    private var actions: some View {
        Button("Copy Link") { model.copy(file, as: .pageLink) }
        Button("Copy Markdown") { model.copy(file, as: .markdown) }
        Button("Copy Image Link") { model.copy(file, as: .imageLink) }
        Button("Open in Browser") { model.open(file) }
        if file.kind == .video {
            Button("Make GIF…") { GIFMakerWindow.show(file: file, model: model) }
        }
        Divider()
        Button("Delete…", role: .destructive) { Task { await model.delete([file]) } }
    }

    /// Marks recordings, whose thumbnail is their GIF when they have one, so they are not mistaken for images.
    @ViewBuilder
    private var videoBadge: some View {
        if file.kind == .video {
            Label(file.gif == nil ? "Video" : "Video · GIF", systemImage: "video.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.7), in: .capsule)
                .padding(8)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = file.kind == .image ? file.file : file.gif {
            Thumbnail(url: url)
        } else {
            Image(systemName: "film").font(.largeTitle).foregroundStyle(.secondary)
        }
    }
}
