import DesignSystem
import Persistence
import SwiftUI

/// Download control for an album or playlist: download → progress ring → downloaded (menu to remove).
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
        .buttonStyle(.glass)
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
            } catch {}
        }
    }

    @ViewBuilder private var label: some View {
        HStack(spacing: theme.spacing.sm) {
            if status.isDownloaded {
                Glyph.downloaded.image.foregroundStyle(theme.palette.accent)
                Text("Downloaded")
            } else if status.isInProgress {
                ProgressRing(progress: status.progress)
                    .frame(width: 20, height: 20)
                Text("Downloading \(status.done)/\(status.total)")
                    .monospacedDigit()
            } else if status.failed > 0 {
                Glyph.warning.image
                Text("\(status.failed) Failed")
            } else {
                Glyph.download.image
                Text("Download")
            }
        }
        .font(theme.typography.itemTitle)
        .foregroundStyle(theme.palette.textPrimary)
        .contentTransition(.opacity)
        .accessibilityElement(children: .combine)
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
