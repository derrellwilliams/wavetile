import DesignSystem
import SwiftUI

/// Content of the search tab. The search field itself comes from `.searchable` on the
/// `TabView`, which is what makes the system render the detached Liquid Glass search button.
struct SearchView: View {
    @ObserveInjection var inject
    @Binding var text: String

    var body: some View {
        NavigationStack {
            EmptyState(
                text.isEmpty ? "Search Your Library" : "No Results for “\(text)”",
                glyph: .search,
                message: text.isEmpty ? "Find artists, albums, and songs." : "Search arrives with library sync (milestone 3)."
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .themedBackground()
                .reportsTabRoot()
                .navigationTitle("Search")
        }
        // Scoped to this tab's stack so the field doesn't leak into other tabs' navigation bars.
        .searchable(text: $text, prompt: "Artists, albums, songs")
        .enableInjection()
    }
}

#Preview {
    @Previewable @State var text = ""
    TabView {
        Tab { Text("Home") } label: { Label("Home", glyph: .home) }
        Tab(role: .search) { SearchView(text: $text) }
    }
    .tabViewSearchActivation(.searchTabSelection)
}
