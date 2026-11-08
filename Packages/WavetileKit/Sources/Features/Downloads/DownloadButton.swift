import DesignSystem
import Persistence
import SwiftUI

/// Download control for an album or playlist (`EpisodeDownloadButton` is the episode twin): download → progress ring → downloaded (menu to remove).
/// Icon-only, for a tinted bar capsule (see `TintedBarCapsule`); the label is read by VoiceOver.
struct DownloadButton: View {
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var library
    @Environment(DownloadsStore.self) private var downloads
    let collectionID: String
    /// False when there's nothing to download (an empty playlist or collection). Only Download and
    /// Retry turn off; removing an existing download always works.
    var canDownload = true
    let onDownload: () -> Void
    @State private var status = DownloadStatus.none
    @State private var showStatus = false

    var body: some View {
        Group {
            if status.isRequested {
                Button { showStatus = true } label: { label }
            } else {
                // Downloading needs the server; removing a download (above) works offline.
                Button(action: onDownload) { label }
                    .disabled(!canDownload)
                    .requiresServer()
            }
        }
        // On the control itself: in a bar capsule a Menu drops its label's accessibility label,
        // leaving the Downloaded check unnamed.
        .accessibilityLabel(title)
        .sheet(isPresented: $showStatus) {
            DownloadStatusSheet(collectionID: collectionID)
        }
        .sensoryFeedback(.success, trigger: status.isDownloaded) { _, done in done }
        .task(id: collectionID) {
            do {
                for try await value in library.observe(library.database.downloadStatus(collectionID: collectionID)) {
                    withAnimation(theme.motion.smooth) { status = value }
                }
            } catch { Log.observationFailed(error) }
        }
    }

    private var label: some View {
        DownloadIcon(state: indicator, title: title)
    }

    private var indicator: DownloadIndicator {
        if status.isDownloaded { .done }
        else if status.paused > 0 { .none }
        else if status.isInProgress { .inProgress(status.progress) }
        else if status.failed > 0 { .failed }
        else { .none }
    }

    private var title: String {
        if status.isDownloaded { "Downloaded" }
        else if status.paused > 0 { "Download paused" }
        else if status.isInProgress { "Downloading \(status.done) of \(status.total)" }
        else if status.failed > 0 { "\(status.failed) Failed" }
        else { "Download" }
    }
}

/// Where a download stands, for the shared icon (albums, playlists and episodes).
enum DownloadIndicator: Equatable {
    case none, inProgress(Double), done, failed
}

/// The download glyph for each state: download → progress ring → check, or a warning.
/// Icon-only; `title` is what VoiceOver reads.
struct DownloadIcon: View {
    let state: DownloadIndicator
    let title: String
    /// Nil keeps the glyphs at their natural 24pt (toolbars); rows pass a smaller size.
    var size: CGFloat?

    var body: some View {
        Label { Text(title) } icon: { icon }
            .labelStyle(.iconOnly)
            .contentTransition(.opacity)
    }

    @ViewBuilder private var icon: some View {
        switch state {
        case .done: glyph(.downloaded)
        case let .inProgress(progress): ProgressRing(progress: progress).frame(width: size ?? 20, height: size ?? 20)
        case .failed: glyph(.warning)
        case .none: glyph(.download)
        }
    }

    @ViewBuilder private func glyph(_ glyph: Glyph) -> some View {
        if let size {
            glyph.image.resizable().frame(width: size, height: size)
        } else {
            glyph.image
        }
    }
}

struct ProgressRing: View {
    @Environment(\.theme) private var theme
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(theme.palette.textPrimary.opacity(0.2), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.04, progress))
                .stroke(theme.palette.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(theme.motion.progress, value: progress)
        }
        .accessibilityLabel("\(Int(progress * 100))%")
    }
}


// Progress is based on completed songs and received bytes; a response without a length
// cannot supply a truthful percentage or prove that the server is transcoding.
struct DownloadStatusSheet: View {
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var library
    @Environment(DownloadsStore.self) private var downloads
    @Environment(\.dismiss) private var dismiss
    let collectionID: String
    @State private var tracks: [DownloadedTrackRecord] = []
    @State private var error: String?
    @State private var busy = false
    @State private var confirmCancel = false

    private var paused: Bool { tracks.contains { $0.state == .paused } }
    private var done: Int { tracks.filter { $0.state == .done }.count }
    private var received: Int64 { tracks.filter { $0.state == .downloading }.reduce(0) { $0 + $1.bytes } }

    private var message: String {
        if done == tracks.count && !tracks.isEmpty { return "Downloaded" }
        if paused { return "Paused" }
        if !Connectivity.shared.hasNetwork { return "Waiting for a network connection" }
        if !Connectivity.shared.serverReachable { return "Can’t reach your server" }
        if received > 0 {
            return "Downloading · \(ByteCountFormatter.string(fromByteCount: received, countStyle: .file)) received for unfinished songs"
        }
        if let failure = tracks.first(where: { $0.state == .failed })?.error { return failure }
        return "Waiting for Jellyfin to send audio…"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(message)
                    Text("\(done) of \(tracks.count) songs downloaded")
                        .font(theme.typography.itemMetadata)
                    if done < tracks.count {
                        Text("Jellyfin may convert audio to match your download quality or a supported format. Conversion can take longer; the server has not confirmed whether these songs need conversion.")
                        Text("Pausing keeps completed songs. An unfinished song restarts when resumed. Shared songs are paused in other downloads too.")
                    }
                    if let error { Text(error) }
                }
                if done < tracks.count {
                    Section {
                        Button(paused ? "Resume Download" : "Pause Download") {
                            perform {
                                if paused { try await downloads.resume(collectionID: collectionID) }
                                else { try await downloads.pause(collectionID: collectionID) }
                            }
                        }
                        if tracks.contains(where: { $0.state == .failed }) {
                            Button("Retry Failed Songs") {
                                perform { try await downloads.resume(collectionID: collectionID) }
                            }
                        }
                    }
                    .disabled(busy)
                }
                Section {
                    Button("Cancel and Remove Download", role: .destructive) { confirmCancel = true }
                }
            }
            .font(theme.typography.itemTitle)
            .navigationTitle("Download Status")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Remove this download?", isPresented: $confirmCancel, titleVisibility: .visible) {
                Button("Remove Download", role: .destructive) {
                    downloads.remove(collectionID: collectionID)
                    dismiss()
                }
            } message: {
                Text("Completed songs are removed unless another download uses them.")
            }
            .task {
                do {
                    for try await value in library.observe(library.database.downloadTracks(collectionID: collectionID)) {
                        tracks = value
                    }
                } catch { self.error = error.localizedDescription }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do { try await operation() } catch { self.error = error.localizedDescription }
        }
    }
}
