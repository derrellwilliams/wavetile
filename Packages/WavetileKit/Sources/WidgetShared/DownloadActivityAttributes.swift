import ActivityKit
import Foundation

/// Live Activity for an album/playlist download (Lock Screen + Dynamic Island).
public struct DownloadActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var done: Int
        public var total: Int
        public var progress: Double

        public init(done: Int, total: Int, progress: Double) {
            self.done = done
            self.total = total
            self.progress = progress
        }

        public var isComplete: Bool { total > 0 && done >= total }
    }

    public var collectionID: String
    public var name: String
    public var subtitle: String

    public init(collectionID: String, name: String, subtitle: String) {
        self.collectionID = collectionID
        self.name = name
        self.subtitle = subtitle
    }
}
