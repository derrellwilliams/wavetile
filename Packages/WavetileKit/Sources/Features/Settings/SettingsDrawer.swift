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
    @State private var signOutFailed = false
    @State private var confirmRemoveDownloads = false
    @State private var showStorage = false
    @Environment(DownloadsStore.self) private var downloads
    @Environment(PodcastsStore.self) private var podcasts
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

            Section("About") {
                PrivacyPolicyLink()
            }

            Section {
                Button {
                    confirmSignOut = true
                } label: {
                    Label("Sign Out", glyph: .signOut)
                }
                .confirmationDialog("Sign out of \(session.serverName)?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                    Button("Sign Out", role: .destructive) {
                        Task { signOutFailed = !(await app.signOut()) }
                    }
                }
            }
        }
        .alert("Couldn’t Sign Out", isPresented: $signOutFailed) {
            Button("OK") {}
        } message: {
            Text("Close and reopen Wavetile, then try signing out again.")
        }
        .enableInjection()
    }

    /// What Storage Used counts and Remove All Downloads clears: music, plus episodes when podcasts are on.
    private var storageBytes: Int64 { downloads.totalBytes + (podcasts.isEnabled ? podcasts.totalBytes : 0) }

    @ViewBuilder private var downloadsSection: some View {
        @Bindable var downloads = downloads
        Section("Downloads") {
            Menu {
                Picker("Quality", selection: $downloads.quality) {
                    Text("MP3 (256 kbps)").tag(DownloadManager.Quality.high)
                    Text("Original (lossless when possible)").tag(DownloadManager.Quality.original)
                }
            } label: {
                LabeledContent {
                    Text(downloads.quality == .high ? "MP3" : "Original")
                } label: {
                    Label("Quality", glyph: .download)
                }
            }
            Toggle(isOn: $downloads.allowCellular) {
                Label("Use Cellular Data", glyph: .address)
            }
            Button { showStorage = true } label: {
                SettingsValue("Storage Used", glyph: .downloads, value: StorageView.size(storageBytes))
            }
            .accessibilityHint("Shows what is using space and lets you remove downloads")
            .sheet(isPresented: $showStorage) { StorageView() }
            Button {
                confirmRemoveDownloads = true
            } label: {
                Label("Remove All Downloads", glyph: .trash)
            }
            .disabled(storageBytes == 0)
            .confirmationDialog(podcasts.isEnabled ? "Remove all downloaded music and episodes?" : "Remove all downloaded music?", isPresented: $confirmRemoveDownloads, titleVisibility: .visible) {
                Button("Remove All", role: .destructive) {
                    downloads.removeAll()
                    if podcasts.isEnabled { podcasts.removeAllDownloads() }
                }
            }
        }
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            Avatar()
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text(session.userName)
                    .font(theme.typography.title)
                // Only when it adds something: the server's main account is named the same as the server.
                if session.serverName.caseInsensitiveCompare(session.userName) != .orderedSame {
                    Text(session.serverName)
                        .font(theme.typography.itemSubtitle)
                        .foregroundStyle(theme.palette.textSecondary)
                }
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
