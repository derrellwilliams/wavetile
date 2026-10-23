import DesignSystem
import SwiftUI

struct LibraryView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme

    private let sections: [(String, Glyph)] = [
        ("Playlists", .playlist),
        ("Artists", .artist),
        ("Albums", .album),
        ("Songs", .song),
        ("Genres", .genre),
    ]

    var body: some View {
        NavigationStack {
            List(sections, id: \.0) { title, symbol in
                NavigationLink {
                    EmptyState(title, glyph: symbol, message: "Arrives with library sync (milestone 3).")
                        .themedBackground()
                } label: {
                    Label(title, glyph: symbol)
                        .font(theme.typography.body)
                }
            }
            .listStyle(.plain)
            .listRowBackground(Color.clear)
            .themedBackground()
            .reportsTabRoot()
            .navigationTitle("Library")
        }
        .enableInjection()
    }
}

#Preview {
    LibraryView()
}
