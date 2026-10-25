import DesignSystem
import Persistence
import SwiftUI

/// Download control for an album or playlist: download → progress ring → downloaded (menu to remove).
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
        Label { Text(title) } icon: { icon }
            .labelStyle(.iconOnly)
            .contentTransition(.opacity)
    }

    private var title: String {
        if status.isDownloaded { "Downloaded" }
        else if status.isInProgress { "Downloading \(status.done) of \(status.total)" }
        else if status.failed > 0 { "\(status.failed) Failed" }
        else { "Download" }
    }

    @ViewBuilder private var icon: some View {
        if status.isDownloaded {
            Glyph.downloaded.image
        } else if status.isInProgress {
            ProgressRing(progress: status.progress)
                .frame(width: 20, height: 20)
        } else if status.failed > 0 {
            Glyph.warning.image
        } else {
            Glyph.download.image
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
        .accessibilityLabel("\(Int(progress * 100)) percent")
    }
}
