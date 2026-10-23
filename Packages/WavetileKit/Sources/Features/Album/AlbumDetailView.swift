import DesignSystem
import JellyfinKit
import PreviewSupport
import SwiftUI

struct AlbumDetailView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @State var model: AlbumDetailModel

    var body: some View {
        ScrollView {
            VStack(spacing: theme.spacing.xl) {
                VStack(spacing: theme.spacing.md) {
                    ArtworkHero(artwork: model.artwork)
                    header
                }
                trackList
            }
            .padding(.bottom, theme.spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .themedBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .enableInjection()
    }

    private var header: some View {
        VStack(spacing: theme.spacing.xs) {
            Text(model.album.title)
                .font(theme.typography.title)
                .foregroundStyle(theme.palette.textPrimary)
                .multilineTextAlignment(.center)
            Text(model.album.artist)
                .font(theme.typography.sectionHeader)
                .foregroundStyle(theme.palette.accent)
            Text(metadata)
                .font(theme.typography.caption)
                .foregroundStyle(theme.palette.textSecondary)
        }
        .padding(.horizontal, theme.spacing.screenInset)
    }

    private var metadata: String {
        var parts: [String] = []
        if let year = model.album.year { parts.append(String(year)) }
        if !model.tracks.isEmpty {
            parts.append("\(model.tracks.count) songs")
            parts.append(model.totalDuration.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var trackList: some View {
        if model.isLoading {
            ProgressView().padding(theme.spacing.xxl)
        } else if let error = model.errorMessage {
            EmptyState("Something Went Wrong", glyph: .warning, message: error) {
                Button("Retry") { Task { await model.load() } }
                    .buttonStyle(.glass)
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.discs, id: \.number) { disc in
                    if let number = disc.number {
                        Text("Disc \(number)")
                            .font(theme.typography.caption.weight(.semibold))
                            .foregroundStyle(theme.palette.textSecondary)
                            .padding(.horizontal, theme.spacing.screenInset)
                            .padding(.top, theme.spacing.lg)
                            .padding(.bottom, theme.spacing.xs)
                    }
                    ForEach(disc.tracks) { track in
                        TrackRow(
                            title: track.title,
                            subtitle: track.artist == model.album.artist ? nil : track.artist,
                            duration: track.duration,
                            leading: .number(track.trackNumber)
                        )
                        .padding(.horizontal, theme.spacing.screenInset)
                        .padding(.vertical, theme.spacing.md)
                        if track.id != disc.tracks.last?.id {
                            Divider()
                                .overlay(theme.palette.separator)
                                .padding(.leading, theme.spacing.screenInset + 24 + theme.spacing.md)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AlbumDetailView(model: AlbumDetailModel(previewAlbum: Fixtures.albums[0], tracks: Fixtures.tracks))
    }
}
