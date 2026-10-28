import DesignSystem
import Persistence
import SwiftUI

/// Download control for an album or playlist (`EpisodeDownloadButton` is the episode twin): download → progress ring → downloaded (menu to remove).
/// Icon-only, for the navigation bar (which supplies the glass); the label is read by VoiceOver.
struct DownloadButton: View {
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var library
    @Environment(DownloadsStore.self) private var downloads
    let collectionID: String
    let onDownload: () -> Void
    @State private var status = DownloadStatus.none
    @State private var confirmRemove = false

    var body: some View {
        Group {
            if status.isRequested {
                Menu {
                    if status.failed > 0 {
                        Button("Retry \(status.failed) Failed", glyph: .download, action: onDownload)
                    }
                    Button("Remove Download", glyph: .trash, role: .destructive) { confirmRemove = true }
                } label: {
                    label
                }
            } else {
                Button(action: onDownload) { label }
            }
        }
        .confirmationDialog("Remove this download?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove Download", role: .destructive) { downloads.remove(collectionID: collectionID) }
        } message: {
            Text("Songs shared with other downloads stay on your device.")
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
        else if status.isInProgress { .inProgress(status.progress) }
        else if status.failed > 0 { .failed }
        else { .none }
    }

    private var title: String {
        if status.isDownloaded { "Downloaded" }
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
                .animation(theme.motion.smooth, value: progress)
        }
        .accessibilityLabel("\(Int(progress * 100))%")
    }
}
