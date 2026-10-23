import DesignSystem
import SwiftUI

struct DownloadedView: View {
    @ObserveInjection var inject

    var body: some View {
        NavigationStack {
            EmptyState(
                "No Downloads",
                glyph: .downloads,
                message: "Albums and playlists you download for offline listening appear here."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .themedBackground()
            .reportsTabRoot()
            .navigationTitle("Downloaded")
        }
        .enableInjection()
    }
}

#Preview {
    DownloadedView()
}
