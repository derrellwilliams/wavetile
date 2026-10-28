import DesignSystem
import Podcasts
import SwiftUI

/// Latest, Saved, Downloaded and Recently Played episodes.
struct EpisodeListView: View {
    @Environment(\.theme) private var theme
    @Environment(PodcastsStore.self) private var podcasts
    let list: EpisodeList
    @State private var items: [EpisodeItem] = []
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            if list == .downloaded {
                PodcastDownloadsList(items: items)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        EpisodeRow(item: item)
                        Divider().overlay(theme.palette.separator)
                    }
                }
                .padding(.horizontal, theme.spacing.screenInset)
            }
        }
        .overlay {
            if didLoad && items.isEmpty { emptyState }
        }
        .themedBackground()
        .navigationTitle(list.title)
        .markRefreshable { if list == .latest { await podcasts.refreshAll() } }
        .task {
            let observation = switch list {
            case .latest: podcasts.database.latestEpisodes(limit: 200)
            case .saved: podcasts.database.saved()
            case .downloaded: podcasts.database.downloads()
            case .history: podcasts.database.history()
            }
            do {
                for try await value in podcasts.observe(observation) {
                    withAnimation(didLoad ? theme.motion.smooth : nil) { items = value }
                    didLoad = true
                }
            } catch { Log.observationFailed(error) }
        }
    }

    @ViewBuilder private var emptyState: some View {
        switch list {
        case .latest: EmptyState("No New Episodes", glyph: .podcasts, message: "New episodes from shows you follow appear here.")
        case .saved: EmptyState("No Saved Episodes", glyph: .save, message: "Save episodes to find them here later.")
        case .downloaded: EmptyState("No Downloads", glyph: .downloads, message: "Download episodes to listen offline.")
        case .history: EmptyState("Nothing Played Yet", glyph: .history, message: "Episodes you listen to appear here.")
        }
    }
}

/// Downloaded episodes grouped by show, with swipe-free removal from each row's menu.
/// Shared by the Podcasts tab's Downloaded list and the Downloaded tab's Podcasts filter.
struct PodcastDownloadsList: View {
    @Environment(\.theme) private var theme
    let items: [EpisodeItem]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: theme.spacing.xl) {
            ForEach(groups, id: \.show.id) { group in
                VStack(alignment: .leading, spacing: 0) {
                    NavigationLink(value: PodcastRoute.show(ShowRoute(group.show))) {
                        HStack(spacing: theme.spacing.md) {
                            ArtworkView(.unsized(group.show.artworkURL, maxPixelWidth: 120), cornerRadius: theme.radius.small)
                                .frame(width: 32)
                            Text(group.show.title)
                                .font(theme.typography.sectionHeader)
                                .foregroundStyle(theme.palette.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isHeader)
                    ForEach(group.items) { item in
                        EpisodeRow(item: item, showsArtwork: false)
                        Divider().overlay(theme.palette.separator)
                    }
                }
            }
        }
        .padding(.horizontal, theme.spacing.screenInset)
        .padding(.vertical, theme.spacing.lg)
    }

    private var groups: [(show: ShowRecord, items: [EpisodeItem])] {
        var order: [String] = []
        var byShow: [String: (show: ShowRecord, items: [EpisodeItem])] = [:]
        for item in items {
            if byShow[item.show.id] == nil {
                order.append(item.show.id)
                byShow[item.show.id] = (item.show, [])
            }
            byShow[item.show.id]?.items.append(item)
        }
        return order.compactMap { byShow[$0] }
    }
}

/// Paste a feed link (RSS URL, or a `feed://` / `podcast://` link) to follow any show,
/// including private feeds that aren't in Apple's directory.
struct AddFeedSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(PodcastsStore.self) private var podcasts
    @Environment(\.pushPodcastRoute) private var push
    @State private var text = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: theme.spacing.lg) {
                Text("Paste the show's RSS feed link. Private feeds (Patreon, Supercast and others) work too and stay on this device.")
                    .font(theme.typography.itemSubtitle)
                    .foregroundStyle(theme.palette.textSecondary)
                TextField("https://example.com/feed.xml", text: $text)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .padding(theme.spacing.md)
                    .background(theme.palette.surface, in: .rect(cornerRadius: 8))
                    .onSubmit(add)
                if let errorMessage {
                    Label(errorMessage, glyph: .warning)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.palette.textSecondary)
                }
                PrimaryButton("Follow", isWorking: isWorking, action: add)
                    .disabled(feedURL == nil || isWorking)
                Spacer()
            }
            .padding(theme.spacing.screenInset)
            .themedBackground()
            .navigationTitle("Add by Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", glyph: .close) { dismiss() }
                }
            }
            // No automatic clipboard read: it would trigger the system paste prompt.
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
        .presentationBackground(theme.palette.background)
    }

    private var feedURL: URL? {
        URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap(PodcastNetwork.secure)
    }

    private func add() {
        guard let url = feedURL, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                let show = try await podcasts.follow(feedURL: url)
                dismiss()
                push(.show(ShowRoute(show)))
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}

/// Shown the first time podcasts are turned on: where shows come from, privacy, and how to start.
struct PodcastsIntroSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(PodcastsStore.self) private var podcasts
    var onFindShows: () -> Void
    var onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xl) {
            Glyph.podcasts.image
                .resizable()
                .frame(width: 44, height: 44)
                .foregroundStyle(theme.palette.accent)
                .padding(.top, theme.spacing.xl)
            Text("Podcasts, Next to Your Music")
                .font(theme.typography.largeTitle)
                .tracking(theme.typography.displayTracking)
                .foregroundStyle(theme.palette.textPrimary)
            VStack(alignment: .leading, spacing: theme.spacing.lg) {
                point(.search, "Find any show", "Search Apple Podcasts, browse top charts, or paste a feed link.")
                point(.address, "Straight from the source", "Your phone downloads episodes directly from each podcast's publisher, which can see your IP address, like in any podcast app.")
                point(.server, "Synced with Jellyfin", "Shows and progress sync through your Jellyfin account, so they follow you to other devices. Server admins can see the shows you follow. Turn sync off anytime in Settings.")
            }
            Spacer(minLength: 0)
            VStack(spacing: theme.spacing.sm) {
                PrimaryButton("Find Shows") {
                    finish()
                    onFindShows()
                }
                Button("Import from Another App") {
                    finish()
                    onImport()
                }
                .font(theme.typography.body.weight(.semibold))
                .foregroundStyle(theme.palette.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
                Button("Not Now") { finish() }
                    .font(theme.typography.body)
                    .foregroundStyle(theme.palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, theme.spacing.xl)
        .padding(.bottom, theme.spacing.lg)
        .background(theme.palette.background.ignoresSafeArea())
        .interactiveDismissDisabled()
    }

    private func finish() {
        podcasts.hasSeenIntro = true
        dismiss()
    }

    private func point(_ glyph: Glyph, _ title: String, _ message: String) -> some View {
        HStack(alignment: .top, spacing: theme.spacing.md) {
            glyph.image
                .foregroundStyle(theme.palette.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text(title)
                    .font(theme.typography.body.weight(.semibold))
                    .foregroundStyle(theme.palette.textPrimary)
                Text(message)
                    .font(theme.typography.itemSubtitle)
                    .foregroundStyle(theme.palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
