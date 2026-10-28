import DesignSystem
import SwiftUI

/// Text that would crowd a page, such as an artist's bio.
struct AboutSheet: View {
    struct Section: Identifiable {
        var id: String { title }
        let title: String
        let text: String
    }

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let sections: [Section]
    /// A closing line, such as an album's release date.
    var footnote: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.xl) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: theme.spacing.sm) {
                            Text(section.title)
                                .font(theme.typography.headline)
                                .foregroundStyle(theme.palette.textPrimary)
                                .accessibilityAddTraits(.isHeader)
                            Text(section.text)
                                // A step up from page body text: this sheet is for reading.
                                .font(theme.typography.lead)
                                .lineSpacing(6)
                                .foregroundStyle(theme.palette.textPrimary)
                                .textSelection(.enabled)
                        }
                    }
                    if let footnote {
                        Text(footnote)
                            .font(theme.typography.itemSubtitle)
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(theme.spacing.screenInset)
            }
            .themedBackground()
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Read-only, so it closes rather than confirms (Done is for finishing a task).
                ToolbarItem(placement: .cancellationAction) { Button("Close", glyph: .close) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.palette.background)
    }
}
