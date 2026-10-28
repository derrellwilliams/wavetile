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
        SettingsSection(title: "Podcasts") {
            SettingsToggle(.podcasts, "Show Podcasts", isOn: $podcasts.isEnabled.animation(theme.motion.smooth))
        }
    }
}

/// Podcast settings, from the gear on the Podcasts tab: playback, downloads, sync and
/// import/export. Same sections and rows as the profile drawer.
struct PodcastSettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(PodcastsStore.self) private var podcasts
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var confirmRemove = false
    @State private var confirmRemoveDownloads = false

    var body: some View {
        @Bindable var podcasts = podcasts
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.xxl) {
                    SettingsSection(title: "Playback") {
                        Menu {
                            Picker("Skip Back", selection: $podcasts.skipBack) {
                                ForEach([10.0, 15, 30], id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                            }
                        } label: {
                            SettingsRow(.skipBack, "Skip Back", value: "\(Int(podcasts.skipBack))s")
                        }
                        Menu {
                            Picker("Skip Forward", selection: $podcasts.skipForward) {
                                ForEach([15.0, 30, 45, 60], id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                            }
                        } label: {
                            SettingsRow(.skipForward, "Skip Forward", value: "\(Int(podcasts.skipForward))s")
                        }
                        Menu {
                            Picker("Default Speed", selection: $podcasts.defaultRate) {
                                ForEach(AudioPlayer.podcastRates, id: \.self) { Text("\(Double($0).formatted())×").tag(Double($0)) }
                            }
                        } label: {
                            SettingsRow(.speed, "Default Speed", value: "\(podcasts.defaultRate.formatted())×")
                        }
                    }

                    SettingsSection(title: "Downloads") {
                        Menu {
                            Picker("Auto-Download", selection: $podcasts.autoDownloadCount) {
                                Text("Off").tag(0)
                                Text("Latest Episode").tag(1)
                                Text("Latest 3 Episodes").tag(3)
                                Text("Latest 5 Episodes").tag(5)
                            }
                        } label: {
                            SettingsRow(.download, "Auto-Download", value: podcasts.autoDownloadCount == 0 ? "Off" : "Latest \(podcasts.autoDownloadCount)")
                        }
                        SettingsToggle(.trash, "Remove Played Downloads", isOn: $podcasts.deletePlayedDownloads)
                        SettingsRow(.downloads, "Episode Storage", value: ByteCountFormatter.string(fromByteCount: podcasts.totalBytes, countStyle: .file))
                        Button { confirmRemoveDownloads = true } label: {
                            SettingsRow(.trash, "Remove Episode Downloads", value: "")
                        }
                        .disabled(podcasts.totalBytes == 0)
                    }

                    SettingsSection(title: "Shows") {
                        SettingsToggle(.server, "Sync with Jellyfin", isOn: $podcasts.syncWithJellyfin)
                        Button { showImporter = true } label: {
                            SettingsRow(.download, "Import OPML", value: "")
                        }
                        ShareLink(item: OPMLDocument(text: podcasts.exportOPML()), preview: SharePreview("Wavetile Podcasts.opml")) {
                            SettingsRow(.export, "Export OPML", value: "")
                        }
                        Button { confirmRemove = true } label: {
                            SettingsRow(.trash, "Remove All Podcast Data", value: "")
                        }
                    }
                }
                .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? theme.spacing.md : theme.spacing.xl)
                .padding(.vertical, theme.spacing.lg)
            }
            .scrollIndicators(.hidden)
            .foregroundStyle(theme.palette.textPrimary)
            .themedBackground()
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

/// A settings row with a switch, matching `SettingsRow`.
struct SettingsToggle: View {
    @Environment(\.theme) private var theme
    let glyph: Glyph
    let title: String
    @Binding var isOn: Bool

    init(_ glyph: Glyph, _ title: String, isOn: Binding<Bool>) {
        self.glyph = glyph
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: theme.spacing.md) {
                glyph.image.foregroundStyle(theme.palette.accent)
                Text(title)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.palette.textPrimary)
            }
        }
        .tint(theme.palette.toggle)
        .padding(.horizontal, theme.spacing.lg)
        .padding(.vertical, theme.spacing.sm)
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
