import DesignSystem
import Downloads
import JellyfinKit
import Playback
import PreviewSupport
import SwiftUI

/// Profile and settings, revealed under the main UI by `SideDrawer` (opened from the top-right avatar on each tab).
struct SettingsDrawer: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var app: AppModel
    let session: ServerSession
    @Binding var isOpen: Bool
    @State private var confirmSignOut = false
    @State private var confirmRemoveDownloads = false
    @Environment(DownloadsStore.self) private var downloads
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        SettingsForm {
            Section {
                profileHeader
            }
            .listRowBackground(Color.clear)

            Section("Account") {
                SettingsValue("Server", glyph: .server, value: session.serverName)
                SettingsValue("Address", glyph: .address, value: session.serverURL.host() ?? session.serverURL.absoluteString)
                SettingsValue(
                    "Connection",
                    glyph: session.serverURL.scheme == "https" ? .lock : .lockOpen,
                    value: session.serverURL.scheme == "https" ? "Encrypted" : "Unencrypted"
                )
            }

            Section("Appearance") {
                Picker(selection: $app.theme) {
                    ForEach(Theme.all) { theme in
                        Text(theme.name).tag(theme)
                    }
                } label: {
                    Label("Theme", glyph: .appearance)
                }
                .pickerStyle(.menu)
            }

            Section("Playback") {
                @Bindable var player = player
                // Uses Jellyfin's per-song loudness analysis (server 10.9 or later).
                Toggle(isOn: $player.levelsVolume) {
                    Label("Volume Levelling", glyph: .waveform)
                }
            }

            PodcastSettingsSection()

            downloadsSection

            Section {
                Button {
                    confirmSignOut = true
                } label: {
                    Label("Sign Out", glyph: .signOut)
                }
                .confirmationDialog("Sign out of \(session.serverName)?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                    Button("Sign Out", role: .destructive) {
                        Task { await app.signOut() }
                    }
                }
            }
        }
        .enableInjection()
    }

    @ViewBuilder private var downloadsSection: some View {
        @Bindable var downloads = downloads
        Section("Downloads") {
            Picker(selection: $downloads.quality) {
                Text("MP3 (256 kbps)").tag(DownloadManager.Quality.high)
                Text("Original (lossless when possible)").tag(DownloadManager.Quality.original)
            } label: {
                Label("Quality", glyph: .download)
            }
            .pickerStyle(.menu)
            Toggle(isOn: $downloads.allowCellular) {
                Label("Use Cellular Data", glyph: .address)
            }
            SettingsValue("Storage Used", glyph: .downloads, value: ByteCountFormatter.string(fromByteCount: downloads.totalBytes, countStyle: .file))
            Button {
                confirmRemoveDownloads = true
            } label: {
                Label("Remove All Downloads", glyph: .trash)
            }
            .disabled(downloads.totalBytes == 0)
            .confirmationDialog("Remove all downloaded music?", isPresented: $confirmRemoveDownloads, titleVisibility: .visible) {
                Button("Remove All", role: .destructive) { downloads.removeAll() }
            }
        }
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            Avatar()
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text(session.userName)
                    .font(theme.typography.title)
                Text(session.serverName)
                    .font(theme.typography.itemSubtitle)
                    .foregroundStyle(theme.palette.textSecondary)
            }
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        }
        .padding(.top, theme.spacing.lg)
    }
}

#Preview {
    @Previewable @State var isOpen = true
    SettingsDrawer(app: .preview(), session: Fixtures.session, isOpen: $isOpen)
}
