import DesignSystem
import Library
import Persistence
import SwiftUI

struct GenresView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store
    @State private var genres: [GenreSummary] = []

    var body: some View {
        List(genres) { genre in
            NavigationLink(value: LibraryRoute.genre(genre.genre)) {
                HStack {
                    Text(genre.genre)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.palette.textPrimary)
                    Spacer()
                    Text("\(genre.albumCount)")
                        .font(theme.typography.itemSubtitle.monospacedDigit())
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .overlay {
            if genres.isEmpty { LibraryEmptyState() }
        }
        .themedBackground()
        .navigationTitle("Genres")
        .task {
            do {
                for try await value in store.observe(store.database.genres()) { genres = value }
            } catch {}
        }
        .enableInjection()
    }
}
