import ActivityKit
import DesignSystem
import SwiftUI
import WidgetKit
import WidgetShared

struct DownloadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            // Lock Screen / banner
            HStack(spacing: 12) {
                (context.state.isComplete ? Glyph.downloaded : Glyph.downloads).image
                    .foregroundStyle(Theme.dark.palette.textPrimary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.name)
                        .font(Theme.dark.typography.itemTitle)
                        .lineLimit(1)
                    Text(status(context.state))
                        .font(Theme.dark.typography.caption)
                        .foregroundStyle(Theme.dark.palette.textSecondary)
                    ProgressView(value: context.state.progress)
                        .tint(Theme.dark.palette.textPrimary)
                }
            }
            .foregroundStyle(Theme.dark.palette.textPrimary)
            .padding()
            .activityBackgroundTint(Theme.dark.palette.background)
            .activitySystemActionForegroundColor(Theme.dark.palette.textPrimary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Glyph.downloads.image.foregroundStyle(Theme.dark.palette.textPrimary)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.name)
                        .font(Theme.dark.typography.itemTitle)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.done)/\(context.state.total)")
                        .font(Theme.dark.typography.mono(.caption))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.progress).tint(Theme.dark.palette.textPrimary)
                }
            } compactLeading: {
                Glyph.downloads.image.foregroundStyle(Theme.dark.palette.textPrimary)
            } compactTrailing: {
                ProgressView(value: context.state.progress)
                    .progressViewStyle(.circular)
                    .tint(Theme.dark.palette.textPrimary)
                    .frame(width: 18, height: 18)
            } minimal: {
                ProgressView(value: context.state.progress)
                    .progressViewStyle(.circular)
                    .tint(Theme.dark.palette.textPrimary)
            }
        }
    }

    private func status(_ state: DownloadActivityAttributes.ContentState) -> String {
        state.isComplete ? "Downloaded · \(state.total) songs" : "Downloading \(state.done) of \(state.total)"
    }
}

#Preview("Download", as: .content, using: DownloadActivityAttributes(collectionID: "1", name: "In Rainbows", subtitle: "Radiohead")) {
    DownloadLiveActivity()
} contentStates: {
    DownloadActivityAttributes.ContentState(done: 4, total: 10, progress: 0.45)
    DownloadActivityAttributes.ContentState(done: 10, total: 10, progress: 1)
}
