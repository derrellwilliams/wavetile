import DesignSystem
import Playback
import SwiftUI
import UniformTypeIdentifiers

/// The profile drawer's Podcasts section: only the opt-in switch. Everything else lives behind
/// the gear on the Podcasts tab (`PodcastSettingsView`).
struct PodcastSettingsSection: View {
    @Environment(\.theme) private var theme
    @Environment(PodcastsStore.self) private var podcasts

    var body: some View {
        @Bindable var podcasts = podcasts
        Section("Podcasts") {
            Toggle(isOn: $podcasts.isEnabled.animation(theme.motion.smooth)) {
                Label("Show Podcasts", glyph: .podcasts)
            }
        }
    }
}

/// Podcast settings, from the gear on the Podcasts tab: playback, downloads, sync and
/// import/export. Same form style as the profile drawer.
struct PodcastSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PodcastsStore.self) private var podcasts
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var confirmRemove = false
    @State private var confirmRemoveDownloads = false

    var body: some View {
        @Bindable var podcasts = podcasts
        NavigationStack {
            SettingsForm {
                Section("Playback") {
                    Picker(selection: $podcasts.skipBack) {
                        ForEach([10.0, 15, 30], id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                    } label: {
                        Label("Skip Back", glyph: .skipBack)
                    }
                    Picker(selection: $podcasts.skipForward) {
                        ForEach([15.0, 30, 45, 60], id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                    } label: {
                        Label("Skip Forward", glyph: .skipForward)
                    }
                    Picker(selection: $podcasts.defaultRate) {
                        ForEach(AudioPlayer.podcastRates, id: \.self) { Text("\(Double($0).formatted())×").tag(Double($0)) }
                    } label: {
                        Label("Default Speed", glyph: .speed)
                    }
                }
                .pickerStyle(.menu)

                Section("Downloads") {
                    Picker(selection: $podcasts.autoDownloadCount) {
                        Text("Off").tag(0)
                        Text("Latest Episode").tag(1)
                        Text("Latest 3 Episodes").tag(3)
                        Text("Latest 5 Episodes").tag(5)
                    } label: {
                        Label("Auto-Download", glyph: .download)
                    }
                    .pickerStyle(.menu)
                    Toggle(isOn: $podcasts.deletePlayedDownloads) {
                        Label("Remove Played Downloads", glyph: .trash)
                    }
                    SettingsValue("Episode Storage", glyph: .downloads, value: ByteCountFormatter.string(fromByteCount: podcasts.totalBytes, countStyle: .file))
                    Button { confirmRemoveDownloads = true } label: {
                        Label("Remove Episode Downloads", glyph: .trash)
                    }
                    .disabled(podcasts.totalBytes == 0)
                }

                Section("Shows") {
                    Toggle(isOn: $podcasts.syncWithJellyfin) {
                        Label("Sync with Jellyfin", glyph: .server)
                    }
                    Button { showImporter = true } label: {
                        Label("Import OPML", glyph: .download)
                    }
                    ShareLink(item: OPMLDocument(text: podcasts.exportOPML()), preview: SharePreview("Wavetile Podcasts.opml")) {
                        Label("Export OPML", glyph: .export)
                    }
                    Button { confirmRemove = true } label: {
                        Label("Remove All Podcast Data", glyph: .trash)
                    }
                }
            }
            .navigationTitle("Podcast Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", glyph: .check) { dismiss() }
                }
            }
        }
        .opmlImporter(isPresented: $showImporter, message: $importMessage)
        .confirmationDialog("Remove all downloaded episodes?", isPresented: $confirmRemoveDownloads, titleVisibility: .visible) {
            Button("Remove Downloads", role: .destructive) { podcasts.removeAllDownloads() }
        }
        .confirmationDialog("Remove all podcast data?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove Everything", role: .destructive) { Task { await podcasts.removeAllData() } }
        } message: {
            Text("Unfollows every show and deletes progress, Up Next and downloads on this device. With sync on, other devices update too.")
        }
    }
}

/// An OPML export for the share sheet.
struct OPMLDocument: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .xml) { document in
            let url = FileManager.default.temporaryDirectory.appending(path: "Wavetile Podcasts.opml")
            try Data(document.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

/// Which kind of audio a screen shows: the Search (All | Music | Podcasts) and Downloaded
/// (Music | Podcasts) filters.
enum MediaKind: String, CaseIterable, Hashable {
    case all, music, podcasts

    var title: String {
        switch self {
        case .all: "All"
        case .music: "Music"
        case .podcasts: "Podcasts"
        }
    }
}

/// Segmented media filter, shown only when podcasts are on.
struct MediaFilter: View {
    @Environment(\.theme) private var theme
    @Binding var selection: MediaKind
    var options: [MediaKind] = [.music, .podcasts]

    var body: some View {
        Picker("Show", selection: $selection.animation(theme.motion.snappy)) {
            ForEach(options, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, theme.spacing.screenInset)
        .padding(.vertical, theme.spacing.sm)
        .sensoryFeedback(.selection, trigger: selection)
    }
}
