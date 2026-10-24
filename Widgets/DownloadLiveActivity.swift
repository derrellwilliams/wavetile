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
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.name)
                        .font(BrandFont.font(.subheadline, weight: .semibold))
                        .lineLimit(1)
                    Text(status(context.state))
                        .font(BrandFont.font(.caption))
                        .foregroundStyle(.white.opacity(0.6))
                    ProgressView(value: context.state.progress)
                        .tint(.white)
                }
            }
            .foregroundStyle(.white)
            .padding()
            .activityBackgroundTint(Color(hex: 0x1A1A1A))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Glyph.downloads.image.foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.name)
                        .font(BrandFont.font(.subheadline, weight: .semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.done)/\(context.state.total)")
                        .font(BrandFont.font(.caption).monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.progress).tint(.white)
                }
            } compactLeading: {
                Glyph.downloads.image.foregroundStyle(.white)
            } compactTrailing: {
                ProgressView(value: context.state.progress)
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .frame(width: 18, height: 18)
            } minimal: {
                ProgressView(value: context.state.progress)
                    .progressViewStyle(.circular)
                    .tint(.white)
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
