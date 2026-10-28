import SwiftUI

/// A description clipped to a few lines, with Read More set into the end of the last line
/// (show descriptions, artist bios). Read More expands in place, or runs `readMore` instead
/// (the artist bio opens a sheet).
public struct ExpandableText: View {
    @Environment(\.theme) private var theme
    private let text: String
    private let lineLimit: Int
    private let readMore: (() -> Void)?
    @State private var isExpanded = false
    @State private var full: CGFloat = 0
    @State private var clipped: CGFloat = 0

    public init(_ text: String, lineLimit: Int = 3, readMore: (() -> Void)? = nil) {
        self.text = text
        self.lineLimit = lineLimit
        self.readMore = readMore
    }

    public var body: some View {
        Text(text)
            .font(theme.typography.body)
            .foregroundStyle(theme.palette.textSecondary)
            .lineLimit(isExpanded ? nil : lineLimit)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Compares the clipped height with the full one, so Read More shows only when needed.
            .background {
                Text(text)
                    .font(theme.typography.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { full = $0 }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { clipped = $0 }
            .overlay(alignment: .bottomTrailing) {
                if isTruncated, !isExpanded { readMoreButton }
            }
    }

    /// Sits over the end of the last line; the text fades out under it, as in Apple Music.
    private var readMoreButton: some View {
        Button {
            if let readMore { return readMore() }
            withAnimation(theme.motion.smooth) { isExpanded = true }
        } label: {
            Text("Read More")
                .font(theme.typography.body.weight(.semibold))
                .foregroundStyle(theme.palette.accent)
                // A wide fade, so the words under it trail off instead of being cut mid-letter.
                .padding(.leading, 56)
                .background {
                    LinearGradient(
                        stops: [
                            .init(color: theme.palette.background.opacity(0), location: 0),
                            .init(color: theme.palette.background, location: 0.42),
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                }
                // Taller than the line it sits on, so it's easy to hit.
                .contentShape(.rect.inset(by: -theme.spacing.md))
        }
        .buttonStyle(.plain)
    }

    private var isTruncated: Bool { full > clipped + 1 }
}
